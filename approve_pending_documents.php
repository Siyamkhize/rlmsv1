<?php
// Approve all pending documents for testing
require_once 'mobile/connection.php';

header('Content-Type: application/json');

// Validate learner_id input
$learner_id = filter_var($_GET['learner_id'] ?? null, FILTER_VALIDATE_INT);

if ($learner_id === false || $learner_id === null || $learner_id <= 0) {
    http_response_code(400);
    echo json_encode([
        'error' => 'Invalid learner_id parameter',
        'message' => 'learner_id must be a positive integer'
    ]);
    exit;
}

// Update all pending documents to approved
$sql = "UPDATE learner_documents 
        SET status = 'Approved', 
            rejection_reason = NULL 
        WHERE learner_id = ? AND status = 'Pending'";

$stmt = $con->prepare($sql);
$stmt->bind_param('i', $learner_id);

if ($stmt->execute()) {
    $affected = $stmt->affected_rows;
    
    // Get all documents for this learner
    $sql = "SELECT document_id, document_type, status, upload_date 
            FROM learner_documents 
            WHERE learner_id = ?";
    $stmt = $con->prepare($sql);
    $stmt->bind_param('i', $learner_id);
    $stmt->execute();
    $result = $stmt->get_result();
    
    $documents = [];
    while ($row = $result->fetch_assoc()) {
        $documents[] = $row;
    }
    
    echo json_encode([
        'success' => true,
        'approved_count' => $affected,
        'documents' => $documents
    ]);
} else {
    echo json_encode(['error' => $stmt->error]);
}

$stmt->close();
$con->close();
?>
