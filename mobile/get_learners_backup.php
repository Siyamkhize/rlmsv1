<?php
include('connection.php');
header('Content-Type: application/json');
error_reporting(0); // Hide warnings
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

if (!isset($_GET['classID'])) {
    echo json_encode(["error" => "classID is required"]);
    exit;
}

$classID = $_GET['classID'];
$query = "SELECT * FROM learnerdetails WHERE classID = ?
";

$stmt = $conn->prepare($query);
$stmt->bind_param("i", $classID);
$stmt->execute();
$result = $stmt->get_result();

$classes = [];
while ($row = $result->fetch_assoc()) {
    $classes[] = $row;
}

echo json_encode($classes, JSON_PRETTY_PRINT);
$stmt->close();
$conn->close();
?>
