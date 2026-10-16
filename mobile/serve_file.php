<?php
ini_set('display_errors', 0);
ini_set('log_errors', 1);
error_reporting(0);

require_once __DIR__ . '/connection.php';
require_once __DIR__ . '/require_auth.php';

// SECURITY: Require authentication for all file access
$user = null;
try {
    $user = requireAuth($conn);
} catch (Exception $e) {
    header('Content-Type: application/json');
    http_response_code(401);
    echo json_encode(['error' => 'Authentication required']);
    exit;
}

$allowedOrigins = [
    'https://rlms.rlms.co.za',
    'http://localhost',
];
$origin = $_SERVER['HTTP_ORIGIN'] ?? '';
if (in_array($origin, $allowedOrigins, true)) {
    header('Access-Control-Allow-Origin: ' . $origin);
    header('Vary: Origin');
} else {
    header('Access-Control-Allow-Origin: *');
}
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('X-Content-Type-Options: nosniff');
header('Cache-Control: private, no-store, no-cache, must-revalidate');
header('Pragma: no-cache');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    header('Content-Type: application/json');
    http_response_code(405);
    echo json_encode(['error' => 'Method not allowed']);
    exit;
}

function safeResolvePath(string $relativePath): string|false
{
    $allowedBase = realpath(__DIR__);
    if ($allowedBase === false) return false;

    $relativePath = str_replace("\0", '', $relativePath);
    $relativePath = ltrim($relativePath, '/\\');

    $real = realpath($allowedBase . DIRECTORY_SEPARATOR . $relativePath);
    if ($real === false) {
        $real = realpath($allowedBase . DIRECTORY_SEPARATOR . '../' . $relativePath);
    }
    
    if ($real === false) {
        return false;
    }

    return $real;
}

