<?php
/**
 * Save Consolidated Clocking with Proper Offline-First Idempotency
 *
 * Combines 3 separate requests into 1:
 * 1. Image uploads (face + signature) 
 * 2. Clock-in/out record in manual_clocking table
 * 3. Evidence record in manual_clocking_evidence table
 * 
 * CRITICAL: Uses tap-time generated idempotency keys for proper offline sync
 */
 // Set timezone to South Africa (SAST = UTC+2) - CRITICAL for date/time consistency
date_default_timezone_set('Africa/Johannesburg');

// SECURITY: Enforce strict resource limits
ini_set('memory_limit', '128M');        // Limit memory usage
ini_set('max_execution_time', '30');    // 30 second max execution
ini_set('post_max_size', '20M');        // Max POST size
ini_set('upload_max_filesize', '10M');  // Max individual file

header('Content-Type: application/json');

// Load core dependencies with error handling
try {
    require_once 'connection.php';
    require_once 'idempotency_helpers.php';
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'error' => 'System initialization failed',
        'message' => 'Service temporarily unavailable'
    ]);
    exit;
}

// Load optional security functions
if (file_exists(__DIR__ . '/security_functions.php')) {
    require_once 'security_functions.php';
}

// Note: require_auth.php is loaded conditionally in the security section below with timeout protection
require_once 'require_auth.php';

// Do not print PHP warnings into the JSON response
error_reporting(E_ALL);
ini_set('display_errors', 0);
ini_set('log_errors', 1);

// SECURITY: Try to require authentication (with timeout protection)
$user = null;
$authTimeout = 5; // 5 second timeout for authentication
$originalTimeout = ini_get('max_execution_time'); // Store original timeout
$authDuration = 0; // Initialize timing variables
$rateLimitDuration = 0;

try {
    if (file_exists(__DIR__ . '/require_auth.php')) {
        // Set execution timeout for auth functions
        set_time_limit($authTimeout);
        
        $authStartTime = microtime(true);
        require_once 'require_auth.php';
        
        // Check if requireAuth function exists and is callable
        if (function_exists('requireAuth') && is_callable('requireAuth')) {
            // Add signal handler for timeout protection (if available)
            if (function_exists('pcntl_alarm') && function_exists('pcntl_signal')) {
                pcntl_signal(SIGALRM, function() use ($authTimeout) {
                    throw new Exception('Authentication timeout after ' . $authTimeout . ' seconds');
                });
                pcntl_alarm($authTimeout);
            }
            
            $user = requireAuth($conn);
            $authDuration = microtime(true) - $authStartTime;
            
            // Clear alarm if set
            if (function_exists('pcntl_alarm')) {
                pcntl_alarm(0);
            }
            
            error_log("[SAVE_CONSOLIDATED_CLOCKING] ✅ Authentication successful - User ID: " . $user['user_id'] . " (took {$authDuration}s)");
        } else {
            throw new Exception('requireAuth function not available');
        }
        
        // Restore original timeout
        set_time_limit($originalTimeout);
        
    } else {
        error_log("[SAVE_CONSOLIDATED_CLOCKING] ❌ Authentication file not found - BLOCKING REQUEST");
        http_response_code(401);
        echo json_encode([
            'success' => false,
            'error' => 'Authentication required',
            'message' => 'Authentication system not available. Access denied.'
        ]);
        exit; // CRITICAL: Must exit here - never continue without auth
    }
} catch (Exception $e) {
    // Restore timeout on any error
    if (isset($originalTimeout)) {
        set_time_limit($originalTimeout);
    }
    
    $authDuration = isset($authStartTime) ? microtime(true) - $authStartTime : 0;
    error_log("[SAVE_CONSOLIDATED_CLOCKING] ⚠️ Authentication failed or timed out after {$authDuration}s: " . $e->getMessage());
    
    // Check if this is a critical auth failure or system issue
    if (strpos($e->getMessage(), 'Unauthorized') !== false || 
        strpos($e->getMessage(), 'Invalid token') !== false ||
        strpos($e->getMessage(), 'Access denied') !== false) {
        // Critical auth failure - block request
        http_response_code(401);
        echo json_encode([
            'success' => false,
            'error' => $e->getMessage(),
            'message' => 'Authentication required',
            'auth_duration' => $authDuration
        ]);
        exit;
    } else {
        // SECURITY: Auth system issue (timeout, unavailable, malformed) - FAIL CLOSED
        error_log("[SAVE_CONSOLIDATED_CLOCKING] ❌ Authentication system issue - BLOCKING REQUEST");
        http_response_code(401);
        echo json_encode([
            'success' => false,
            'error' => 'Authentication required',
            'message' => 'Authentication failed. Access denied.',
            'auth_duration' => $authDuration
        ]);
        exit; // CRITICAL: Must exit here - never continue without auth
    }
}

