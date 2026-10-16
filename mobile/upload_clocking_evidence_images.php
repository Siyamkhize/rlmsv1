<?php
/**
 * Upload Clocking Evidence Images (Signatures + Face Photos)
 * 
 * Handles upload of signature and face photo images for clock-in/out evidence.
 * Images are stored in mobile/clocking_evidence/ directory.
 * 
 * Security Features:
 * - Bearer token authentication required
 * - Global and endpoint-specific rate limiting
 * - File validation (PNG for signatures, JPEG for photos)
 * - File size limits
 * - Request monitoring and logging
 * 
 * @security CRITICAL - Authentication required
 */

require_once 'connection.php';
require_once 'require_auth.php';
require_once 'security_middleware.php';

header('Content-Type: application/json');

// Initialize request security and logging  
$log_id = 0;
if (function_exists('initializeRequestSecurity') && isset($conn)) {
    $log_id = initializeRequestSecurity($conn, 'upload_clocking_evidence_images');
}

// Enable detailed logging for troubleshooting
error_log("[UPLOAD_EVIDENCE] === New upload request received ===");
error_log("[UPLOAD_EVIDENCE] Request method: " . $_SERVER['REQUEST_METHOD']);
error_log("[UPLOAD_EVIDENCE] Content-Type: " . ($_SERVER['CONTENT_TYPE'] ?? 'not set'));
error_log("[UPLOAD_EVIDENCE] Authorization header: " . (isset($_SERVER['HTTP_AUTHORIZATION']) ? 'present' : 'missing'));
error_log("[UPLOAD_EVIDENCE] FILES array: " . json_encode(array_keys($_FILES)));
error_log("[UPLOAD_EVIDENCE] POST fields: " . json_encode(array_keys($_POST)));

// SECURITY: Require authentication
try {
    if (function_exists('requireAuth') && isset($conn)) {
        $user = requireAuth($conn);
        error_log("[UPLOAD_EVIDENCE] ✅ Authentication successful - User ID: " . $user['user_id']);
    }
} catch (Exception $e) {
    error_log("[UPLOAD_EVIDENCE] ❌ Authentication failed: " . $e->getMessage());
    
    // Log completion with error
    if (function_exists('log_request_completion') && isset($conn)) {
        log_request_completion($conn, $log_id, 401, 'error', 'Authentication failed: ' . $e->getMessage());
    }
    
    http_response_code(401);
    echo json_encode(['error' => 'Authentication required', 'message' => $e->getMessage()]);
    exit;
}

// SECURITY: Apply endpoint-specific rate limiting
try {
    if (function_exists('applyRateLimit') && isset($conn)) {
        applyRateLimit($conn, 'upload_clocking_evidence');
    }
    error_log("[UPLOAD_EVIDENCE] ✅ Rate limit check passed");
} catch (Exception $e) {
    error_log("[UPLOAD_EVIDENCE] ❌ Rate limit exceeded: " . $e->getMessage());
    
    // Log completion with error
    if (function_exists('log_request_completion') && isset($conn)) {
        log_request_completion($conn, $log_id, 429, 'error', 'Rate limit exceeded: ' . $e->getMessage());
    }
    
    throw $e;
}

// Initialize response
$response = [
    'success' => true,
    'uploaded' => []
];

error_log("[UPLOAD_EVIDENCE] Initializing upload process...");

// Create directories with secure permissions (inside mobile/)
$signatures_dir = 'clocking_evidence/signatures/';
$photos_dir = 'clocking_evidence/face_photos/';

if (!is_dir($signatures_dir)) {
    mkdir($signatures_dir, 0755, true);
    error_log("[UPLOAD_EVIDENCE] Created signatures directory");
}
if (!is_dir($photos_dir)) {
    mkdir($photos_dir, 0755, true);
    error_log("[UPLOAD_EVIDENCE] Created face photos directory");
}

error_log("[UPLOAD_EVIDENCE] Signatures dir exists: " . (is_dir($signatures_dir) ? 'YES' : 'NO'));
error_log("[UPLOAD_EVIDENCE] Photos dir exists: " . (is_dir($photos_dir) ? 'YES' : 'NO'));
error_log("[UPLOAD_EVIDENCE] Signatures dir writable: " . (is_writable($signatures_dir) ? 'YES' : 'NO'));
error_log("[UPLOAD_EVIDENCE] Photos dir writable: " . (is_writable($photos_dir) ? 'YES' : 'NO'));

