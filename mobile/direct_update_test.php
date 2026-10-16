<?php
/**
 * Direct test of update_learner.php logic
 * Bypasses HTTP to see if the code itself works
 */

echo "=== DIRECT UPDATE TEST ===\n\n";

// Simulate POST request
$_SERVER['REQUEST_METHOD'] = 'POST';

// Simulate JSON input
$testInput = [
    'LearnerID' => '6246',
    'data' => [
        'Province' => 'Free State',
        'District' => 'Mangaung',
        'Municipality' => 'Bloem'
    ]
];

// Mock the php://input stream
$GLOBALS['mock_php_input'] = json_encode($testInput);

// Override file_get_contents for php://input
if (!function_exists('original_file_get_contents')) {
    function original_file_get_contents($filename) {
        return \file_get_contents($filename);
    }
}

// Include the update file (this will execute it)
ob_start();
$_POST = $testInput; // Also set POST data as backup

// Create a test by directly using the update logic
require_once 'connection.php';

$learnerID = '6246';
$updateData = [
    'Province' => 'Free State',
    'District' => 'Mangaung', 
    'Municipality' => 'Bloem'
];

echo "Updating Learner $learnerID with:\n";
print_r($updateData);
echo "\n";

try {
    $updateFields = [];
    $updateValues = [];
    $updateTypes = '';

    foreach ($updateData as $key => $value) {
        $updateFields[] = "`$key` = ?";
        $updateValues[] = $value;
        $updateTypes .= 's';
    }

    $updateValues[] = $learnerID;
    $updateTypes .= 's';

    $sql = "UPDATE learnerdetails SET " . implode(', ', $updateFields) . " WHERE LearnerID = ?";
    echo "SQL: $sql\n\n";
    
    $stmt = $conn->prepare($sql);
    $stmt->bind_param($updateTypes, ...$updateValues);
    
    if ($stmt->execute()) {
        echo "✅ UPDATE SUCCESSFUL\n";
        echo "Rows affected: " . $stmt->affected_rows . "\n";
    } else {
        echo "❌ UPDATE FAILED: " . $stmt->error . "\n";
    }
    
    $stmt->close();
    
    // Verify
    echo "\nVerifying update:\n";
    $checkStmt = $conn->prepare('SELECT Province, District, Municipality FROM learnerdetails WHERE LearnerID = ?');
    $checkStmt->bind_param('s', $learnerID);
    $checkStmt->execute();
    $result = $checkStmt->get_result();
    $row = $result->fetch_assoc();
    
    echo "Current values:\n";
    print_r($row);
    
} catch (Exception $e) {
    echo "❌ ERROR: " . $e->getMessage() . "\n";
}

$conn->close();
