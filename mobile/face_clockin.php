<?php
// face_clockin.php
// Facial-recognition clock-in for facilitators.
// Mirrors facilitator_clockin.php but also records the clock-out path.
// Geofencing is enforced the same way as fingerprint clocking — the app calls
// verify_geofence.php before calling this endpoint; we simply log GPS coords.
//
// POST JSON body:
//   facilitator_id  int     required
//   action          string  'in' | 'out'
//   clock_date      string  YYYY-MM-DD  required
//   clock_time      string  HH:MM:SS    required
//   user_latitude   float   optional
//   user_longitude  float   optional
//   user_accuracy   float   optional

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Method not allowed']);
    exit;
}

require_once 'connection.php';

$raw   = file_get_contents('php://input');
$data  = json_decode($raw, true);

if (!$data) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Invalid JSON']);
    exit;
}

$facilitatorId = isset($data['facilitator_id']) ? intval($data['facilitator_id']) : 0;
$action        = $data['action']       ?? 'in';
$clockDate     = $data['clock_date']   ?? '';
$clockTime     = $data['clock_time']   ?? '';
$lat           = $data['user_latitude']  ?? '0.0';
$lng           = $data['user_longitude'] ?? '0.0';
$accuracy      = $data['user_accuracy']  ?? '10.0';

if ($facilitatorId <= 0 || empty($clockDate) || empty($clockTime)) {
    http_response_code(400);
    echo json_encode([
        'success' => false,
        'message' => 'Missing required fields: facilitator_id, clock_date, clock_time',
    ]);
    exit;
}

// Verify facilitator
$stmt = $conn->prepare(
    "SELECT facilitator_id, firstName, lastName FROM facilitator WHERE facilitator_id = ?"
);
$stmt->bind_param('i', $facilitatorId);
$stmt->execute();
$res = $stmt->get_result();
if ($res->num_rows === 0) {
    http_response_code(404);
    echo json_encode(['success' => false, 'message' => 'Facilitator not found']);
    $stmt->close(); $conn->close(); exit;
}
$facilitator = $res->fetch_assoc();
$stmt->close();
$fullName = trim($facilitator['firstName'] . ' ' . $facilitator['lastName']);

// Check existing record for this date
$checkStmt = $conn->prepare(
    "SELECT clocking_id, clock_in_time FROM facilitator_clocking
     WHERE facilitator_id = ? AND clock_date = ?"
);
$checkStmt->bind_param('is', $facilitatorId, $clockDate);
$checkStmt->execute();
$existing = $checkStmt->get_result()->fetch_assoc();
$checkStmt->close();

if ($action === 'in') {
    if ($existing) {
        // Update clock-in
        $upd = $conn->prepare(
            "UPDATE facilitator_clocking
             SET clock_in_time = ?, user_latitude = ?, user_longitude = ?, user_accuracy = ?
             WHERE clocking_id = ?"
        );
        $upd->bind_param('ssssi', $clockTime, $lat, $lng, $accuracy, $existing['clocking_id']);
        $ok = $upd->execute();
        $upd->close();
    } else {
        // Insert new record
        $ins = $conn->prepare(
            "INSERT INTO facilitator_clocking
             (facilitator_id, clock_date, clock_in_time, user_latitude, user_longitude, user_accuracy)
             VALUES (?, ?, ?, ?, ?, ?)"
        );
        $ins->bind_param('isssss', $facilitatorId, $clockDate, $clockTime, $lat, $lng, $accuracy);
        $ok = $ins->execute();
        $ins->close();
    }

    error_log("[FACE_CLOCK] Clock-IN for facilitator $facilitatorId on $clockDate at $clockTime");
    echo json_encode([
        'success'          => (bool)$ok,
        'message'          => $ok ? 'Clocked in successfully' : 'Clock-in failed: ' . $conn->error,
        'action'           => 'in',
        'facilitator_name' => $fullName,
        'clock_time'       => $clockTime,
    ]);

} else {
    // Clock OUT
    if (!$existing) {
        http_response_code(400);
        echo json_encode(['success' => false, 'message' => 'No clock-in record found for today']);
        $conn->close(); exit;
    }

    // Calculate contact time
    $contactTime = '';
    if (!empty($existing['clock_in_time'])) {
        try {
            $inDt  = new DateTime($clockDate . ' ' . $existing['clock_in_time']);
            $outDt = new DateTime($clockDate . ' ' . $clockTime);
            $diff  = $inDt->diff($outDt);
            $contactTime = sprintf('%02d:%02d:%02d',
                $diff->h + ($diff->days * 24), $diff->i, $diff->s);
        } catch (Exception $e) {
            $contactTime = '00:00:00';
        }
    }

    $upd = $conn->prepare(
        "UPDATE facilitator_clocking
         SET clock_out_time = ?, contact_time = ?,
             user_latitude = ?, user_longitude = ?, user_accuracy = ?
         WHERE clocking_id = ?"
    );
    $upd->bind_param('sssssi', $clockTime, $contactTime, $lat, $lng, $accuracy,
        $existing['clocking_id']);
    $ok = $upd->execute();
    $upd->close();

    error_log("[FACE_CLOCK] Clock-OUT for facilitator $facilitatorId on $clockDate at $clockTime, contact=$contactTime");
    echo json_encode([
        'success'          => (bool)$ok,
        'message'          => $ok ? 'Clocked out successfully' : 'Clock-out failed: ' . $conn->error,
        'action'           => 'out',
        'facilitator_name' => $fullName,
        'clock_time'       => $clockTime,
        'contact_time'     => $contactTime,
    ]);
}

$conn->close();
?>
