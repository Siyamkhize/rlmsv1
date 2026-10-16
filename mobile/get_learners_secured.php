<?php
/**
 * Secured Get Learners Endpoint (Example Implementation)
 * 
 * This is an example of how to properly secure an API endpoint with auth middleware
 * 
 * To secure the actual get_learners.php, replace its contents with this pattern
 */

require_once('connection.php');
require_once('auth_middleware.php');

// Set JSON response header
header('Content-Type: application/json');

// ✅ STEP 1: Validate authentication token
$auth = requireAuth($conn, ['facilitator', 'assessor', 'sdp', 'arpl_assessor']);

// If we reach here, the user is authenticated and authorized
$user_id = $auth['user_id'];
$user_role = $auth['user_role'];

// ✅ STEP 2: Get request parameters
$classID = $_POST['classID'] ?? $_GET['classID'] ?? null;

if (empty($classID)) {
    http_response_code(400);
    echo json_encode([
        'success' => false,
        'error' => 'Missing required parameter: classID'
    ]);
    exit;
}

// ✅ STEP 3: Additional authorization check - user can only access their own class
// (Optional - depends on your business rules)
if ($user_role === 'facilitator') {
    // Verify this facilitator has access to this class
    $stmt = $conn->prepare("
        SELECT classID FROM facilitator 
        WHERE facilitator_id = ? AND classID = ?
    ");
    $stmt->bind_param("ss", $user_id, $classID);
    $stmt->execute();
    $result = $stmt->get_result();
    
    if ($result->num_rows === 0) {
        http_response_code(403);
        echo json_encode([
            'success' => false,
            'error' => 'You do not have access to this class'
        ]);
        exit;
    }
    $stmt->close();
}

// ✅ STEP 4: Execute the actual query
$stmt = $conn->prepare("
    SELECT * FROM learnerdetails 
    WHERE classID = ? 
    ORDER BY firstName, lastName
");

if (!$stmt) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'error' => 'Database error'
    ]);
    exit;
}

$stmt->bind_param("s", $classID);
$stmt->execute();
$result = $stmt->get_result();

// Fetch all learners
$learners = [];
while ($row = $result->fetch_assoc()) {
    $learners[] = $row;
}

$stmt->close();

// ✅ STEP 5: Log successful access (optional)
logAuthEvent($conn, 'api_access', $user_id, $user_role, null, "get_learners: classID=$classID");

// ✅ STEP 6: Return successful response
echo json_encode([
    'success' => true,
    'learners' => $learners,
    'count' => count($learners)
]);

$conn->close();
?>