function authorizeEvidenceFileAccess($conn, $user, $filename): bool 
{
    // Extract learner ID from evidence filename for authorization
    if (preg_match('/^(signature|face)_(\d+)_/', $filename, $matches)) {
        $learnerID = $matches[2];
        
        // Check if user has access to this learner's data - mobile uses facilitator and sdp tables only  
        // First check if user is a facilitator with access to this learner's class
        $stmt = $conn->prepare("
            SELECT COUNT(*) as count 
            FROM learnerdetails ld 
            JOIN class c ON ld.classID = c.classID 
            JOIN facilitator f ON (FIND_IN_SET(c.classID, f.classID) > 0 AND f.facilitator_id = ?)
            WHERE ld.LearnerID = ? 
            AND f.role IN ('facilitator', 'moderator', 'assessor', 'arpl_Assessor')
        ");
        
        if ($stmt) {
            $stmt->bind_param("ii", $user['user_id'], $learnerID);
            $stmt->execute();
            $result = $stmt->get_result();
            $row = $result->fetch_assoc();
            $stmt->close();
            
            if ($row['count'] > 0) {
                return true;
            }
        }
        
        // If not found as facilitator, check if user is SDP
        $stmt = $conn->prepare("
            SELECT COUNT(*) as count 
            FROM sdp s 
            WHERE s.sdp_id = ? AND s.role = 'sdp'
        ");
        
        if ($stmt) {
            $stmt->bind_param("i", $user['user_id']);
            $stmt->execute();
            $result = $stmt->get_result();
            $row = $result->fetch_assoc();
            $stmt->close();
            
            return $row['count'] > 0; // SDP users have access to all learners
        }
    }
    return false;
}

$fileMeta = null;
$isEvidenceFile = false;

// Handle evidence file requests (clocking signatures and face photos)
if (isset($_GET['filename']) && isset($_GET['type'])) {
    $filename = $_GET['filename'] ?? '';
    $type = $_GET['type'] ?? '';
    
    if (!empty($filename) && !empty($type)) {
        // SECURITY: Validate filename format (server-generated only)
        if (preg_match('/^(signature|face)_\d+_\d{8}_\d{6}_[a-f0-9]{8}_(in|out)\.(png|jpg)$/', $filename)) {
            // SECURITY: Validate type parameter
            if (in_array($type, ['signature', 'face_photo'], true)) {
                // SECURITY: Additional authorization check for evidence files
                if (authorizeEvidenceFileAccess($conn, $user, $filename)) {
                    $subDir = ($type === 'signature') ? 'signatures/' : 'face_photos/';
                    $fileMeta = [
                        'learner_id' => 0, // Evidence files don't use learner_id for path resolution
                        'relative_path' => 'clocking_evidence/' . $subDir . $filename,
                    ];
                    $isEvidenceFile = true;
                } else {
                    header('Content-Type: application/json');
                    http_response_code(403);
                    echo json_encode(['error' => 'Access denied to this evidence file']);
                    exit;
                }
            } else {
                header('Content-Type: application/json');
                http_response_code(400);
                echo json_encode(['error' => 'Invalid file type']);
                exit;
            }
        } else {
            header('Content-Type: application/json');
            http_response_code(400);
            echo json_encode(['error' => 'Invalid filename format']);
            exit;
        }
    }
}

// Handle POE file requests
if (!$fileMeta && isset($_GET['poe_id'])) {
    $poeId = filter_var($_GET['poe_id'], FILTER_VALIDATE_INT);
    if ($poeId && $poeId > 0) {
        $stmt = $conn->prepare("SELECT poe_id, learner_id, file_path FROM poe WHERE poe_id = ? LIMIT 1");
        if ($stmt) {
            $stmt->bind_param('i', $poeId);
            $stmt->execute();
            $result = $stmt->get_result();
            if ($result && $row = $result->fetch_assoc()) {
                $fileMeta = [
                    'learner_id' => (int)($row['learner_id'] ?? 0),
                    'relative_path' => $row['file_path'],
                ];
            }
            $stmt->close();
        }
    }
}

if (!$fileMeta && isset($_GET['file'])) {
    $relative_path = (string)$_GET['file'];
    
    // If path is just a filename (no directory separator), prepend appropriate folder
    // This handles files stored as just filename in database
    if (strpos($relative_path, '/') === false && strpos($relative_path, '\\') === false) {
        // Check if it looks like a signature/initial file (in signatures/ folder)
        // Matches: signature_123.png, witness_signature_123.png, learner_initials_123.png, etc.
        if (preg_match('/(^|_)(signature|initials)_\d+\.png$/i', $relative_path)) {
            $relative_path = 'signatures/' . $relative_path;
        }
        // Check if it looks like a learner profile image (in learnerImages/ folder)
        // Profile images typically start with learner ID or timestamp
        elseif (preg_match('/^\d+.*\.(jpg|jpeg|png|gif)$/i', $relative_path)) {
            $relative_path = 'learnerImages/' . $relative_path;
        }
    }
    
    $fileMeta = [
        'learner_id' => isset($_GET['learner_id']) ? (int)$_GET['learner_id'] : 0,
        'relative_path' => $relative_path,
    ];
}

if (!$fileMeta) {
    header('Content-Type: application/json');
    http_response_code(400);
    echo json_encode(['error' => 'Missing required parameters. Use: poe_id, file, or filename+type']);
    exit;
}

$file = safeResolvePath((string)$fileMeta['relative_path']);
if ($file === false || !is_file($file) || !is_readable($file)) {
    header('Content-Type: application/json');
    http_response_code(404);
    echo json_encode(['error' => 'File not found']);
    exit;
}

$allowedExtensions = ['pdf', 'jpg', 'jpeg', 'png'];
$ext = strtolower(pathinfo($file, PATHINFO_EXTENSION));
if (!in_array($ext, $allowedExtensions, true)) {
    header('Content-Type: application/json');
    http_response_code(403);
    echo json_encode(['error' => 'File type not allowed']);
    exit;
}

$mimeTypes = [
    'pdf' => 'application/pdf',
    'jpg' => 'image/jpeg',
    'jpeg' => 'image/jpeg',
    'png' => 'image/png',
];

$mimeType = $mimeTypes[$ext];

// Enhanced headers for evidence files
if ($isEvidenceFile) {
    header('Cache-Control: private, max-age=3600'); // Evidence files can cache for 1 hour
    header('X-Frame-Options: DENY');
} else {
    header('Cache-Control: private, no-store, no-cache, must-revalidate');
}

header('Content-Type: ' . $mimeType);
header('Content-Length: ' . filesize($file));
header('Content-Disposition: inline; filename="' . addslashes(basename($file)) . '"');
header('X-Content-Type-Options: nosniff');

$fp = fopen($file, 'rb');
if ($fp === false) {
    header('Content-Type: application/json');
    http_response_code(500);
    echo json_encode(['error' => 'Unable to open file']);
    exit;
}
fpassthru($fp);
fclose($fp);
exit;