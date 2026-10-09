<?php
require_once 'connection.php';

header('Content-Type: application/json');

// Get parameters
$action = isset($_GET['action']) ? $_GET['action'] : '';
$project_id = isset($_GET['project_id']) ? intval($_GET['project_id']) : 0;
$site_id = isset($_GET['site_id']) ? intval($_GET['site_id']) : 0;

try {
    if ($action === 'get_sites') {
        // Get sites based on project_id
        if ($project_id > 0) {
            $stmt = $conn->prepare("SELECT siteID, SiteName FROM sites WHERE project_id = ? ORDER BY SiteName");
            $stmt->bind_param("i", $project_id);
        } else {
            $stmt = $conn->prepare("SELECT siteID, SiteName FROM sites ORDER BY SiteName");
        }
        
        $stmt->execute();
        $result = $stmt->get_result();
        
        $sites = [];
        while ($row = $result->fetch_assoc()) {
            $sites[] = [
                'id' => $row['siteID'],
                'name' => $row['SiteName']
            ];
        }
        
        echo json_encode($sites);
        
    } elseif ($action === 'get_classes') {
        // Get classes based on site_id
        if ($site_id > 0) {
            $stmt = $conn->prepare("SELECT classID, ClassName FROM class WHERE siteID = ? ORDER BY ClassName");
            $stmt->bind_param("i", $site_id);
        } else {
            $stmt = $conn->prepare("SELECT classID, ClassName FROM class ORDER BY ClassName");
        }
        
        $stmt->execute();
        $result = $stmt->get_result();
        
        $classes = [];
        while ($row = $result->fetch_assoc()) {
            $classes[] = [
                'id' => $row['classID'],
                'name' => $row['ClassName']
            ];
        }
        
        echo json_encode($classes);
        
    } else {
        http_response_code(400);
        echo json_encode(['error' => 'Invalid action']);
    }
    
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['error' => 'Server error: ' . $e->getMessage()]);
}
?>