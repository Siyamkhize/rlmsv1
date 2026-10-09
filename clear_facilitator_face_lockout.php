<?php
/**
 * Clear Facilitator Face Verification Lockout
 *
 * Removes recent failed face verification attempts for a facilitator
 * to unlock them immediately.
 *
 * Usage: http://your-server/clear_facilitator_face_lockout.php?facilitator_id=148
 */

require_once 'connection.php';

header('Content-Type: application/json');

// Get facilitator ID from query parameter
$facilitator_id = isset($_GET['facilitator_id']) ? intval($_GET['facilitator_id']) : 0;

if ($facilitator_id === 0) {
    http_response_code(400);
    echo json_encode([
        'success' => false,
        'message' => 'Missing facilitator_id parameter'
    ]);
    exit;
}

try {
    // Delete failed attempts from the last 10 minutes
    $delete_sql = "DELETE FROM facilitator_face_verification_log 
                   WHERE facilitator_id = ? 
                   AND passed = 0 
                   AND verified_at > (NOW() - INTERVAL 10 MINUTE)";
    
    $stmt = $conn->prepare($delete_sql);
    
    if (!$stmt) {
        throw new Exception('Failed to prepare statement: ' . $conn->error);
    }
    
    $stmt->bind_param('i', $facilitator_id);
    $stmt->execute();
    
    $deleted_count = $stmt->affected_rows;
    $stmt->close();
    
    // Get remaining failed attempts (if any older than 10 minutes)
    $count_sql = "SELECT COUNT(*) as count FROM facilitator_face_verification_log 
                  WHERE facilitator_id = ? 
                  AND passed = 0 
                  AND verified_at > (NOW() - INTERVAL 10 MINUTE)";
    
    $count_stmt = $conn->prepare($count_sql);
    $count_stmt->bind_param('i', $facilitator_id);
    $count_stmt->execute();
    $result = $count_stmt->get_result();
    $row = $result->fetch_assoc();
    $remaining = $row['count'];
    $count_stmt->close();
    
    echo json_encode([
        'success' => true,
        'facilitator_id' => $facilitator_id,
        'deleted_attempts' => $deleted_count,
        'remaining_failed_attempts' => $remaining,
        'message' => $deleted_count > 0 
            ? "Cleared $deleted_count failed attempts. Facilitator $facilitator_id is now unlocked."
            : "No failed attempts found in the last 10 minutes. Facilitator $facilitator_id was not locked out."
    ]);
    
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'error' => $e->getMessage()
    ]);
}

$conn->close();
?>
