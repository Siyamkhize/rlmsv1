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
    
    // Fetch all provinces
    $query = "SELECT DISTINCT name FROM province ORDER BY name";
    $stmt = $pdo->prepare($query);
    $stmt->execute();
    
    $provinces = [];
    while ($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
        $provinces[] = [
            'name' => $row['name']
        ];
    }
    
    echo json_encode([
        'success' => true,
        'provinces' => $provinces,
        'count' => count($provinces),
        'message' => 'Provinces fetched successfully'
    ]);
    
} catch (Exception $e) {
    echo json_encode([
        'success' => false,
        'message' => 'Error fetching provinces: ' . $e->getMessage(),
        'provinces' => []
    ]);
}
?>