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
    
    // Fetch all municipalities with their districts
    $query = "SELECT name, district FROM local_municipality ORDER BY district, name";
    $stmt = $pdo->prepare($query);
    $stmt->execute();
    
    $municipalities = [];
    while ($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
        $municipalities[] = [
            'name' => $row['name'],
            'district' => $row['district']
        ];
    }
    
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
?>