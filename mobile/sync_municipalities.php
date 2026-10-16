<?php
// Disable error display to prevent HTML output in JSON response
error_reporting(E_ALL);
ini_set('display_errors', 0);
ini_set('log_errors', 1);

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

// Handle preflight OPTIONS request
if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    exit(0);
}

require_once 'connection.php';

try {
    if (!isset($conn) || !$conn) {
        throw new Exception("Database connection failed");
    }
    
    // Fetch all municipalities with their districts
    $stmt = $conn->prepare("SELECT name, district FROM local_municipality ORDER BY district, name");
    if (!$stmt) {
        throw new Exception("Prepare failed: " . $conn->error);
    }
    
    if (!$stmt->execute()) {
        throw new Exception("Execute failed: " . $stmt->error);
    }
    
    $result = $stmt->get_result();
    if (!$result) {
        throw new Exception("Get result failed: " . $stmt->error);
    }
    
    $municipalities = [];
    while ($row = $result->fetch_assoc()) {
        $municipalities[] = [
            'name' => $row['name'],
            'district' => $row['district']
        ];
    }
    
    $stmt->close();
    
    echo json_encode([
        'success' => true,
        'municipalities' => $municipalities,
        'count' => count($municipalities),
        'message' => 'Municipalities fetched successfully'
    ]);
    
} catch (Exception $e) {
    echo json_encode([
        'success' => false,
        'message' => 'Error fetching municipalities: ' . $e->getMessage(),
        'municipalities' => []
    ]);
}

if (isset($conn)) {
    $conn->close();
}
?>