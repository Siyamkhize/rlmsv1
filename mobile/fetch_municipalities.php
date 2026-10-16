<?php
/**
 * Fetch Municipalities - Returns list of municipalities for a specific district
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
    
    // Get district parameter
    $district = isset($_GET['district']) ? trim($_GET['district']) : '';
    
    if (empty($district)) {
        http_response_code(400);
        echo json_encode([
            'success' => false,
            'message' => 'District parameter is required'
        ]);
        exit;
    }
    
    // Fetch municipalities for the specified district
    $stmt = $conn->prepare("SELECT DISTINCT local_municipality_name FROM local_municipality WHERE district_name = ? ORDER BY local_municipality_name ASC");
    if (!$stmt) {
        throw new Exception("Prepare failed: " . $conn->error);
    }
    
    $stmt->bind_param('s', $district);
    
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
            'id' => $row['local_municipality_name'],
            'name' => $row['local_municipality_name']
        ];
    }
    
    $stmt->close();
    
    http_response_code(200);
    echo json_encode([
        'success' => true,
        'message' => 'Municipalities fetched successfully',
        'data' => [
            'municipalities' => $municipalities
        ]
    ]);
    
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Failed to fetch municipalities: ' . $e->getMessage()
    ]);
}

if (isset($conn)) {
    $conn->close();
}
?>