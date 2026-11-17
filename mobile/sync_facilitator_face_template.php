<?php
// sync_facilitator_face_template.php
// Saves/updates a MobileFaceNet embedding for a facilitator in the facilitator_faces table.

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

$facilitatorId = isset($input['facilitator_id']) ? intval($input['facilitator_id']) : 0;
$faceTemplate  = $input['face_template'] ?? '';

if ($facilitatorId <= 0) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Invalid facilitator_id']);
    exit;
}
if (empty(trim($faceTemplate)) || strlen($faceTemplate) < 10) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'face_template is empty or too short']);
    exit;
}

// Verify facilitator exists
$check = $conn->prepare("SELECT facilitator_id FROM facilitator WHERE facilitator_id = ?");
$check->bind_param('i', $facilitatorId);
$check->execute();
if ($check->get_result()->num_rows === 0) {
    http_response_code(404);
    echo json_encode(['success' => false, 'message' => 'Facilitator not found']);
    $check->close(); $conn->close(); exit;
}
$check->close();

// Upsert into facilitator_faces
$stmt = $conn->prepare("
    INSERT INTO facilitator_faces (facilitator_id, face_template, enrolled_at, updated_at)
    VALUES (?, ?, NOW(), NOW())
    ON DUPLICATE KEY UPDATE face_template = VALUES(face_template), updated_at = NOW()
");
$stmt->bind_param('is', $facilitatorId, $faceTemplate);

if ($stmt->execute()) {
    error_log("[FACE] facilitator_faces upsert OK for facilitator_id=$facilitatorId (".strlen($faceTemplate)." chars)");
    echo json_encode([
        'success'        => true,
        'message'        => 'Face template saved successfully',
        'facilitator_id' => $facilitatorId,
    ]);
} else {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'DB error: ' . $stmt->error]);
}

$stmt->close();
$conn->close();
?>
