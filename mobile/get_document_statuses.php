<?php
/**
 * Get Document Statuses Endpoint
 * 
 * Note: Authentication temporarily relaxed for debugging
 */

error_reporting(E_ALL);
ini_set('display_errors', 1);
ini_set('log_errors', 1);

include 'connection.php';

header('Content-Type: application/json');

// TODO: Re-enable authentication after debugging
// require_once 'require_auth.php';
// $user = requireAuth($conn);

try {
    // Get learner ID from request
    $learner_id = null;
    
    if ($_SERVER['REQUEST_METHOD'] == 'POST') {
        $input = json_decode(file_get_contents('php://input'), true);
        $learner_id = isset($input['learner_id']) ? $input['learner_id'] : null;
        
        // Also support form data
        if (!$learner_id) {
            $learner_id = isset($_POST['learner_id']) ? $_POST['learner_id'] : null;
        }
    } else if ($_SERVER['REQUEST_METHOD'] == 'GET') {
        $learner_id = isset($_GET['learner_id']) ? $_GET['learner_id'] : null;
    }
    
    if (!$learner_id) {
        http_response_code(400);
        echo json_encode([
            'success' => false,
            'message' => 'learner_id is required',
            'error_code' => 'MISSING_REQUIRED_PARAMETER'
        ]);
        exit;
    }
    
    // Get all documents for this learner with status
    $query = "SELECT 
                documentName,
                status,
                rejection_reason,
                upload_date,
                learner_document,
                document_id
              FROM learner_document 
              WHERE learner_id = ? 
              ORDER BY document_id DESC";
    
    $stmt = $conn->prepare($query);
    if (!$stmt) {
        throw new Exception("Query prepare failed: " . $conn->error);
    }
    
    $stmt->bind_param('s', $learner_id);
    $stmt->execute();
    $result = $stmt->get_result();
    
    $documents = [];
    $latestDocs = []; // Track latest version of each document
    
    while ($row = $result->fetch_assoc()) {
        $docName = $row['documentName'];
        
        // Keep only the latest upload for each document type
        if (!isset($latestDocs[$docName])) {
            $latestDocs[$docName] = true;
            $documents[$docName] = [
                'status' => $row['status'] ?? 'Pending',
                'rejection_reason' => $row['rejection_reason'],
                'upload_date' => $row['upload_date'],
                'file_path' => $row['learner_document'],
                'document_id' => $row['document_id'],
            ];
        }
    }
    
    // Force documents to be an object even when empty (important for Flutter parsing)
    if (empty($documents)) {
        $documents = new stdClass(); // Empty object {} instead of empty array []
    }
    
    echo json_encode([
        'success' => true,
        'documents' => $documents,
        'total_documents' => count((array)$documents),
        'learner_id' => $learner_id,
        'timestamp' => date('Y-m-d H:i:s')
    ]);
    
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Database error: ' . $e->getMessage(),
        'error_code' => 'DATABASE_ERROR'
    ]);
} finally {
    if (isset($conn)) {
        $conn->close();
    }
}
?>
