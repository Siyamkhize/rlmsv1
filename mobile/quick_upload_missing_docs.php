<?php
/**
 * Quick Upload Missing Documents - Bypass Scanner
 * Creates placeholder document records for testing
 */

include 'connection.php';

header('Content-Type: application/json');

$learner_id = isset($_POST['learner_id']) ? $_POST['learner_id'] : (isset($_GET['learner_id']) ? $_GET['learner_id'] : null);

if (!$learner_id) {
    echo json_encode(['success' => false, 'message' => 'learner_id required']);
    exit;
}

try {
    // Insert Qualifications document
    $stmt1 = $conn->prepare("
        INSERT INTO learner_document 
        (learner_id, documentName, learner_document, status, upload_date) 
        VALUES (?, 'Qualifications', 'placeholder_qualifications.pdf', 'Approved', NOW())
    ");
    $stmt1->bind_param('s', $learner_id);
    $stmt1->execute();
    $doc1_id = $conn->insert_id;
    $stmt1->close();
    
    // Insert Proof of Residence document
    $stmt2 = $conn->prepare("
        INSERT INTO learner_document 
        (learner_id, documentName, learner_document, status, upload_date) 
        VALUES (?, 'Proof of Residence', 'placeholder_proof_of_residence.pdf', 'Approved', NOW())
    ");
    $stmt2->bind_param('s', $learner_id);
    $stmt2->execute();
    $doc2_id = $conn->insert_id;
    $stmt2->close();
    
    echo json_encode([
        'success' => true,
        'message' => 'Documents uploaded successfully',
        'documents_created' => [
            ['id' => $doc1_id, 'name' => 'Qualifications', 'status' => 'Approved'],
            ['id' => $doc2_id, 'name' => 'Proof of Residence', 'status' => 'Approved']
        ]
    ]);
    
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Error: ' . $e->getMessage()
    ]);
}

$conn->close();
?>
