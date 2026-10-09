<?php
/**
 * Clear Failed Face Verification Attempts for a Learner
 * 
 * This script clears failed face verification attempts from the database
 * to unlock a learner who has been locked out due to too many failed attempts.
 * 
 * Usage: clear_learner_face_failed_attempts.php?learner_id=12345
 */

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');

// Include database connection
require_once 'connection.php';

// Get learner ID from query parameter
$learnerId = isset($_GET['learner_id']) ? trim($_GET['learner_id']) : '';

if (empty($learnerId)) {
    echo json_encode([
        'success' => false,
        'message' => 'learner_id parameter is required'
    ]);
    exit;
}

try {
    // Delete failed attempts for this learner
    $stmt = $conn->prepare("
        DELETE FROM learner_face_failed_attempts 
        WHERE learner_id = ?
    ");
    
    $stmt->bind_param("s", $learnerId);
    $stmt->execute();
    $deletedCount = $stmt->affected_rows;
    $stmt->close();
    
    echo json_encode([
        'success' => true,
        'message' => "Cleared $deletedCount failed attempts for learner $learnerId",
        'deleted_count' => $deletedCount,
        'learner_id' => $learnerId
    ]);
    
} catch (Exception $e) {
    error_log("Failed to clear learner face attempts: " . $e->getMessage());
    echo json_encode([
        'success' => false,
        'message' => 'Database error: ' . $e->getMessage()
    ]);
}
