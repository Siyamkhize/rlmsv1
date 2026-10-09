<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

// Handle preflight OPTIONS request
if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    exit(0);
}

try {
    include '../db.php';
    
    // Fetch all districts with their provinces
    $query = "SELECT name, province FROM district ORDER BY province, name";
    $stmt = $pdo->prepare($query);
    $stmt->execute();
    
    $districts = [];
    while ($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
        $districts[] = [
            'name' => $row['name'],
            'province' => $row['province']
        ];
    }
    
    echo json_encode([
        'success' => true,
        'districts' => $districts,
        'count' => count($districts),
        'message' => 'Districts fetched successfully'
    ]);
    
} catch (Exception $e) {
    echo json_encode([
        'success' => false,
        'message' => 'Error fetching districts: ' . $e->getMessage(),
        'districts' => []
    ]);
}
?>