<?php
/**
 * Fetch Provinces - Returns list of South African provinces
 */

error_reporting(E_ALL);
ini_set('display_errors', 1);

require_once 'connection.php';

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

try {
    if (!isset($conn) || !$conn) {
        throw new Exception("Database connection failed");
    }
    
    // Fetch provinces from database
    $query = "SELECT DISTINCT province_name FROM province ORDER BY province_name ASC";
    $result = $conn->query($query);
    
    if (!$result) {
        throw new Exception("Query failed: " . $conn->error);
    }
    
    $provinces = [];
    while ($row = $result->fetch_assoc()) {
        $provinces[] = [
            'id' => $row['province_name'],
            'name' => $row['province_name']
        ];
    }
    
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
