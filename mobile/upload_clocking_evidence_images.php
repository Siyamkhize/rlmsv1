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

require_once 'require_auth.php';
require_once 'connection.php';

header('Content-Type: application/json');

// SECURITY: Require authentication
$user = requireAuth($conn);

// SECURITY: Apply rate limiting
applyRateLimit($conn, 'upload_clocking_evidence');

// Initialize response
$response = [
    'success' => true,
    'uploaded' => []
];

// Create directories with secure permissions (inside mobile/)
$signatures_dir = 'clocking_evidence/signatures/';
$photos_dir = 'clocking_evidence/face_photos/';

if (!is_dir($signatures_dir)) {
    mkdir($signatures_dir, 0755, true);
}
if (!is_dir($photos_dir)) {
    mkdir($photos_dir, 0755, true);
}

// Process signature upload (if provided)
if (isset($_FILES['signature']) && $_FILES['signature']['error'] === UPLOAD_ERR_OK) {
    $signature = $_FILES['signature'];
    $learner_id = $_POST['learner_id'] ?? '';
    $suffix = $_POST['signature_suffix'] ?? 'in';
    
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
    
    if (move_uploaded_file($signature['tmp_name'], $signature_path)) {
        chmod($signature_path, 0644);
        $response['uploaded'][] = [
            'type' => 'signature',
            'filename' => $signature_filename,
            'path' => $signature_path
        ];
    } else {
        sendError('Failed to save signature file', 500, 'SIGNATURE_SAVE_ERROR');
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