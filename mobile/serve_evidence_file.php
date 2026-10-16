<?php
/**
 * Secure Evidence File Server
 * 
 * Serves clocking evidence files with authentication and authorization
 * Replaces direct file access which was blocked by .htaccess
 */

require_once 'connection.php';
require_once 'require_auth.php';

// SECURITY: Always require authentication
try {
    $user = requireAuth($conn);
} catch (Exception $e) {
    http_response_code(401);
    echo json_encode(['error' => 'Authentication required']);
    exit;
}

// Get and validate parameters
$filename = $_GET['filename'] ?? '';
$type = $_GET['type'] ?? ''; // 'signature' or 'face_photo'

if (empty($filename) || empty($type)) {
    http_response_code(400);
    echo json_encode(['error' => 'Missing filename or type parameter']);
    exit;
}

// SECURITY: Validate filename format (server-generated only)
if (!preg_match('/^(signature|face)_\d+_\d{8}_\d{6}_[a-f0-9]{8}_(in|out)\.(png|jpg)$/', $filename)) {
    http_response_code(400);
    echo json_encode(['error' => 'Invalid filename format']);
    exit;
}

// SECURITY: Validate type parameter
if (!in_array($type, ['signature', 'face_photo'], true)) {
    http_response_code(400);  
    echo json_encode(['error' => 'Invalid file type']);
    exit;
}

// Construct secure file path
$baseDir = __DIR__ . '/clocking_evidence/';
$subDir = ($type === 'signature') ? 'signatures/' : 'face_photos/';
$filepath = $baseDir . $subDir . $filename;

// SECURITY: Prevent directory traversal - ensure file is within evidence directory
$realBasePath = realpath($baseDir);
$realFilePath = realpath($filepath);

if (!$realFilePath || !str_starts_with($realFilePath, $realBasePath)) {
    http_response_code(403);
    echo json_encode(['error' => 'Access denied']);
    exit;
}

// Check if file exists
if (!file_exists($filepath)) {
    http_response_code(404);
    echo json_encode(['error' => 'File not found']);
    exit;
}

// SECURITY: Additional authorization - verify user has access to this evidence
// Extract learner ID from filename for authorization check
if (preg_match('/^(signature|face)_(\d+)_/', $filename, $matches)) {
    $learnerID = $matches[2];
    
    // Check if user has access to this learner's data based on your actual table structure
    $stmt = $conn->prepare("
        SELECT COUNT(*) as count 
        FROM learnerdetails ld 
        WHERE ld.LearnerID = ? 
        AND (
            ld.FacilitatorID = ? 
            OR ? IN (SELECT user_id FROM users WHERE role IN ('admin', 'manager'))
        )
    ");
    
    if ($stmt) {
        $stmt->bind_param("iii", $learnerID, $user['user_id'], $user['user_id']);
        $stmt->execute();
        $result = $stmt->get_result();
        $row = $result->fetch_assoc();
        
        if ($row['count'] == 0) {
            http_response_code(403);
            echo json_encode(['error' => 'Access denied to this evidence file']);
            exit;
        }
        $stmt->close();
    }
}

// Determine MIME type
$mimeType = ($type === 'signature') ? 'image/png' : 'image/jpeg';

// SECURITY: Set secure headers
header('Content-Type: ' . $mimeType);
header('Content-Length: ' . filesize($filepath));
header('Content-Disposition: inline; filename="' . basename($filename) . '"');
header('X-Content-Type-Options: nosniff');
header('Cache-Control: private, max-age=3600'); // Cache for 1 hour
header('X-Frame-Options: DENY');

// Stream file securely
$handle = fopen($filepath, 'rb');
if ($handle) {
    while (!feof($handle)) {
        echo fread($handle, 8192);
        flush();
    }
    fclose($handle);
} else {
    http_response_code(500);
    echo json_encode(['error' => 'Failed to read file']);
}
?>