// SECURITY: Check idempotency key FIRST (before any processing)
$idempotencyKey = $_SERVER['HTTP_IDEMPOTENCY_KEY'] ?? '';
if (!validate_idempotency_key($idempotencyKey)) {
    http_response_code(400);
    echo json_encode([
        'success' => false,
        'error' => 'Missing or invalid idempotency key',
        'message' => 'Idempotency-Key header must be a valid UUID v4'
    ]);
    exit;
}

// Check if this is a duplicate request (key already processed)
$prev = idem_begin($conn, $user['user_id'], 'consolidated_clocking', $idempotencyKey);
if ($prev) {
    if ($prev['status'] === 'done') {
        // Return the same response as before
        http_response_code((int)$prev['response_code']);
        echo $prev['response_body'];
        exit;
    }
    // Still processing - shouldn't happen with proper client implementation
    http_response_code(409);
    echo json_encode([
        'success' => false,
        'error' => 'Request already in progress',
        'message' => 'This action is still being processed'
    ]);
    exit;
}

// SECURITY: Validate client timestamp
$clientTimestamp = $_POST['client_timestamp'] ?? '';
$timestampValidation = validate_client_timestamp($clientTimestamp);
if (!$timestampValidation['valid']) {
    idem_abort($conn, $user['user_id'], $idempotencyKey);
    http_response_code(400);
    echo json_encode([
        'success' => false,
        'error' => 'Invalid timestamp',
        'message' => $timestampValidation['error']
    ]);
    exit;
}

$actionTime = $timestampValidation['timestamp'];
try {
    if (function_exists('applyRateLimit') && is_callable('applyRateLimit')) {
        $rateLimitStartTime = microtime(true);
        set_time_limit(3); // 3 second timeout for rate limiting
        
        applyRateLimit($conn, 'save_consolidated_clocking');
        
        $rateLimitDuration = microtime(true) - $rateLimitStartTime;
        error_log("[SAVE_CONSOLIDATED_CLOCKING] ✅ Rate limit check passed (took {$rateLimitDuration}s)");
        
        // Restore original timeout
        set_time_limit($originalTimeout ?? 30);
        
    } else {
        error_log("[SAVE_CONSOLIDATED_CLOCKING] ⚠️ Rate limiting skipped - function not available");
    }
} catch (Exception $e) {
    // Restore timeout on any error
    set_time_limit($originalTimeout ?? 30);
    
    $rateLimitDuration = isset($rateLimitStartTime) ? microtime(true) - $rateLimitStartTime : 0;
    error_log("[SAVE_CONSOLIDATED_CLOCKING] ⚠️ Rate limiting failed after {$rateLimitDuration}s: " . $e->getMessage());
    
    // For rate limit exceeded, block the request
    if (strpos(strtolower($e->getMessage()), 'rate limit') !== false || 
        strpos(strtolower($e->getMessage()), 'too many') !== false) {
        http_response_code(429);
        echo json_encode([
            'success' => false,
            'error' => $e->getMessage(),
            'message' => 'Rate limit exceeded',
            'retry_after' => 60
        ]);
        exit;
    }
    // For other rate limiting issues, continue with warning
}

