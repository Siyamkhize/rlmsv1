<?php
/**
 * Deploy sync_learners_by_class.php to server
 * Upload this file to the server and run it via browser
 */

$fileContent = <<<'EOD'
<?php
/**
 * Sync Learners By Class Endpoint - PUBLIC (for offline sync)
 * 
 * Returns ALL learners for a specific class for offline sync
 * 
 * Security Features:
 * - Input validation for classID
 * - SQL injection protection via prepared statements
 * 
 * @note NO AUTHENTICATION REQUIRED - Designed for offline sync use case
 */

include('connection.php');

header('Content-Type: application/json');
error_reporting(0); // Hide warnings
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

// Validate required parameters
if (!isset($_GET['classID'])) {
    http_response_code(400);
    echo json_encode([
        'success' => false,
        'error' => 'classID is required',
        'code' => 'MISSING_PARAMETER'
    ]);
    exit;
}

// Validate classID is a valid integer
$classID = filter_var($_GET['classID'], FILTER_VALIDATE_INT);
if ($classID === false || $classID < 1) {
    http_response_code(400);
    echo json_encode([
        'success' => false,
        'error' => 'Invalid classID format',
        'code' => 'INVALID_PARAMETER'
    ]);
    exit;
}

try {
    // Query to get ALL learner data for the specified class
    // Using SELECT * to get all columns automatically
    // Filter out learners with null classID
    $sql = "SELECT l.*, c.ClassName, c.SiteID, p.Project_name
            FROM learnerdetails l
            LEFT JOIN class c ON l.classID = c.ClassID
            LEFT JOIN sites s ON s.siteID = c.siteID
            LEFT JOIN project p ON s.project_id = p.project_id
            WHERE l.classID = ?
            AND l.classID IS NOT NULL
            ORDER BY l.Surname, l.Name";
    
    $stmt = $conn->prepare($sql);
    if (!$stmt) {
        http_response_code(500);
        echo json_encode([
            'success' => false,
            'error' => 'Database error: Failed to prepare statement',
            'code' => 'DB_ERROR'
        ]);
        exit;
    }
    
    $stmt->bind_param("i", $classID);
    
    if (!$stmt->execute()) {
        http_response_code(500);
        echo json_encode([
            'success' => false,
            'error' => 'Database error: Failed to execute query',
            'code' => 'DB_ERROR'
        ]);
        exit;
    }
    
    $result = $stmt->get_result();
    $learners = [];
    
    while ($row = $result->fetch_assoc()) {
        $learners[] = $row;
    }
    
    $stmt->close();
    
    // Return response with success flag and data array
    // Using the same format as get_learners.php for consistency
    echo json_encode([
        'success' => true,
        'data' => $learners,
        'count' => count($learners),
        'classID' => $classID,
        'timestamp' => date('Y-m-d H:i:s')
    ]);
    
} catch (Exception $e) {
    error_log("sync_learners_by_class.php error: " . $e->getMessage());
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'error' => 'Server error occurred',
        'code' => 'SERVER_ERROR'
    ]);
}

$conn->close();
?>
EOD;

// Write the file
$targetFile = __DIR__ . '/mobile/sync_learners_by_class.php';
$result = file_put_contents($targetFile, $fileContent);

if ($result !== false) {
    echo "✅ Successfully deployed sync_learners_by_class.php ($result bytes written)<br>";
    echo "Endpoint URL: <a href='https://rlms.rlms.co.za/mobile/sync_learners_by_class.php?classID=790'>Test it here</a>";
} else {
    echo "❌ Failed to deploy sync_learners_by_class.php";
}
?>
