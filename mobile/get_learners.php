<?php
/**
 * Get Learners Endpoint - SECURED
 * 
 * Security Features:
 * - Bearer token authentication required
 * - Rate limiting: 60 requests per minute
 * - Input validation for classID
 * - SQL injection protection via prepared statements
 * 
 * @security CRITICAL - Authentication required
 */

require_once 'require_auth.php';
include('connection.php');

header('Content-Type: application/json');
error_reporting(0); // Hide warnings
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

// SECURITY: Require authentication
$user = requireAuth($conn);

// SECURITY: Apply rate limiting (60 requests per minute)
applyRateLimit($conn, 'get_learners');

// SECURITY: Validate required parameters
if (!isset($_GET['classID'])) {
    sendError('classID is required', 400, 'MISSING_PARAMETER');
}

// SECURITY: Validate classID is a valid integer
$classID = validate_int($_GET['classID'], 1);
if ($classID === false) {
    sendError('Invalid classID format', 400, 'INVALID_PARAMETER');
}
// PAGINATION: Support lazy loading OR fetch all if no pagination params
$usePagination = isset($_GET['page']) || isset($_GET['pageSize']);

if ($usePagination) {
    $page = isset($_GET['page']) ? validate_int($_GET['page'], 1) : 1;
    $pageSize = isset($_GET['pageSize']) ? validate_int($_GET['pageSize'], 1, 100) : 30;

    if ($page === false || $pageSize === false) {
        sendError('Invalid pagination parameters', 400, 'INVALID_PARAMETER');
    }

    $offset = ($page - 1) * $pageSize;

    // Get total count for pagination metadata (exclude NULL classID)
    $countQuery = "SELECT COUNT(*) as total FROM learnerdetails WHERE classID = ? AND classID IS NOT NULL";
    $countStmt = $conn->prepare($countQuery);
    $countStmt->bind_param("i", $classID);
    $countStmt->execute();
    $countResult = $countStmt->get_result();
    $totalCount = $countResult->fetch_assoc()['total'];
    $countStmt->close();

    // Get paginated results (exclude NULL classID)
    $query = "SELECT * FROM learnerdetails WHERE classID = ? AND classID IS NOT NULL LIMIT ? OFFSET ?";
    $stmt = $conn->prepare($query);
    $stmt->bind_param("iii", $classID, $pageSize, $offset);
} else {
    // NO PAGINATION: Fetch ALL learners for this class (for offline sync)
    // Explicitly exclude learners with NULL classID
    $query = "SELECT * FROM learnerdetails WHERE classID = ? AND classID IS NOT NULL";
    $stmt = $conn->prepare($query);
    $stmt->bind_param("i", $classID);
    
    // Get total count
    $countQuery = "SELECT COUNT(*) as total FROM learnerdetails WHERE classID = ?";
    $countStmt = $conn->prepare($countQuery);
    $countStmt->bind_param("i", $classID);
    $countStmt->execute();
    $countResult = $countStmt->get_result();
    $totalCount = $countResult->fetch_assoc()['total'];
    $countStmt->close();
}

$stmt->execute();
$result = $stmt->get_result();

$classes = [];
while ($row = $result->fetch_assoc()) {
    $classes[] = $row;
}

// Return response with appropriate metadata
if ($usePagination) {
    $response = [
        'success' => true,
        'data' => $classes,
        'pagination' => [
            'page' => $page,
            'pageSize' => $pageSize,
            'total' => $totalCount,
            'totalPages' => ceil($totalCount / $pageSize),
            'hasMore' => ($offset + $pageSize) < $totalCount
        ]
    ];
} else {
    // Non-paginated response (all records)
    $response = [
        'success' => true,
        'data' => $classes,
        'pagination' => [
            'page' => 1,
            'pageSize' => $totalCount,
            'total' => $totalCount,
            'totalPages' => 1,
            'hasMore' => false
        ]
    ];
}

echo json_encode($response, JSON_PRETTY_PRINT);
$stmt->close();
$conn->close();
?>
