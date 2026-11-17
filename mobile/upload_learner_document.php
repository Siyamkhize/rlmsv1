<?php
header('Content-Type: application/json');

include'connection.php';
// Create connection
$conn = new mysqli($servername, $username, $password, $dbname);
if ($conn->connect_error) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Database connection failed: ' . $conn->connect_error
    ]);
    exit;
}

try {
    // Validate required POST fields
    if (!isset($_POST['learner_id'], $_POST['documentName'], $_POST['upload_date'], $_FILES['learner_document'])) {
        throw new Exception('Missing required fields');
    }

    $learnerId = $conn->real_escape_string($_POST['learner_id']);
    $documentName = $conn->real_escape_string($_POST['documentName']);
    
    // Convert documentName to lowercase with underscores for document_type
    // "ID Document" -> "id_document", "Bank Confirmation Letter" -> "bank_confirmation_letter"
    $documentType = strtolower(str_replace(' ', '_', $documentName));
    
    $uploadDate = $conn->real_escape_string($_POST['upload_date']);
    $status = isset($_POST['status']) ? $conn->real_escape_string($_POST['status']) : 'Pending';
    $synced = isset($_POST['synced']) ? (int)$_POST['synced'] : 1; // Mark as synced on server
    $rejectionReason = isset($_POST['rejection_reason']) ? $conn->real_escape_string($_POST['rejection_reason']) : null;

    // Validate file upload
    $file = $_FILES['learner_document'];
    if ($file['error'] !== UPLOAD_ERR_OK) {
        throw new Exception('File upload error: ' . $file['error']);
    }

    // Validate file type and size
    $allowedExtensions = ['pdf'];
    $maxFileSize = 5 * 1024 * 1024; // 5MB
    $fileExtension = strtolower(pathinfo($file['name'], PATHINFO_EXTENSION));
    if (!in_array($fileExtension, $allowedExtensions)) {
        throw new Exception('Invalid file type. Only PDF files are allowed.');
    }
    if ($file['size'] > $maxFileSize) {
        throw new Exception('File size exceeds 5MB limit.');
    }

    // Create uploads directory if it doesn't exist
    $uploadDir = 'learner_documents/';
    if (!is_dir($uploadDir)) {
        mkdir($uploadDir, 0755, true);
    }

    // Generate unique filename to avoid conflicts
    $uniqueFilename = uniqid('doc_', true) . '.' . $fileExtension;
    $destination = $uploadDir . $uniqueFilename;

    // Move uploaded file to destination
    if (!move_uploaded_file($file['tmp_name'], $destination)) {
        throw new Exception('Failed to save file on server.');
    }

    // Insert document record into database
    $query = "INSERT INTO learner_document (
        learner_id, documentName, document_type, learner_document, status, upload_date, synced, rejection_reason
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)";
    $stmt = $conn->prepare($query);
    if (!$stmt) {
        throw new Exception('Prepare failed: ' . $conn->error);
    }

    $stmt->bind_param(
        'ssssssis',
        $learnerId,
        $documentName,
        $documentType,
        $destination,
        $status,
        $uploadDate,
        $synced,
        $rejectionReason
    );

    if (!$stmt->execute()) {
        throw new Exception('Execute failed: ' . $stmt->error);
    }

    $documentId = $conn->insert_id;

    // Return success response
    echo json_encode([
        'success' => true,
        'message' => 'Document uploaded successfully',
        'document_id' => $documentId,
    ]);

} catch (Exception $e) {
    // Return error response
    http_response_code(400);
    echo json_encode([
        'success' => false,
        'message' => $e->getMessage(),
    ]);
} finally {
    // Close statement and connection
    if (isset($stmt)) {
        $stmt->close();
    }
    $conn->close();
}
?>