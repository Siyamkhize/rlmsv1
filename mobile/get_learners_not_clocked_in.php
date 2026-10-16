<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

require_once '../config.php';

// Get parameters
$classID = isset($_GET['classID']) ? trim($_GET['classID']) : '';
$clock_date = isset($_GET['clock_date']) ? trim($_GET['clock_date']) : date('Y-m-d');

if (empty($classID)) {
    echo json_encode([
        'status' => 'error',
        'message' => 'classID is required'
    ]);
    exit;
}

try {
    $conn = new mysqli(DB_HOST, DB_USER, DB_PASS, DB_NAME);
    
    if ($conn->connect_error) {
        throw new Exception("Connection failed: " . $conn->connect_error);
    }
    
    $conn->set_charset("utf8mb4");
    
    // Get learners who have NOT clocked in today for this class
    $sql = "
        SELECT 
            l.LearnerID, 
            l.Name, 
            l.Surname,
            l.IDNumber
        FROM learnerdetails l
        WHERE l.classID = ?
        AND l.LearnerID NOT IN (
            SELECT LearnerID 
            FROM manual_clocking 
            WHERE clock_date = ? 
            AND clock_in_time IS NOT NULL 
            AND clock_in_time != ''
        )
        ORDER BY l.Name ASC
    ";
    
    $stmt = $conn->prepare($sql);
    $stmt->bind_param("ss", $classID, $clock_date);
    $stmt->execute();
    $result = $stmt->get_result();
    
    $learners = [];
    while ($row = $result->fetch_assoc()) {
        $learners[] = [
            'LearnerID' => $row['LearnerID'],
            'Name' => $row['Name'],
            'Surname' => $row['Surname'],
            'IDNumber' => $row['IDNumber']
        ];
    }
    
    echo json_encode([
        'status' => 'success',
        'data' => $learners,
        'count' => count($learners),
        'clock_date' => $clock_date
    ]);
    
    $stmt->close();
    $conn->close();
    
} catch (Exception $e) {
    echo json_encode([
        'status' => 'error',
        'message' => $e->getMessage()
    ]);
}
?>
