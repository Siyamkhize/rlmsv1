<?php
/**
 * Facilitator Face Verification Endpoint
 *
 * Receives a live face embedding from the mobile app during facilitator login/clock-in
 * and compares it to ALL of the facilitator's stored enrollment embeddings
 * (front and back camera are treated equally; the best score is used).
 *
 * The comparison happens SERVER-SIDE. Never trust a client-reported match.
 *
 * Expected POST payload:
 * {
 *   "facilitator_id": 123,
 *   "embedding": [0.123, -0.456, ...],   // 192 finite floats from MobileFaceNet
 *   "quality_score": 0.75,               // REQUIRED, 0.0 to 1.0
 *   "liveness_passed": true,             // logged only; client-reported, NOT enforced
 *   "verification_type": "login",        // or "clock_in", "clock_out", "enrollment_test"
 *   "device_info": "Samsung Galaxy S21, Android 12, App v1.0.7"
 * }
 *
 * Returns (score and threshold are NOT returned unless FACE_DEBUG_RESPONSE is true):
 * {
 *   "success": true,
 *   "verified": true/false,
 *   "log_id": 123,   // reference to facilitator_face_verification_log
 *   "message": "Face verification successful"
 * }
 *
 * Errors: { "success": false, "verified": false, "error": true,
 *           "code": "quality_too_low" | "not_enrolled" | "locked_out" | ..., "message": "..." }
 *   400 bad input / quality / not enrolled, 401 unauthorized, 429 locked out, 500 server error
 *
 * Written to run on PHP 5.6 and 8.1+ (no ?? operator, no scalar type hints).
 */

header('Content-Type: application/json');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

// Handle preflight requests
if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    exit(0);
}

// Log errors server-side; never emit HTML warnings into JSON responses
error_reporting(E_ALL);
ini_set('display_errors', 0);
ini_set('log_errors', 1);

// Include database connection and face recognition config
require_once '../connection.php';
require_once 'face_recognition_config.php';

/**
 * An error that is safe to show to the client (fixed message, no internals).
 */
class FaceVerifyClientError extends Exception {
    public $errorCode;
    public $httpStatus;

    public function __construct($message, $errorCode = 'bad_request', $httpStatus = 400) {
        parent::__construct($message);
        $this->errorCode = $errorCode;
        $this->httpStatus = $httpStatus;
    }
}

/**
 * Write one row to facilitator_face_verification_log. Returns the new log id (0 on failure).
 */
function logFaceAttempt($conn, $facilitator_id, $similarity, $passed, $verification_type,
                        $liveness_passed, $quality_score, $ip_address, $device_info) {
    $log_stmt = $conn->prepare("
        INSERT INTO facilitator_face_verification_log
        (facilitator_id, similarity_score, threshold_used, passed, verification_type,
         liveness_passed, quality_score, ip_address, device_info)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ");
    if (!$log_stmt) {
        error_log('[FAC_FACE_VERIFY] Failed to prepare log insert: ' . $conn->error);
        return 0;
    }

    $threshold = FACE_MATCH_THRESHOLD;
    $passed_int = $passed ? 1 : 0;
    $liveness_int = ($liveness_passed === true) ? 1 : 0;
    $quality_val = ($quality_score === null) ? 0.0 : $quality_score;

    $log_stmt->bind_param(
        'iddisidss',
        $facilitator_id,
        $similarity,
        $threshold,
        $passed_int,
        $verification_type,
        $liveness_int,
        $quality_val,
        $ip_address,
        $device_info
    );
    $log_stmt->execute();
    $log_id = $conn->insert_id;
    $log_stmt->close();

    return $log_id;
}

// Only accept POST requests
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(array(
        'success' => false,
        'message' => 'Method not allowed. Use POST.'
    ));
    exit;
}

