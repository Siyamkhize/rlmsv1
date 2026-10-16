<?php
/**
 * Fetch Provinces - Returns list of all South African provinces
 */

// Disable error display to prevent HTML output in JSON response
error_reporting(E_ALL);
ini_set('display_errors', 0);
ini_set('log_errors', 1);

header('Content-Type: application/json');

require_once 'connection.php';
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

try {
    if (!isset($conn) || !$conn) {
        throw new Exception("Database connection failed");
    }
    
    // Fetch all provinces
    $stmt = $conn->prepare("SELECT id, province_name FROM province ORDER BY province_name ASC");
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
    
    $provinces = [];
    while ($row = $result->fetch_assoc()) {
        $provinces[] = [
            'id' => $row['province_name'],
            'name' => $row['province_name']
        ];
    }
    
    $stmt->close();
    
    http_response_code(200);
    echo json_encode([
        'success' => true,
        'message' => 'Provinces fetched successfully',
        'data' => [
            'provinces' => $provinces
        ]
    ]);
    
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Failed to fetch provinces: ' . $e->getMessage()
    ]);
}

if (isset($conn)) {
    $conn->close();
}
?>
