<?php
/**
 * Save Manual Clock-In
 *
 * Handles clock-in for signature + geofence + face verification method
 * Inserts into: manual_clocking table + manual_clocking_evidence table
 * Stores IMAGE FILENAMES (not base64)
 *
 * A clock-in is only accepted when BOTH the face photo and the signature
 * exist on the server. Partial records are rejected.
 */

header('Content-Type: application/json');
require_once 'connection.php';
require_once '../security_functions.php';
require_once '../idempotency_helpers.php';
require_once 'evidence_helpers.php';

// Do not print PHP warnings into the JSON response
error_reporting(E_ALL);
ini_set('display_errors', 0);
ini_set('log_errors', 1);

// SECURITY: Require authentication
try {
    $user = requireAuth($conn);
    error_log("[SAVE_MANUAL_CLOCKIN] ✅ Authentication successful - User ID: " . $user['user_id']);
} catch (Exception $e) {
    error_log("[SAVE_MANUAL_CLOCKIN] ❌ Authentication failed: " . $e->getMessage());
    throw $e;
}

// SECURITY: Apply rate limiting (15 clock-ins per minute)
try {
    applyRateLimit($conn, 'save_manual_clockin');
    error_log("[SAVE_MANUAL_CLOCKIN] ✅ Rate limit check passed");
} catch (Exception $e) {
    error_log("[SAVE_MANUAL_CLOCKIN] ❌ Rate limit exceeded: " . $e->getMessage());
    throw $e;
}

try {
    // Get JSON input
    $input = json_decode(file_get_contents('php://input'), true);

    if (!$input || !is_array($input)) {
        throw new Exception('Invalid JSON input');
    }
    
    // Extract idempotency key FIRST - before any processing
    $idempotencyKey = $_SERVER['HTTP_X_IDEMPOTENCY_KEY'] ?? ($input['idempotency_key'] ?? null);
    
    if (!$idempotencyKey) {
        throw new Exception('Idempotency key required');
    }
    
    // Check idempotency BEFORE processing
    $existing = idem_begin($conn, $user['user_id'], 'clock_in', $idempotencyKey);
    if ($existing) {
        // Return cached response for duplicate request
        http_response_code($existing['response_code'] ?? 200);
        echo $existing['response_body'];
        error_log("[SAVE_MANUAL_CLOCKIN] ✅ Idempotent response returned for key: $idempotencyKey");
        exit;
    }

    // Required fields
    $learnerID   = isset($input['learner_id']) ? intval($input['learner_id']) : 0;
    $clockDate   = isset($input['clock_date']) ? $input['clock_date'] : date('Y-m-d');
    $clockInTime = isset($input['clock_in_time']) ? $input['clock_in_time'] : null;
    $contactTime = isset($input['contact_time']) ? $input['contact_time'] : null;

    // Evidence data (FILENAMES, not base64)
    $signatureInFilename = isset($input['signature_in']) ? $input['signature_in'] : null;
    $faceInFilename      = isset($input['face_in']) ? $input['face_in'] : null;

    // GPS data
    $latitude  = isset($input['latitude']) ? floatval($input['latitude']) : null;
    $longitude = isset($input['longitude']) ? floatval($input['longitude']) : null;
    $accuracy  = isset($input['accuracy']) ? floatval($input['accuracy']) : null;

    // Basic validation
    if ($learnerID <= 0) {
        throw new Exception('Invalid learner ID');
    }
    requireValidDate($clockDate);

    if (!$clockInTime) {
        throw new Exception('Clock-in time is required');
    }
    requireValidTime($clockInTime, 'Clock-in time');

    // EVIDENCE VALIDATION: both images must exist on the server
    requireEvidenceFile($faceInFilename,      'face',      'in', $learnerID, $clockDate);
    requireEvidenceFile($signatureInFilename, 'signature', 'in', $learnerID, $clockDate);

    // Start transaction
    $conn->begin_transaction();

    // Lock today's row (if any) and make sure the learner has not already clocked in
    $stmt = $conn->prepare("
        SELECT clock_in_time
        FROM manual_clocking
        WHERE LearnerID = ? AND clock_date = ?
        FOR UPDATE
    ");
    $stmt->bind_param("is", $learnerID, $clockDate);
    $stmt->execute();
    $existing = $stmt->get_result()->fetch_assoc();
    $stmt->close();

    if ($existing && !empty($existing['clock_in_time'])) {
        throw new Exception('Already clocked in today.');
    }

    // 1. INSERT OR UPDATE manual_clocking table
    $stmt = $conn->prepare("
        INSERT INTO manual_clocking
        (LearnerID, clock_date, clock_in_time, contact_time, is_manual_attendance)
        VALUES (?, ?, ?, ?, 1)
        ON DUPLICATE KEY UPDATE
            clock_in_time = VALUES(clock_in_time),
            contact_time = VALUES(contact_time)
    ");

    $stmt->bind_param("isss",
        $learnerID,
        $clockDate,
        $clockInTime,
        $contactTime
    );

    if (!$stmt->execute()) {
        throw new Exception('Failed to save manual clocking: ' . $stmt->error);
    }

    $manualId = $stmt->insert_id ?: $conn->insert_id;
    $stmt->close();

    // 2. INSERT OR UPDATE manual_clocking_evidence table (always, both images are validated)
    $stmt = $conn->prepare("
        INSERT INTO manual_clocking_evidence
        (LearnerID, clock_date, signature_in, face_in)
        VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            signature_in = VALUES(signature_in),
            face_in = VALUES(face_in)
    ");

    $stmt->bind_param("isss",
        $learnerID,
        $clockDate,
        $signatureInFilename,
        $faceInFilename
    );

    if (!$stmt->execute()) {
        throw new Exception('Failed to save evidence: ' . $stmt->error);
    }

    $stmt->close();

    // Commit transaction
    $conn->commit();

    // Success response
    $response = [
        'success' => true,
        'message' => 'Clock-in saved successfully',
        'manual_id' => $manualId,
        'learner_id' => $learnerID,
        'clock_date' => $clockDate,
        'clock_in_time' => $clockInTime,
        'evidence' => [
            'signature_in' => $signatureInFilename,
            'face_in' => $faceInFilename
        ],
        'gps' => [
            'latitude' => $latitude,
            'longitude' => $longitude,
            'accuracy' => $accuracy
        ]
    ];
    
    // Mark as complete in idempotency system
    idem_finish($conn, $user['user_id'], $idempotencyKey, 200, json_encode($response));
    
    echo json_encode($response);

} catch (Exception $e) {
    // Rollback on error
    if (isset($conn)) {
        $conn->rollback();
    }
    
    // Abort idempotency (allow retry)
    if (isset($idempotencyKey) && isset($user)) {
        idem_abort($conn, $user['user_id'], $idempotencyKey);
    }

    http_response_code(400);
    echo json_encode([
        'success' => false,
        'error' => $e->getMessage(),
        'message' => $e->getMessage()
    ]);
}

if (isset($conn)) {
    $conn->close();
}
?>