try {
    // Get POST data
    $input = json_decode(file_get_contents('php://input'), true);

    if (json_last_error() !== JSON_ERROR_NONE || !is_array($input)) {
        throw new FaceVerifyClientError('Invalid request', 'invalid_request');
    }

    // Validate required fields
    if (!isset($input['facilitator_id']) || !isset($input['embedding'])) {
        throw new FaceVerifyClientError('Missing required fields', 'invalid_request');
    }

    $facilitator_id = intval($input['facilitator_id']);
    if ($facilitator_id <= 0) {
        throw new FaceVerifyClientError('Invalid request', 'invalid_request');
    }

    // ------------------------------------------------------------------
    // TODO (REQUIRED BEFORE PRODUCTION): authenticate the caller.
    // Use the same token/session check as your other /mobile/ endpoints and
    // make sure the authenticated user is allowed to verify THIS facilitator_id.
    // ------------------------------------------------------------------

    // Optional fields (validated, never trusted)
    $verification_type = 'login';
    if (isset($input['verification_type']) && is_string($input['verification_type'])
        && in_array($input['verification_type'], array('login', 'clock_in', 'clock_out', 'enrollment_test'), true)) {
        $verification_type = $input['verification_type'];
    }

    $liveness_passed = null;
    if (isset($input['liveness_passed'])) {
        $liveness_passed = filter_var($input['liveness_passed'], FILTER_VALIDATE_BOOLEAN, FILTER_NULL_ON_FAILURE);
    }

    $quality_score = null;
    if (isset($input['quality_score']) && is_numeric($input['quality_score'])) {
        $q = floatval($input['quality_score']);
        if (is_finite($q) && $q >= 0.0 && $q <= 1.0) {
            $quality_score = $q;
        }
    }

    $device_info = (isset($input['device_info']) && is_string($input['device_info']))
        ? substr($input['device_info'], 0, 255)
        : '';

    // Use REMOTE_ADDR only. X-Forwarded-For is client-controlled and spoofable.
    $ip_address = isset($_SERVER['REMOTE_ADDR']) ? substr($_SERVER['REMOTE_ADDR'], 0, 45) : '';

    // ------------------------------------------------------------------
    // Lockout: too many recent failed attempts for this facilitator
    // ------------------------------------------------------------------
    $lock_sql = "SELECT COUNT(*) FROM facilitator_face_verification_log
                 WHERE facilitator_id = ? AND passed = 0
                   AND " . FACE_LOG_TIME_COLUMN . " > (NOW() - INTERVAL " . intval(FACE_LOCKOUT_WINDOW_MINUTES) . " MINUTE)";
    $lock_stmt = $conn->prepare($lock_sql);
    if (!$lock_stmt) {
        error_log('[FAC_FACE_VERIFY] Lockout query failed: ' . $conn->error);
        throw new Exception('Lockout query could not be prepared');
    }
    $lock_stmt->bind_param('i', $facilitator_id);
    $lock_stmt->execute();
    $recent_failures = 0;
    $lock_stmt->bind_result($recent_failures);
    $lock_stmt->fetch();
    $lock_stmt->close();

    if ($recent_failures >= FACE_MAX_FAILED_ATTEMPTS) {
        throw new FaceVerifyClientError(
            'Too many failed attempts. Please try again later.',
            'locked_out',
            429
        );
    }

    // ------------------------------------------------------------------
    // Validate the live embedding (finite numbers, correct length)
    // ------------------------------------------------------------------
    $validated_embedding = validateEmbedding($input['embedding']);
    if ($validated_embedding === false) {
        // Malformed embeddings are suspicious: log them as failures (counts toward lockout)
        logFaceAttempt($conn, $facilitator_id, -1.0, false, $verification_type,
                       $liveness_passed, $quality_score, $ip_address, $device_info);
        throw new FaceVerifyClientError('Invalid request', 'invalid_embedding');
    }

    // Quality score is REQUIRED (omitting it must not bypass the check)
    if ($quality_score === null || $quality_score < MIN_VERIFICATION_QUALITY) {
        error_log('[FAC_FACE_VERIFY] Low or missing quality for facilitator ' . $facilitator_id);
        throw new FaceVerifyClientError('Image quality too low, please retake', 'quality_too_low');
    }

    // ------------------------------------------------------------------
    // Fetch ALL stored enrollment embeddings (front and back camera)
    // ------------------------------------------------------------------
    $stmt = $conn->prepare("
        SELECT id, embedding_vector, camera_facing
        FROM facilitator_face
        WHERE facilitator_id = ? AND active = 1
    ");
    if (!$stmt) {
        throw new Exception('Failed to prepare enrollment lookup: ' . $conn->error);
    }
    $stmt->bind_param('i', $facilitator_id);
    $stmt->execute();
    $result = $stmt->get_result();

    $stored_embeddings = array();
    while ($row = $result->fetch_assoc()) {
        // Same strict validation as the live embedding (finite numbers, correct length)
        $embedding_data = validateEmbedding($row['embedding_vector']);
        if ($embedding_data === false) {
            error_log('[FAC_FACE_VERIFY] Skipping invalid stored embedding id ' . $row['id']);
            continue;
        }
        $stored_embeddings[] = array(
            'id' => $row['id'],
            'embedding' => $embedding_data,
            'camera_facing' => $row['camera_facing']
        );
    }
    $stmt->close();

    if (empty($stored_embeddings)) {
        error_log('[FAC_FACE_VERIFY] No valid enrollment for facilitator ' . $facilitator_id);
        throw new FaceVerifyClientError('Face enrollment required', 'not_enrolled');
    }

    // ------------------------------------------------------------------
    // Compare against ALL stored embeddings (SERVER-SIDE ONLY), use the best score
    // ------------------------------------------------------------------
    $best_score = -1.0;
    $matched_camera = null;

    foreach ($stored_embeddings as $stored) {
        $score = computeCosineSimilarity($validated_embedding, $stored['embedding']);
        if ($score > $best_score) {
            $best_score = $score;
            $matched_camera = $stored['camera_facing'];
        }
    }

    $verified = isFaceMatch($best_score);

    // Log the attempt (pass or fail). The score stays server-side.
    $log_id = logFaceAttempt($conn, $facilitator_id, $best_score, $verified, $verification_type,
                             $liveness_passed, $quality_score, $ip_address, $device_info);

    // Fetch facilitator name for confirmation modal (only if verified successfully)
    $facilitator_name = '';
    $facilitator_surname = '';
    $full_name = 'Unknown Facilitator';
    
    if ($verified) {
        $name_stmt = $conn->prepare("SELECT firstName, lastName FROM facilitator WHERE facilitator_id = ? LIMIT 1");
        if ($name_stmt) {
            $name_stmt->bind_param('i', $facilitator_id);
            $name_stmt->execute();
            $name_result = $name_stmt->get_result();
            
            if ($name_result && $name_result->num_rows > 0) {
                $facilitator_data = $name_result->fetch_assoc();
                $facilitator_name = isset($facilitator_data['firstName']) ? trim($facilitator_data['firstName']) : '';
                $facilitator_surname = isset($facilitator_data['lastName']) ? trim($facilitator_data['lastName']) : '';
                $full_name = trim($facilitator_name . ' ' . $facilitator_surname);
                if (empty($full_name)) {
                    $full_name = 'Facilitator ' . $facilitator_id;
                }
            }
            $name_stmt->close();
        }
    }

    // Minimal response: no score, threshold or camera details for the client
    $response = array(
        'success' => true,
        'verified' => $verified,
        'log_id' => $log_id,
        'message' => $verified ? 'Face verification successful' : 'Face verification failed'
    );
    
    // Add facilitator name fields if verification passed (for confirmation modal)
    if ($verified) {
        $response['facilitator_id'] = $facilitator_id;
        $response['facilitator_name'] = $facilitator_name;
        $response['facilitator_surname'] = $facilitator_surname;
        $response['full_name'] = $full_name;
    }

    if (FACE_DEBUG_RESPONSE) {
        $response['debug'] = array(
            'similarity_score' => $best_score,
            'threshold' => FACE_MATCH_THRESHOLD,
            'matched_camera' => $verified ? $matched_camera : null,
            'total_embeddings_checked' => count($stored_embeddings)
        );
    }

    echo json_encode($response);

} catch (FaceVerifyClientError $e) {
    http_response_code($e->httpStatus);
    echo json_encode(array(
        'success' => false,
        'verified' => false,
        'error' => true,
        'code' => $e->errorCode,
        'message' => $e->getMessage()
    ));
} catch (Exception $e) {
    // Internal details go to the server log only, never to the client
    error_log('[FAC_FACE_VERIFY] ' . $e->getMessage());
    http_response_code(500);
    echo json_encode(array(
        'success' => false,
        'verified' => false,
        'error' => true,
        'code' => 'server_error',
        'message' => 'Verification could not be completed. Please try again.'
    ));
}
