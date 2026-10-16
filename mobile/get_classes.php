<?php
include('connection.php');
require_once __DIR__ . '/require_auth.php';

header('Content-Type: application/json');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
error_reporting(0); // Hide warnings
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

// SECURITY: Require authentication
/** @var mysqli $conn */
$user = requireAuth($conn);
$authenticated_user_id = $user['user_id'];
$authenticated_role = $user['user_role'];

// SECURITY: Apply rate limiting
applyRateLimit($conn, 'get_classes', 60);

if (!isset($_GET['facilitator_id'])) {
    echo json_encode(["error" => "facilitator_id is required"]);
    exit;
}

$facilitator_id = $_GET['facilitator_id'];

// Log the incoming request
error_log("[GET_CLASSES] Request for facilitator_id: $facilitator_id");

$query = "
    SELECT 
        c.classID,
        c.className,
        c.siteID,
        c.numberOfLearners,
        s.project_id, 
        s.Project_pathway
    FROM class c
    JOIN sites s ON s.siteID = c.siteID
    JOIN facilitator f ON FIND_IN_SET(c.classID, f.classID) > 0
    WHERE f.facilitator_id = ?
    ORDER BY c.className
";

$stmt = $conn->prepare($query);
$stmt->bind_param("i", $facilitator_id);
$stmt->execute();
$result = $stmt->get_result();

$classes = [];
while ($row = $result->fetch_assoc()) {
    // Explicitly ensure Project_pathway is present in the response
    if (empty($row['Project_pathway'])) {
        $row['Project_pathway'] = '';
        error_log("[GET_CLASSES] WARNING: Empty Project_pathway for classID {$row['classID']}");
    } else {
        error_log("[GET_CLASSES] ClassID {$row['classID']}: Project_pathway = '{$row['Project_pathway']}'");
    }
    $classes[] = $row;
}

error_log("[GET_CLASSES] Returning " . count($classes) . " classes for facilitator $facilitator_id");
if (count($classes) > 0) {
    error_log("[GET_CLASSES] First class: " . json_encode($classes[0]));
}

echo json_encode($classes, JSON_PRETTY_PRINT);
$stmt->close();
$conn->close();
?>
