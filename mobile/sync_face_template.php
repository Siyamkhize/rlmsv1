<?php
// sync_face_template.php
// Saves/updates a MobileFaceNet embedding for a learner in the learner_faces table.
// Uses INSERT ... ON DUPLICATE KEY UPDATE so re-enrollment always overwrites.

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Method not allowed']);
    exit;
}

require_once 'connection.php';

$raw   = file_get_contents('php://input');
$input = json_decode($raw, true);
if (!$input) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Invalid JSON']);
    exit;
}

$learnerId    = isset($input['learner_id'])    ? intval($input['learner_id'])    : 0;
$faceTemplate = $input['face_template'] ?? '';

if ($learnerId <= 0) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Invalid learner_id']);
    exit;
}
if (empty(trim($faceTemplate)) || strlen($faceTemplate) < 10) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'face_template is empty or too short']);
    exit;
}

// Verify learner exists
$check = $conn->prepare("SELECT LearnerID FROM learnerdetails WHERE LearnerID = ?");
$check->bind_param('i', $learnerId);
$check->execute();
if ($check->get_result()->num_rows === 0) {
    http_response_code(404);
    echo json_encode(['success' => false, 'message' => 'Learner not found']);
    $check->close(); $conn->close(); exit;
}
$check->close();

// Upsert into learner_faces
$stmt = $conn->prepare("
    INSERT INTO learner_faces (LearnerID, face_template, enrolled_at, updated_at)
    VALUES (?, ?, NOW(), NOW())
    ON DUPLICATE KEY UPDATE face_template = VALUES(face_template), updated_at = NOW()
");
$stmt->bind_param('is', $learnerId, $faceTemplate);

if ($stmt->execute()) {
    error_log("[FACE] learner_faces upsert OK for LearnerID=$learnerId (".strlen($faceTemplate)." chars)");
    echo json_encode([
        'success'    => true,
        'message'    => 'Face template saved successfully',
        'learner_id' => $learnerId,
    ]);
} else {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'DB error: ' . $stmt->error]);
}

$stmt->close();
$conn->close();
?>
