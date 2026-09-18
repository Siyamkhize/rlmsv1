<?php
/**
 * Sync Attendance Signature Images - Upload PNG files from phone to server
 * 
 * This endpoint handles uploading signature images for clock-in and clock-out
 * from the phone's local /signatures/ folder to the server.
 * 
 * Security Features:
 * - Bearer token authentication required
 * - File type validation (PNG only)
 * - File size validation (max 2MB per signature)
 * - Validates signature filename format
 * 
 * @security CRITICAL - Authentication required
 */

require_once 'require_auth.php';
require_once 'connection.php';

header('Content-Type: application/json');

// SECURITY: Require authentication
$user = requireAuth($conn);

// Check if signature file is provided
if (!isset($_FILES['signature_file']) || !isset($_POST['filename'])) {
    sendError('Missing signature_file or filename', 400, 'MISSING_REQUIRED_FIELDS');
}

$signature_file = $_FILES['signature_file'];
$filename = trim($_POST['filename']);

// SECURITY: Validate filename format: signature_{LEARNERID}_{YYYYMMDD_HHMMSS}_{in/out}.png
if (!preg_match('/^signature_\d+_\d{8}_\d{6}_(in|out)\.png$/', $filename)) {
    sendError('Invalid signature filename format', 400, 'INVALID_FILENAME');
}

// SECURITY: Validate file upload
$validation = validate_file_upload($signature_file, [
    'allowed_extensions' => ['png'],
    'allowed_mime_types' => ['image/png'],
    'max_size' => 2 * 1024 * 1024,  // 2MB
    'allow_svg' => false
]);

if (!$validation['valid']) {
    sendError($validation['error'], 400, 'INVALID_FILE_UPLOAD');
}

// Ensure upload directory exists (same folder as learner profile signatures)
$upload_dir = 'signatures/';
if (!is_dir($upload_dir)) {
    mkdir($upload_dir, 0755, true);
}

$file_path = $upload_dir . $filename;

// Check if file already exists (skip duplicate uploads)
if (file_exists($file_path)) {
    sendSuccess([
        'filename' => $filename,
        'status' => 'already_exists',
        'message' => 'Signature file already exists on server'
    ], 'Signature already uploaded');
}

// Move uploaded file
if (move_uploaded_file($signature_file['tmp_name'], $file_path)) {
    // Set secure file permissions
    chmod($file_path, 0644);
    
    // Log security event
    log_security_event('attendance_signature_synced', "Attendance signature uploaded", [
        'user_id' => $user['user_id'],
        'filename' => $filename
    ]);
    
    sendSuccess([
        'filename' => $filename,
        'status' => 'uploaded',
        'size' => filesize($file_path)
    ], 'Signature uploaded successfully');
} else {
    sendError('Failed to save signature file', 500, 'FILE_SAVE_ERROR');
}

$conn->close();
?>
