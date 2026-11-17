<?php
/**
 * Upload Clocking Evidence Images (Signatures + Face Photos)
 * 
 * Handles upload of signature and face photo images for clock-in/out evidence.
 * Images are stored in mobile/clocking_evidence/ directory.
 * 
 * Security Features:
 * - Bearer token authentication required
 * - Rate limiting
 * - File validation (PNG for signatures, JPEG for photos)
 * - File size limits
 * 
 * @security CRITICAL - Authentication required
 */

// Enable error logging
error_log("[UPLOAD_EVIDENCE] === New upload request received ===");
error_log("[UPLOAD_EVIDENCE] Request method: " . $_SERVER['REQUEST_METHOD']);
error_log("[UPLOAD_EVIDENCE] Content-Type: " . ($_SERVER['CONTENT_TYPE'] ?? 'not set'));
error_log("[UPLOAD_EVIDENCE] Authorization header: " . (isset($_SERVER['HTTP_AUTHORIZATION']) ? 'present' : 'missing'));
error_log("[UPLOAD_EVIDENCE] FILES array: " . json_encode(array_keys($_FILES)));
error_log("[UPLOAD_EVIDENCE] POST fields: " . json_encode(array_keys($_POST)));

require_once 'require_auth.php';
require_once 'connection.php';

header('Content-Type: application/json');

// SECURITY: Require authentication
try {
    $user = requireAuth($conn);
    error_log("[UPLOAD_EVIDENCE] ✅ Authentication successful - User ID: " . $user['user_id']);
} catch (Exception $e) {
    error_log("[UPLOAD_EVIDENCE] ❌ Authentication failed: " . $e->getMessage());
    throw $e;
}

// SECURITY: Apply rate limiting
try {
    applyRateLimit($conn, 'upload_clocking_evidence');
    error_log("[UPLOAD_EVIDENCE] ✅ Rate limit check passed");
} catch (Exception $e) {
    error_log("[UPLOAD_EVIDENCE] ❌ Rate limit exceeded: " . $e->getMessage());
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
    
    // Validate PNG signature
    $validation = validate_file_upload($signature, [
        'allowed_extensions' => ['png'],
        'allowed_mime_types' => ['image/png'],
        'max_size' => 2 * 1024 * 1024,  // 2MB
        'allow_svg' => false
    ]);
    
    if (!$validation['valid']) {
        sendError('Invalid signature file: ' . $validation['error'], 400, 'INVALID_SIGNATURE');
    }
    
    // Use the filename provided by the app (or generate one)
    $signature_filename = $_POST['signature_filename'] ?? null;
    if (!$signature_filename) {
        // Generate filename if not provided
        $timestamp = date('Ymd_His');
        $signature_filename = "signature_{$learner_id}_{$timestamp}_{$suffix}.png";
    }
    
    $signature_path = $signatures_dir . $signature_filename;
    
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
    
    // Validate JPEG photo
    $validation = validate_file_upload($photo, [
        'allowed_extensions' => ['jpg', 'jpeg'],
        'allowed_mime_types' => ['image/jpeg'],
        'max_size' => 5 * 1024 * 1024,  // 5MB
        'allow_svg' => false
    ]);
    
    if (!$validation['valid']) {
        sendError('Invalid face photo file: ' . $validation['error'], 400, 'INVALID_PHOTO');
    }
    
    // Use the filename provided by the app (or generate one)
    $photo_filename = $_POST['photo_filename'] ?? null;
    if (!$photo_filename) {
        // Generate filename if not provided
        $timestamp = date('Ymd_His');
        $photo_filename = "face_{$learner_id}_{$timestamp}_{$suffix}.jpg";
    }
    
    $photo_path = $photos_dir . $photo_filename;
    
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

$conn->close();
?>