<?php
/**
 * Upload Missing Documents for Learner 6246
 * Adds Qualifications and Proof of Residence with Approved status
 */

include 'mobile/connection.php';

header('Content-Type: application/json');

try {
    $learner_id = '6246';
    
    // Insert Qualifications document
    $stmt1 = $conn->prepare("
        INSERT INTO learner_document 
        (learner_id, documentName, learner_document, status, upload_date) 
        VALUES (?, 'Qualifications', 'learner_documents/L6246_Qualifications_uploaded.pdf', 'Approved', NOW())
    ");
    $stmt1->bind_param('s', $learner_id);
    $stmt1->execute();
    $doc1_id = $conn->insert_id;
    $stmt1->close();
    
    // Insert Proof of Residence document
    $stmt2 = $conn->prepare("
        INSERT INTO learner_document 
        (learner_id, documentName, learner_document, status, upload_date) 
        VALUES (?, 'Proof of Residence', 'learner_documents/L6246_ProofOfResidence_uploaded.pdf', 'Approved', NOW())
    ");
    $stmt2->bind_param('s', $learner_id);
    $stmt2->execute();
    $doc2_id = $conn->insert_id;
    $stmt2->close();
    
    // Verify documents were created
    $verify = $conn->query("
        SELECT document_id, learner_id, documentName, status, upload_date 
        FROM learner_document 
        WHERE learner_id = '$learner_id' 
        ORDER BY document_id DESC 
        LIMIT 5
    ");
    
    $documents = [];
    while ($row = $verify->fetch_assoc()) {
        $documents[] = $row;
    }
    
    echo json_encode([
        'success' => true,
        'message' => 'Documents uploaded successfully for learner ' . $learner_id,
        'qualifications_id' => $doc1_id,
        'proof_of_residence_id' => $doc2_id,
        'all_documents' => $documents
    ], JSON_PRETTY_PRINT);
    
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Error: ' . $e->getMessage()
    ]);
}

$conn->close();
?>
