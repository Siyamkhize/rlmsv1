<?php
/**
 * Face Verification Endpoint
 *
 * Receives a live face embedding from the mobile app during clock-in/clock-out
 * and compares it to ALL of the learner's stored enrollment embeddings
 * (front and back camera are treated equally; the best score is used).
 *
 * The comparison happens SERVER-SIDE. Never trust a client-reported match.
 *
 * Expected POST payload:
 * {
 *   "learner_id": 12345,
 *   "embedding": [0.123, -0.456, ...],   // 192 finite floats from MobileFaceNet
 *   "quality_score": 0.75,               // REQUIRED, 0.0 to 1.0
 *   "liveness_passed": true,             // logged only; client-reported, NOT enforced
 *   "verification_type": "clock_in",     // or "clock_out", "enrollment_test"
 *   "device_info": "Samsung Galaxy S21, Android 12, App v1.0.7"
 * }
 *
 * Returns (score and threshold are NOT returned unless FACE_DEBUG_RESPONSE is true):
 * {
 *   "success": true,
 *   "verified": true/false,
 *   "log_id": 123,   // reference to learner_face_verification_log
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
 * Write one row to learner_face_verification_log. Returns the new log id (0 on failure).
 */
function logFaceAttempt($conn, $learner_id, $similarity, $passed, $verification_type,
                        $liveness_passed, $quality_score, $ip_address, $device_info) {
    $log_stmt = $conn->prepare("
        INSERT INTO learner_face_verification_log
        (learner_id, similarity_score, threshold_used, passed, verification_type,
         liveness_passed, quality_score, ip_address, device_info)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ");
    if (!$log_stmt) {
        error_log('[FACE_VERIFY] Failed to prepare log insert: ' . $conn->error);
        return 0;
    }

    $threshold = FACE_MATCH_THRESHOLD;
    $passed_int = $passed ? 1 : 0;
    $liveness_int = ($liveness_passed === true) ? 1 : 0;
    $quality_val = ($quality_score === null) ? 0.0 : $quality_score;

    $log_stmt->bind_param(
        'iddisidss',
        $learner_id,
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
    if (!isset($input['learner_id']) || !isset($input['embedding'])) {
        throw new FaceVerifyClientError('Missing required fields', 'invalid_request');
    }

    $learner_id = intval($input['learner_id']);
    if ($learner_id <= 0) {
        throw new FaceVerifyClientError('Invalid request', 'invalid_request');
    }

    // ------------------------------------------------------------------
    // TODO (REQUIRED BEFORE PRODUCTION): authenticate the caller.
    // Use the same token/session check as your other /mobile/ endpoints and
    // make sure the authenticated user is allowed to verify THIS learner_id.
    // Example shape (wire this to your real auth):
    //
    //   $auth_learner_id = getAuthenticatedLearnerId($conn);
    //   if ($auth_learner_id !== $learner_id) {
    //       throw new FaceVerifyClientError('Unauthorized', 'unauthorized', 401);
    //   }
    // ------------------------------------------------------------------

    // Optional fields (validated, never trusted)
    $verification_type = 'clock_in';
    if (isset($input['verification_type']) && is_string($input['verification_type'])
        && in_array($input['verification_type'], array('clock_in', 'clock_out', 'enrollment_test'), true)) {
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
    // Lockout: too many recent failed attempts for this learner
    // ------------------------------------------------------------------
    $lock_sql = "SELECT COUNT(*) FROM learner_face_verification_log
                 WHERE learner_id = ? AND passed = 0
                   AND " . FACE_LOG_TIME_COLUMN . " > (NOW() - INTERVAL " . intval(FACE_LOCKOUT_WINDOW_MINUTES) . " MINUTE)";
    $lock_stmt = $conn->prepare($lock_sql);
    if (!$lock_stmt) {
        // Fail loudly rather than silently running without a lockout.
        // Most likely cause: FACE_LOG_TIME_COLUMN does not match your table.
        error_log('[FACE_VERIFY] Lockout query failed: ' . $conn->error);
        throw new Exception('Lockout query could not be prepared');
    }
    $lock_stmt->bind_param('i', $learner_id);
    $lock_stmt->execute();
    $recent_failures = 0;
    $lock_stmt->bind_result($recent_failures);
    $lock_stmt->fetch();
    $lock_stmt->close();

    if ($recent_failures >= FACE_MAX_FAILED_ATTEMPTS) {
        throw new FaceVerifyClientError(
            'Too many failed attempts. Please try again later or ask a facilitator.',
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
        logFaceAttempt($conn, $learner_id, -1.0, false, $verification_type,
                       $liveness_passed, $quality_score, $ip_address, $device_info);
        throw new FaceVerifyClientError('Invalid request', 'invalid_embedding');
    }

    // Quality score is REQUIRED (omitting it must not bypass the check)
    if ($quality_score === null || $quality_score < MIN_VERIFICATION_QUALITY) {
        error_log('[FACE_VERIFY] Low or missing quality for learner ' . $learner_id);
        throw new FaceVerifyClientError('Image quality too low, please retake', 'quality_too_low');
    }

    // ------------------------------------------------------------------
    // Fetch ALL stored enrollment embeddings (front and back camera)
    // ------------------------------------------------------------------
    $stmt = $conn->prepare("
        SELECT id, embedding_vector, camera_facing
        FROM learner_face
        WHERE learner_id = ? AND active = 1
    ");
    if (!$stmt) {
        throw new Exception('Failed to prepare enrollment lookup: ' . $conn->error);
    }
    $stmt->bind_param('i', $learner_id);
    $stmt->execute();
    $result = $stmt->get_result();

    $stored_embeddings = array();
    while ($row = $result->fetch_assoc()) {
        // Same strict validation as the live embedding (finite numbers, correct length)
        $embedding_data = validateEmbedding($row['embedding_vector']);
        if ($embedding_data === false) {
            error_log('[FACE_VERIFY] Skipping invalid stored embedding id ' . $row['id']);
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
        error_log('[FACE_VERIFY] No valid enrollment for learner ' . $learner_id);
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
    $log_id = logFaceAttempt($conn, $learner_id, $best_score, $verified, $verification_type,
                             $liveness_passed, $quality_score, $ip_address, $device_info);

    // Minimal response: no score, threshold or camera details for the client
    $response = array(
        'success' => true,
        'verified' => $verified,
        'log_id' => $log_id,
        'message' => $verified ? 'Face verification successful' : 'Face verification failed'
    );

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
    error_log('[FACE_VERIFY] ' . $e->getMessage());
    http_response_code(500);
    echo json_encode(array(
        'success' => false,
        'verified' => false,
        'error' => true,
        'code' => 'server_error',
        'message' => 'Verification could not be completed. Please try again.'
    ));
}
