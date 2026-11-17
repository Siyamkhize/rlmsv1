<?php
require_once 'connection.php';

error_reporting(E_ALL);
ini_set('display_errors', 1);
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header("Access-Control-Allow-Methods: POST, GET, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Authorization");

// ENHANCED DEBUG: Log all incoming data to file
$debug_log = 'signature_upload_debug.log';
$debug_data = [
    'timestamp' => date('Y-m-d H:i:s'),
    'POST' => $_POST,
    'FILES' => $_FILES,
    'SERVER' => [
        'REQUEST_METHOD' => $_SERVER['REQUEST_METHOD'],
        'CONTENT_TYPE' => $_SERVER['CONTENT_TYPE'] ?? 'not set',
        'CONTENT_LENGTH' => $_SERVER['CONTENT_LENGTH'] ?? 'not set',
    ]
];
file_put_contents($debug_log, "=== NEW REQUEST ===\n" . print_r($debug_data, true) . "\n\n", FILE_APPEND);

// DEBUG: Log all incoming data
error_log("=== SIGNATURE UPLOAD REQUEST ===");
error_log("POST data: " . print_r($_POST, true));
error_log("FILES data: " . print_r($_FILES, true));
error_log("================================");

// Use the connection from connection.php (already defined as $conn)


// Determine which signature field is present
$field_name = '';
$signature = null;
if (isset($_FILES['signature'])) {
    $field_name = 'signature';
    $signature = $_FILES['signature'];
    file_put_contents('signature_upload_debug.log', "Field detected: signature\n", FILE_APPEND);
} elseif (isset($_FILES['witness_signature'])) {
    $field_name = 'witness_signature';
    $signature = $_FILES['witness_signature'];
    file_put_contents('signature_upload_debug.log', "Field detected: witness_signature\n", FILE_APPEND);
}

if ($signature && isset($_POST['learner_id'])) {
    file_put_contents('signature_upload_debug.log', "Inside main IF block - learner_id: {$_POST['learner_id']}, field: $field_name\n", FILE_APPEND);
    
    $learner_id = trim($_POST['learner_id']); // Trim to avoid whitespace issues
    error_log("Received learner_id: $learner_id, field_name: $field_name");

    // Validate learner_id exists
    $check_query = "SELECT LearnerID FROM learnerdetails WHERE LearnerID = ?";
    $check_stmt = $conn->prepare($check_query);
    $check_stmt->bind_param("i", $learner_id);
    $check_stmt->execute();
    $check_result = $check_stmt->get_result();
    if ($check_result->num_rows === 0) {
        error_log("No learner found with LearnerID: $learner_id");
        echo json_encode(['success' => false, 'message' => 'No learner found with LearnerID: ' . $learner_id]);
        $check_stmt->close();
        $conn->close();
        exit();
    }
    $check_stmt->close();

    // Ensure upload directory exists
    $upload_dir = 'signatures/';
    if (!is_dir($upload_dir)) {
        mkdir($upload_dir, 0775, true);
    }

    // Generate simple filename: signature_LEARNERID.png or witness_signature_LEARNERID.png
    $file_name = $field_name . '_' . $learner_id . '.png';
    $file_path = $upload_dir . $file_name;

    if ($signature['error'] !== UPLOAD_ERR_OK) {
        error_log("File upload error for $field_name: " . $signature['error']);
        echo json_encode(['success' => false, 'message' => 'File upload error: ' . $signature['error']]);
        $conn->close();
        exit();
    }

    if (move_uploaded_file($signature['tmp_name'], $file_path)) {
        file_put_contents('signature_upload_debug.log', "File moved successfully to: $file_path\n", FILE_APPEND);
        
        // Update database - ALWAYS update, overwrite old signature
        $column = $field_name === 'signature' ? 'signature' : 'witness_signature';
        file_put_contents('signature_upload_debug.log', "About to UPDATE column: $column with value: $file_name for learner: $learner_id\n", FILE_APPEND);
        
        $sql = "UPDATE learnerdetails SET $column = ? WHERE LearnerID = ?";
        $stmt = $conn->prepare($sql);

        if ($stmt === false) {
            file_put_contents('signature_upload_debug.log', "FAILED to prepare statement: " . $conn->error . "\n", FILE_APPEND);
            error_log("Failed to prepare statement: " . $conn->error);
            echo json_encode(['success' => false, 'message' => 'Failed to prepare statement: ' . $conn->error]);
            $conn->close();
            exit();
        }

        file_put_contents('signature_upload_debug.log', "Statement prepared successfully\n", FILE_APPEND);
        $stmt->bind_param("si", $file_name, $learner_id);
        file_put_contents('signature_upload_debug.log', "Parameters bound\n", FILE_APPEND);

        if ($stmt->execute()) {
            file_put_contents('signature_upload_debug.log', "✅ UPDATE executed successfully! Affected rows: " . $stmt->affected_rows . "\n", FILE_APPEND);
            error_log("Signature saved for learner_id: $learner_id, column: $column, file: $file_name");
            echo json_encode(['success' => true, 'message' => "$field_name saved successfully", 'filename' => $file_name]);
        } else {
            file_put_contents('signature_upload_debug.log', "❌ UPDATE execution FAILED: " . $stmt->error . "\n", FILE_APPEND);
            error_log("Failed to execute statement: " . $stmt->error);
            echo json_encode(['success' => false, 'message' => 'Failed to execute statement: ' . $stmt->error]);
        }

        $stmt->close();
    } else {
        error_log("Failed to move uploaded file to $file_path");
        echo json_encode(['success' => false, 'message' => 'Failed to save signature. Error code: ' . $signature['error']]);
    }
} else {
    error_log("Invalid request: signature or learner_id missing");
    echo json_encode(['success' => false, 'message' => 'Invalid request: signature or learner_id missing']);
}

$conn->close();

// Log completion
file_put_contents('signature_upload_debug.log', "=== REQUEST COMPLETED ===\n\n", FILE_APPEND);
?>