// Process signature upload (if provided)
if (isset($_FILES['signature']) && $_FILES['signature']['error'] === UPLOAD_ERR_OK) {
    error_log("[UPLOAD_EVIDENCE] Processing signature upload...");
    $signature = $_FILES['signature'];
    $learner_id = $_POST['learner_id'] ?? '';
    $suffix = $_POST['signature_suffix'] ?? 'in';
    
    error_log("[UPLOAD_EVIDENCE] Signature file name: " . $signature['name']);
    error_log("[UPLOAD_EVIDENCE] Signature file size: " . $signature['size']);
    error_log("[UPLOAD_EVIDENCE] Signature file type: " . $signature['type']);
    error_log("[UPLOAD_EVIDENCE] Learner ID: $learner_id");
    error_log("[UPLOAD_EVIDENCE] Suffix: $suffix");
    
    // SECURITY: Enforce memory and file size limits before processing
    ini_set('memory_limit', '256M'); // Limit memory usage for image processing
    
    // Validate PNG signature with size limits and memory estimation
    $validation = validate_file_upload($signature, [
        'allowed_extensions' => ['png'],
        'allowed_mime_types' => ['image/png'],
        'max_size' => 2 * 1024 * 1024,  // 2MB max
        'max_width' => 2048,   // Prevent memory exhaustion from huge images
        'max_height' => 2048,  // Prevent memory exhaustion from huge images
        'allow_svg' => false
    ]);
    
    if (!$validation['valid']) {
        sendError('Invalid signature file: ' . $validation['error'], 400, 'INVALID_SIGNATURE');
    }
    
    // SECURITY: Additional image resource validation before processing
    $image_info = getimagesize($signature['tmp_name']);
    if ($image_info === false) {
        sendError('Invalid image file - cannot read image data', 400, 'INVALID_IMAGE_DATA');
    }
    
    list($width, $height) = $image_info;
    
    // Estimate memory usage (width × height × 4 bytes per pixel for RGBA)
    $estimated_memory = $width * $height * 4;
    $available_memory = _get_available_memory();
    
    if ($estimated_memory > $available_memory * 0.8) { // Use max 80% available
        sendError('Image too large for available memory. Reduce image size.', 413, 'IMAGE_TOO_LARGE');
    }
    
    // SECURITY: Always use server-generated filenames - NEVER trust client input
    $timestamp = date('Ymd_His');
    $secure_random = bin2hex(random_bytes(4)); // 8 character random string
    $signature_filename = "signature_{$learner_id}_{$timestamp}_{$secure_random}_{$suffix}.png";
    
    // Log rejected client filename for security monitoring
    if (isset($_POST['signature_filename'])) {
        error_log("[UPLOAD_EVIDENCE] SECURITY: Ignored client-supplied filename: " . $_POST['signature_filename']);
    }
    
    $signature_path = $signatures_dir . $signature_filename;
    
    // SECURITY: Validate that the resolved path stays within the intended upload directory
    $realSignaturesDir = realpath($signatures_dir);
    $realSignaturePath = realpath(dirname($signature_path)) . '/' . basename($signature_path);
    
    if ($realSignaturesDir === false || strpos($realSignaturePath, $realSignaturesDir) !== 0) {
        sendError('Invalid signature path - directory traversal detected', 400, 'INVALID_PATH');
    }
    
    error_log("[UPLOAD_EVIDENCE] Attempting to move uploaded file to: $signature_path");
    
    if (move_uploaded_file($signature['tmp_name'], $signature_path)) {
        chmod($signature_path, 0644);
        error_log("[UPLOAD_EVIDENCE] ✅ Signature file saved successfully: $signature_path");
        $response['uploaded'][] = [
            'type' => 'signature',
            'filename' => $signature_filename,
            'path' => $signature_path
        ];
    } else {
        error_log("[UPLOAD_EVIDENCE] ❌ Failed to move signature file");
        error_log("[UPLOAD_EVIDENCE] Source: " . $signature['tmp_name']);
        error_log("[UPLOAD_EVIDENCE] Destination: " . $signature_path);
        sendError('Failed to save signature file', 500, 'SIGNATURE_SAVE_ERROR');
    }
} else {
    if (isset($_FILES['signature'])) {
        error_log("[UPLOAD_EVIDENCE] Signature upload error code: " . $_FILES['signature']['error']);
    } else {
        error_log("[UPLOAD_EVIDENCE] No signature file in request");
    }
}

