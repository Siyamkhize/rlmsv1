<?php
/**
 * Save Manual Clock-Out
 *
 * Handles clock-out for signature + geofence + face verification method
 * Updates: manual_clocking table + manual_clocking_evidence table
 * Stores IMAGE FILENAMES (not base64)
 *
 * A clock-out is only accepted when:
 *  - the learner has a COMPLETE clock-in today (time + face + signature)
 *  - the learner has not already clocked out
 *  - BOTH the face photo and the signature for clock-out exist on the server
 * 
 * LAST UPDATED: 2026/11/03 - No changes (existing code)
 */

header('Content-Type: application/json');
require_once 'connection.php';
require_once 'security_functions.php';
require_once 'idempotency_helpers.php';
require_once 'evidence_helpers.php';
require_once 'require_auth.php';

// Do not print PHP warnings into the JSON response
error_reporting(E_ALL);
ini_set('display_errors', 0);
ini_set('log_errors', 1);

// SECURITY: Require authentication
try {
    $user = requireAuth($conn);
    error_log("[SAVE_MANUAL_CLOCKOUT] ✅ Authentication successful - User ID: " . $user['user_id']);
} catch (Exception $e) {
    error_log("[SAVE_MANUAL_CLOCKOUT] ❌ Authentication failed: " . $e->getMessage());
    throw $e;
}

// SECURITY: Apply rate limiting (15 clock-outs per minute)
try {
    applyRateLimit($conn, 'save_manual_clockout');
    error_log("[SAVE_MANUAL_CLOCKOUT] ✅ Rate limit check passed");
} catch (Exception $e) {
    error_log("[SAVE_MANUAL_CLOCKOUT] ❌ Rate limit exceeded: " . $e->getMessage());
    throw $e;
}

try {
    // Get JSON input
    $input = json_decode(file_get_contents('php://input'), true);

    if (!$input || !is_array($input)) {
        throw new Exception('Invalid JSON input');
    }
    
    // Extract idempotency key (optional but recommended)
    $idempotencyKey = $input['idempotency_key'] ?? null;
    
    if ($idempotencyKey && validate_idempotency_key($idempotencyKey)) {
        // Check if this is a duplicate request
        $existing = idem_begin($conn, $user['user_id'], 'manual_clock_out', $idempotencyKey);
        if ($existing !== null) {
            // Return cached response for duplicate request
            error_log("[SAVE_MANUAL_CLOCKOUT] 🔄 Duplicate request detected, returning cached response");
            http_response_code($existing['response_code'] ?? 200);
            echo $existing['response_body'];
            exit;
        }
    }

    // Required fields
    $learnerID    = isset($input['learner_id']) ? intval($input['learner_id']) : 0;
    $clockDate    = isset($input['clock_date']) ? $input['clock_date'] : date('Y-m-d');
    $clockOutTime = isset($input['clock_out_time']) ? $input['clock_out_time'] : null;

    // Evidence data (FILENAMES, not base64)
    $signatureOutFilename = isset($input['signature_out']) ? $input['signature_out'] : null;
    $faceOutFilename      = isset($input['face_out']) ? $input['face_out'] : null;

    // GPS data
    $latitude  = isset($input['latitude']) ? floatval($input['latitude']) : null;
    $longitude = isset($input['longitude']) ? floatval($input['longitude']) : null;
    $accuracy  = isset($input['accuracy']) ? floatval($input['accuracy']) : null;

    // Basic validation
    if ($learnerID <= 0) {
        throw new Exception('Invalid learner ID');
    }
    requireValidDate($clockDate);

    if (!$clockOutTime) {
        throw new Exception('Clock-out time is required');
    }
    requireValidTime($clockOutTime, 'Clock-out time');

    // EVIDENCE VALIDATION: both images must exist on the server
    requireEvidenceFile($faceOutFilename,      'face',      'out', $learnerID, $clockDate);
    requireEvidenceFile($signatureOutFilename, 'signature', 'out', $learnerID, $clockDate);

    // Start transaction
    $conn->begin_transaction();

    // Lock the day's record and check its state
    $stmt = $conn->prepare("
        SELECT m.clock_in_time, m.clock_out_time, e.face_in, e.signature_in
        FROM manual_clocking m
        LEFT JOIN manual_clocking_evidence e
               ON e.LearnerID = m.LearnerID AND e.clock_date = m.clock_date
        WHERE m.LearnerID = ? AND m.clock_date = ?
        FOR UPDATE
    ");
    $stmt->bind_param("is", $learnerID, $clockDate);
    $stmt->execute();
    $row = $stmt->get_result()->fetch_assoc();
    $stmt->close();

    if (!$row || empty($row['clock_in_time'])) {
        throw new Exception('No clock-in record found. Please clock in first.');
    }
    if (empty($row['face_in']) || empty($row['signature_in'])) {
        throw new Exception('Clock-in is incomplete (missing face or signature). Please contact an administrator.');
    }
    if (!empty($row['clock_out_time'])) {
        throw new Exception('Already clocked out today.');
    }

    // 1. UPDATE manual_clocking table
    $stmt = $conn->prepare("
        UPDATE manual_clocking
        SET clock_out_time = ?
        WHERE LearnerID = ?
        AND clock_date = ?
        AND clock_in_time IS NOT NULL
        AND clock_out_time IS NULL
    ");

    $stmt->bind_param("sis",
        $clockOutTime,
        $learnerID,
        $clockDate
    );

    if (!$stmt->execute()) {
        throw new Exception('Failed to save clock-out: ' . $stmt->error);
    }

    $affectedRows = $stmt->affected_rows;
    $stmt->close();

    if ($affectedRows !== 1) {
        throw new Exception('Clock-out was not saved. Please try again.');
    }

    // 2. UPDATE manual_clocking_evidence table (always, both images are validated)
    $stmt = $conn->prepare("
        UPDATE manual_clocking_evidence
        SET signature_out = ?, face_out = ?
        WHERE LearnerID = ?
        AND clock_date = ?
    ");

    $stmt->bind_param("ssis",
        $signatureOutFilename,
        $faceOutFilename,
        $learnerID,
        $clockDate
    );

    if (!$stmt->execute()) {
        throw new Exception('Failed to save evidence: ' . $stmt->error);
    }

    if ($stmt->affected_rows < 1) {
        throw new Exception('Evidence record not found. Clock-out not saved.');
    }

    $stmt->close();

    // Commit transaction
    $conn->commit();

    // Success response
    $responseBody = json_encode([
        'success' => true,
        'message' => 'Clock-out saved successfully',
        'learner_id' => $learnerID,
        'clock_date' => $clockDate,
        'clock_out_time' => $clockOutTime,
        'evidence' => [
            'signature_out' => $signatureOutFilename,
            'face_out' => $faceOutFilename
        ],
        'gps' => [
            'latitude' => $latitude,
            'longitude' => $longitude,
            'accuracy' => $accuracy
        ]
    ]);
    
    // Save response in idempotency table if key was provided
    if (isset($idempotencyKey) && $idempotencyKey) {
        idem_finish($conn, $user['user_id'], $idempotencyKey, 200, $responseBody);
        error_log("[SAVE_MANUAL_CLOCKOUT] ✅ Idempotency key stored: $idempotencyKey");
    }
    
    echo $responseBody;

} catch (Exception $e) {
    // Rollback on error
    if (isset($conn)) {
        $conn->rollback();
    }
    
    // Abort idempotency if this was an idempotent request
    if (isset($idempotencyKey) && $idempotencyKey && isset($user)) {
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