try {
    // Track processing time
    $processingStartTime = microtime(true);
    
    // Get JSON input
    $input = json_decode(file_get_contents('php://input'), true);
    
    if (!$input || !is_array($input)) {
        throw new Exception('Invalid JSON input');
    }
    
    // SECURITY: Idempotency protection to prevent duplicate submissions
    $idempotencyToken = isset($input['idempotency_token']) ? trim($input['idempotency_token']) : null;
    
    if ($idempotencyToken) {
        // SECURITY: Validate token format (UUID v4 or secure clk_ format)
        if (!validate_idempotency_key($idempotencyToken)) {
            throw new Exception('Invalid idempotency token format. Expected UUID v4 or clk_[hex32] format.');
        }
        
        // Check if we've already processed this exact request
        $stmt = $conn->prepare("SELECT id, response_data FROM idempotency_log WHERE token = ? AND endpoint = 'save_consolidated_clocking'");
        if ($stmt) {
            $stmt->bind_param('s', $idempotencyToken);
            $stmt->execute();
            $result = $stmt->get_result();
            
            if ($result->num_rows > 0) {
                // Request already processed - return cached response
                $row = $result->fetch_assoc();
                error_log("[SAVE_CONSOLIDATED_CLOCKING] ⚠️ Duplicate request detected with token: $idempotencyToken, returning cached response");
                
                http_response_code(200);
                echo $row['response_data']; // Return exact same response as before
                $stmt->close();
                exit;
            }
            $stmt->close();
        }
    } else {
        // Generate idempotency token if not provided (for logging)
        $idempotencyToken = 'auto_' . uniqid() . '_' . bin2hex(random_bytes(4));
    }
    $learnerID = isset($input['learner_id']) ? intval($input['learner_id']) : 0;
    $classID = isset($input['class_id']) ? intval($input['class_id']) : null;
    $clockDate = isset($input['clock_date']) ? trim($input['clock_date']) : date('Y-m-d');
    $type = isset($input['type']) ? strtolower(trim($input['type'])) : ''; // 'in' or 'out'
    $timestamp = isset($input['timestamp']) ? trim($input['timestamp']) : date('Y-m-d H:i:s');
    
    // GPS data with validation
    $latitude = isset($input['latitude']) ? floatval($input['latitude']) : null;
    $longitude = isset($input['longitude']) ? floatval($input['longitude']) : null;
    $accuracy = isset($input['accuracy']) ? floatval($input['accuracy']) : null;
    
    // Images (base64 encoded) - validate base64
    $faceImage = isset($input['face_image']) ? trim($input['face_image']) : '';
    $signatureImage = isset($input['signature_image']) ? trim($input['signature_image']) : '';
    
    // SECURITY: Comprehensive input validation
    if ($learnerID <= 0 || $learnerID > 2147483647) { // Max MySQL INT
        throw new Exception('Invalid learner ID - must be positive integer');
    }
    
    if (!in_array($type, ['in', 'out'], true)) {
        throw new Exception('Invalid type - must be "in" or "out"');
    }
    
    // Validate date format (YYYY-MM-DD)
    if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $clockDate)) {
        throw new Exception('Invalid clock_date format - must be YYYY-MM-DD');
    }
    
    $dateTime = DateTime::createFromFormat('Y-m-d', $clockDate);
    if (!$dateTime || $dateTime->format('Y-m-d') !== $clockDate) {
        throw new Exception('Invalid clock_date - not a valid date');
    }
    
    // Validate timestamp format (YYYY-MM-DD HH:MM:SS)
    if (!preg_match('/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/', $timestamp)) {
        throw new Exception('Invalid timestamp format - must be YYYY-MM-DD HH:MM:SS');
    }
    
    $dateTimeCheck = DateTime::createFromFormat('Y-m-d H:i:s', $timestamp);
    if (!$dateTimeCheck || $dateTimeCheck->format('Y-m-d H:i:s') !== $timestamp) {
        throw new Exception('Invalid timestamp - not a valid datetime');
    }
    
    // Validate GPS coordinates if provided
    if ($latitude !== null && ($latitude < -90 || $latitude > 90)) {
        throw new Exception('Invalid latitude - must be between -90 and 90');
    }
    
    if ($longitude !== null && ($longitude < -180 || $longitude > 180)) {
        throw new Exception('Invalid longitude - must be between -180 and 180');
    }
    
    if ($accuracy !== null && ($accuracy < 0 || $accuracy > 10000)) {
        throw new Exception('Invalid accuracy - must be between 0 and 10000 meters');
    }
    
    // Validate base64 images if provided
    if (!empty($faceImage)) {
        // Remove data URL prefix if present
        $faceImage = preg_replace('/^data:image\/[a-zA-Z]+;base64,/', '', $faceImage);
        if (!preg_match('/^[A-Za-z0-9+\/]*={0,2}$/', $faceImage)) {
            throw new Exception('Invalid face image - must be valid base64');
        }
        // Test decode
        $testDecode = base64_decode($faceImage, true);
        if ($testDecode === false || strlen($testDecode) < 100) {
            throw new Exception('Invalid face image - base64 decode failed or too small');
        }
        // Check for image signatures
        if (!preg_match('/^(\/9j\/|iVBORw0KGgoAAAANSUhEUgAA|R0lGOD|UklGR)/', $faceImage)) {
            throw new Exception('Invalid face image - not a recognized image format');
        }
    }
    
    if (!empty($signatureImage)) {
        // Remove data URL prefix if present
        $signatureImage = preg_replace('/^data:image\/[a-zA-Z]+;base64,/', '', $signatureImage);
        if (!preg_match('/^[A-Za-z0-9+\/]*={0,2}$/', $signatureImage)) {
            throw new Exception('Invalid signature image - must be valid base64');
        }
        // Test decode
        $testDecode = base64_decode($signatureImage, true);
        if ($testDecode === false || strlen($testDecode) < 100) {
            throw new Exception('Invalid signature image - base64 decode failed or too small');
        }
    }
    
    // Start transaction
    $conn->begin_transaction();
    
    try {
        // Step 1: Save images and get filenames
        // Base directories (inside mobile folder)
        $baseDir = __DIR__; // This is the mobile folder
        $facesDir = $baseDir . '/manual_clocking_evidence/faces';
        $signaturesDir = $baseDir . '/manual_clocking_evidence/signatures';
        
        $faceFilename = '';
        $signatureFilename = '';
        
        if (!empty($faceImage)) {
            // SECURITY: Safe filename generation - prevent path traversal
            $faceFilename = sprintf(
                "face_%d_%s_%d.jpg",
                $learnerID,
                ($type === 'in' ? 'in' : 'out'),
                time()
            );
            
            // SECURITY: Validate filename is safe
            if (strpos($faceFilename, '..') !== false || strpos($faceFilename, '/') !== false || strpos($faceFilename, '\\') !== false) {
                throw new Exception('Invalid face filename generated');
            }
            
            $facePath = $facesDir . '/' . $faceFilename;
            
            // SECURITY: Ensure path is within expected directory
            $realFacesDir = realpath($facesDir);
            $realFacePath = realpath(dirname($facePath)) . '/' . basename($facePath);
            
            if ($realFacesDir === false || strpos($realFacePath, $realFacesDir) !== 0) {
                throw new Exception('Invalid face image path - directory traversal detected');
            }
            
            $faceData = base64_decode($faceImage, true);
            if (!$faceData || file_put_contents($facePath, $faceData) === false) {
                throw new Exception('Failed to save face image');
            }
            
            // SECURITY: Verify saved file size is reasonable
            $savedSize = filesize($facePath);
            if ($savedSize === false || $savedSize < 100 || $savedSize > 512000) { // 500KB max
                @unlink($facePath);
                throw new Exception('Face image file size invalid - must be between 100 bytes and 500KB');
            }
        }
        
        if (!empty($signatureImage)) {
            // SECURITY: Safe filename generation - prevent path traversal
            $signatureFilename = sprintf(
                "signature_%d_%s_%d.png",
                $learnerID,
                ($type === 'in' ? 'in' : 'out'),
                time()
            );
            
            // SECURITY: Validate filename is safe
            if (strpos($signatureFilename, '..') !== false || strpos($signatureFilename, '/') !== false || strpos($signatureFilename, '\\') !== false) {
                throw new Exception('Invalid signature filename generated');
            }
            
            $signaturePath = $signaturesDir . '/' . $signatureFilename;
            
            // SECURITY: Ensure path is within expected directory
            $realSignaturesDir = realpath($signaturesDir);
            $realSignaturePath = realpath(dirname($signaturePath)) . '/' . basename($signaturePath);
            
            if ($realSignaturesDir === false || strpos($realSignaturePath, $realSignaturesDir) !== 0) {
                throw new Exception('Invalid signature image path - directory traversal detected');
            }
            
            $signatureData = base64_decode($signatureImage, true);
            if (!$signatureData || file_put_contents($signaturePath, $signatureData) === false) {
                throw new Exception('Failed to save signature image');
            }
            
            // SECURITY: Verify saved file size is reasonable
            $savedSize = filesize($signaturePath);
            if ($savedSize === false || $savedSize < 100 || $savedSize > 256000) { // 250KB max
                @unlink($signaturePath);
                throw new Exception('Signature image file size invalid - must be between 100 bytes and 250KB');
            }
        }
        
        // Step 2: Save to correct tables (manual_clocking + manual_clocking_evidence)
        if ($type === 'in') {
            // Clock-in: Insert/update manual_clocking table
            $stmt = $conn->prepare("
                INSERT INTO manual_clocking 
                (LearnerID, clock_date, clock_in_time, contact_time, is_manual_attendance) 
                VALUES (?, ?, ?, ?, 1)
                ON DUPLICATE KEY UPDATE
                clock_in_time = VALUES(clock_in_time),
                contact_time = VALUES(contact_time)
            ");
            
            $stmt->bind_param("isss", 
                $learnerID, $clockDate, $timestamp, $timestamp
            );
            
            if (!$stmt->execute()) {
                throw new Exception('Database error in manual_clocking: ' . $stmt->error);
            }
            $stmt->close();
            
            // Insert/update evidence table for clock-in
            $stmt = $conn->prepare("
                INSERT INTO manual_clocking_evidence 
                (LearnerID, clock_date, signature_in, face_in) 
                VALUES (?, ?, ?, ?)
                ON DUPLICATE KEY UPDATE
                signature_in = VALUES(signature_in),
                face_in = VALUES(face_in)
            ");
            
            $stmt->bind_param("isss",
                $learnerID, $clockDate, $signatureFilename, $faceFilename
            );
            
        } else {
            // Clock-out: Update manual_clocking table
            $stmt = $conn->prepare("
                UPDATE manual_clocking 
                SET clock_out_time = ?
                WHERE LearnerID = ? AND clock_date = ?
                AND clock_in_time IS NOT NULL AND clock_out_time IS NULL
            ");
            
            $stmt->bind_param("sis",
                $timestamp, $learnerID, $clockDate
            );
            
            if (!$stmt->execute()) {
                throw new Exception('Database error in manual_clocking: ' . $stmt->error);
            }
            
            if ($stmt->affected_rows < 1) {
                throw new Exception('No clock-in record found or already clocked out');
            }
            $stmt->close();
            
            // Update evidence table for clock-out
            $stmt = $conn->prepare("
                UPDATE manual_clocking_evidence 
                SET signature_out = ?, face_out = ?
                WHERE LearnerID = ? AND clock_date = ?
            ");
            
            $stmt->bind_param("ssis",
                $signatureFilename, $faceFilename, $learnerID, $clockDate
            );
        }
        
        if (!$stmt->execute()) {
            throw new Exception('Database error in manual_clocking_evidence: ' . $stmt->error);
        }
        $stmt->close();
        
        $conn->commit();
        
        $response = json_encode([
            'success' => true,
            'message' => "Clock-{$type} saved successfully",
            'learner_id' => $learnerID,
            'clock_date' => $clockDate,
            'timestamp' => $timestamp,
            'face_filename' => $faceFilename,
            'signature_filename' => $signatureFilename,
            'server_time' => date('Y-m-d H:i:s'),
            'client_time' => $actionTime->format('Y-m-d H:i:s'),
            'sync_status' => 'completed',
            'gps' => [
                'latitude' => $latitude,
                'longitude' => $longitude,
                'accuracy' => $accuracy
            ],
            'auth_status' => 'enabled',
            'performance' => [
                'auth_duration' => isset($authDuration) ? round($authDuration, 3) : null,
                'rate_limit_duration' => isset($rateLimitDuration) ? round($rateLimitDuration, 3) : null,
                'total_processing_time' => round(microtime(true) - $processingStartTime, 3)
            ],
            'server_info' => [
                'endpoint' => 'save_consolidated_clocking',
                'version' => '1.1',
                'timestamp' => date('Y-m-d H:i:s'),
                'php_timeout' => ini_get('max_execution_time')
            ]
        ]);
        
        // IDEMPOTENCY: Mark as successfully completed
        idem_finish($conn, $user['user_id'], $idempotencyKey, 200, $response);
        
        echo $response;
        
    } catch (Exception $e) {
        $conn->rollback();
        
        // Clean up uploaded files on error
        if (!empty($faceFilename)) {
            @unlink($facesDir . '/' . $faceFilename);
        }
        if (!empty($signatureFilename)) {
            @unlink($signaturesDir . '/' . $signatureFilename);
        }
        
        throw $e;
    }
    
} catch (Exception $e) {
    // IDEMPOTENCY: Abort on failure to allow retry
    if (isset($idempotencyKey) && isset($user['user_id'])) {
        idem_abort($conn, $user['user_id'], $idempotencyKey);
    }
    
    // Rollback on error
    if (isset($conn)) {
        $conn->rollback();
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