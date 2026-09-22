<?php
/**
 * Fetch Districts - Returns list of districts for a specific province
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
    
    // Get province parameter
    $province = isset($_GET['province']) ? trim($_GET['province']) : '';
    
    if (empty($province)) {
        http_response_code(400);
        echo json_encode([
            'success' => false,
            'message' => 'Province parameter is required'
        ]);
        exit;
    }
    
    // Fetch districts for the specified province
    $stmt = $conn->prepare("SELECT DISTINCT District_name FROM district WHERE province_name = ? ORDER BY District_name ASC");
    if (!$stmt) {
        throw new Exception("Prepare failed: " . $conn->error);
    }
    
    $stmt->bind_param('s', $province);
    
    if (!$stmt->execute()) {
        throw new Exception("Execute failed: " . $stmt->error);
    }
    
    $result = $stmt->get_result();
    if (!$result) {
        throw new Exception("Get result failed: " . $stmt->error);
    }
    
    $districts = [];
    while ($row = $result->fetch_assoc()) {
        $districts[] = [
            'id' => $row['District_name'],
            'name' => $row['District_name']
        ];
    }
    
    $stmt->close();
    
    http_response_code(200);
    echo json_encode([
        'success' => true,
        'message' => 'Districts fetched successfully',
        'data' => [
            'districts' => $districts
        ]
    ]);
    
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Failed to fetch districts: ' . $e->getMessage()
    ]);
}

if (isset($conn)) {
    $conn->close();
}
?>