// Process face photo upload (if provided)
if (isset($_FILES['face_photo']) && $_FILES['face_photo']['error'] === UPLOAD_ERR_OK) {
    $photo = $_FILES['face_photo'];
    $learner_id = $_POST['learner_id'] ?? '';
    $suffix = $_POST['photo_suffix'] ?? 'in';
    
    // Validate JPEG photo with size limits  
    $validation = validate_file_upload($photo, [
        'allowed_extensions' => ['jpg', 'jpeg'],
        'allowed_mime_types' => ['image/jpeg'],
        'max_size' => 5 * 1024 * 1024,  // 5MB max
        'max_width' => 3840,   // 4K width max to prevent memory issues
        'max_height' => 2160,  // 4K height max to prevent memory issues  
        'allow_svg' => false
    ]);
    
    if (!$validation['valid']) {
        sendError('Invalid face photo file: ' . $validation['error'], 400, 'INVALID_PHOTO');
    }
    
    // SECURITY: Additional image resource validation before processing
    $image_info = getimagesize($photo['tmp_name']);
    if ($image_info === false) {
        sendError('Invalid image file - cannot read image data', 400, 'INVALID_IMAGE_DATA');
    }
    
    list($width, $height) = $image_info;
    
    // Estimate memory usage (width × height × 4 bytes per pixel for RGBA)
    $estimated_memory = $width * $height * 4;
    $available_memory = _get_available_memory();
    
    if ($estimated_memory > $available_memory * 0.8) { // Use max 80% available
        sendError('Image too large for available memory. Reduce image size.', 413, 'IMAGE_TOO_LARGE');
    }
    
    // SECURITY: Always use server-generated filenames - NEVER trust client input
    $timestamp = date('Ymd_His');
    $secure_random = bin2hex(random_bytes(4)); // 8 character random string
    $photo_filename = "face_{$learner_id}_{$timestamp}_{$secure_random}_{$suffix}.jpg";
    
    // Log rejected client filename for security monitoring
    if (isset($_POST['photo_filename'])) {
        error_log("[UPLOAD_EVIDENCE] SECURITY: Ignored client-supplied filename: " . $_POST['photo_filename']);
    }
    
    $photo_path = $photos_dir . $photo_filename;
    
    // SECURITY: Validate that the resolved path stays within the intended upload directory
    $realPhotosDir = realpath($photos_dir);
    $realPhotoPath = realpath(dirname($photo_path)) . '/' . basename($photo_path);
    
    if ($realPhotosDir === false || strpos($realPhotoPath, $realPhotosDir) !== 0) {
        sendError('Invalid photo path - directory traversal detected', 400, 'INVALID_PATH');
    }
    
    if (move_uploaded_file($photo['tmp_name'], $photo_path)) {
        chmod($photo_path, 0644);
        $response['uploaded'][] = [
            'type' => 'face_photo',
            'filename' => $photo_filename,
            'path' => $photo_path
        ];
    } else {
        sendError('Failed to save face photo file', 500, 'PHOTO_SAVE_ERROR');
    }
}

// Check if any files were uploaded
if (empty($response['uploaded'])) {
    sendError('No valid files uploaded', 400, 'NO_FILES_UPLOADED');
}

// Log security event
log_security_event('clocking_evidence_uploaded', 'Clocking evidence images uploaded', [
    'user_id' => $user['user_id'],
    'learner_id' => $_POST['learner_id'] ?? 'unknown',
    'files' => count($response['uploaded'])
]);

sendSuccess($response, 'Files uploaded successfully');

// Log successful completion
if (function_exists('log_request_completion') && isset($conn)) {
    log_request_completion($conn, $log_id, 200, 'success', 'Files uploaded successfully');
}

$conn->close();

/**
 * Get available memory for image processing
 * 
 * @return int Available memory in bytes
 */
function _get_available_memory() {
    $memory_limit = ini_get('memory_limit');
    $current_usage = memory_get_usage(true);
    
    // Convert memory_limit to bytes
    $limit_bytes = _parse_size($memory_limit);
    return $limit_bytes - $current_usage;
}

/**
 * Parse size string (e.g., '256M', '1G') to bytes
 * 
 * @param string $size Size string
 * @return int Size in bytes
 */
function _parse_size($size) {
    $size = trim($size);
    $last = strtolower($size[strlen($size)-1]);
    $number = (int) $size;
    
    switch($last) {
        case 'g':
            $number *= 1024;
        case 'm':
            $number *= 1024;
        case 'k':
            $number *= 1024;
    }
    
    return $number;
}
?>