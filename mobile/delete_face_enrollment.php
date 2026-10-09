<?php
/**
 * Delete Face Enrollment
 * 
 * Deletes a learner's face enrollment data (for re-enrollment)
 * This allows a learner to re-enroll their face with fresh data
 */

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

// Handle preflight requests
if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    exit(0);
}

// Log errors server-side
error_reporting(E_ALL);
ini_set('display_errors', 0);
ini_set('log_errors', 1);

// Include database connection
require_once '../connection.php';

// Get JSON input
$input = json_decode(file_get_contents('php://input'), true);

if (!isset($input['learner_id'])) {
    echo json_encode([
        'success' => false,
        'message' => 'learner_id is required'
    ]);
    exit;
}

$learnerId = intval($input['learner_id']);

if ($learnerId <= 0) {
    echo json_encode([
        'success' => false,
        'message' => 'Invalid learner_id'
    ]);
    exit;
}

try {
    // Delete from learner_faces table
    $stmt = $conn->prepare("DELETE FROM learner_faces WHERE learner_id = ?");
    $stmt->bind_param("i", $learnerId);
    $stmt->execute();
    $deletedFaces = $stmt->affected_rows;
    $stmt->close();
    
    // Optional: Also delete verification logs (commented out to keep history)
    // $stmt = $conn->prepare("DELETE FROM learner_face_verification_log WHERE learner_id = ?");
    // $stmt->bind_param("i", $learnerId);
    // $stmt->execute();
    // $deletedLogs = $stmt->affected_rows;
    // $stmt->close();
    
    echo json_encode([
        'success' => true,
        'message' => "Face enrollment deleted for learner $learnerId",
        'deleted_count' => $deletedFaces
    ]);
    
} catch (Exception $e) {
    error_log("Error deleting face enrollment: " . $e->getMessage());
    echo json_encode([
        'success' => false,
        'message' => 'Database error: ' . $e->getMessage()
    ]);
}
