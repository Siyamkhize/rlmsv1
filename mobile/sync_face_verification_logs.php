<?php
/**
 * Sync Face Verification Logs from Device to Server
 * 
 * Receives offline face verification logs from mobile devices
 * and inserts them into learner_face_verification_log table
 */

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST');
header('Access-Control-Allow-Headers: Content-Type');

// Database connection
require_once '../connection.php';

// Only allow POST requests
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode([
        'success' => false,
        'message' => 'Method not allowed'
    ]);
    exit;
}

// Get JSON input
$input = file_get_contents('php://input');
$data = json_decode($input, true);

if (!$data || !isset($data['logs']) || !is_array($data['logs'])) {
    http_response_code(400);
    echo json_encode([
        'success' => false,
        'message' => 'Invalid input: logs array required'
    ]);
    exit;
}

$logs = $data['logs'];
$syncedCount = 0;
$failedCount = 0;
$syncedIds = []; // Track which logs were successfully synced
$errors = [];

try {
    // Process each log
    foreach ($logs as $index => $log) {
        try {
            // Validate required fields
            $requiredFields = ['learner_id', 'embedding', 'match_score', 'verified', 
                               'quality_score', 'verification_type', 'attempted_at'];
            
            foreach ($requiredFields as $field) {
                if (!isset($log[$field])) {
                    throw new Exception("Missing required field: $field");
                }
            }

            // Decode embedding if it's a JSON string
            $embedding = is_string($log['embedding']) 
                ? $log['embedding'] 
                : json_encode($log['embedding']);

            // Get camera_facing (default to 'back' for backward compatibility)
            $cameraFacing = $log['camera_facing'] ?? 'back';

            // Insert into learner_face_verification_log
            $stmt = $conn->prepare("
                INSERT INTO learner_face_verification_log (
                    learner_id,
                    embedding,
                    match_score,
                    verified,
                    quality_score,
                    liveness_passed,
                    verification_type,
                    camera_facing,
                    failure_reason,
                    device_info,
                    attempted_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ");

            if (!$stmt) {
                throw new Exception("Prepare failed: " . $conn->error);
            }

            $verified = (int)$log['verified'];
            $livenessPassed = isset($log['liveness_passed']) ? (int)$log['liveness_passed'] : 1;
            $failureReason = $log['failure_reason'] ?? null;
            $deviceInfo = $log['device_info'] ?? 'offline_sync';
            
            $stmt->bind_param(
                "isddisssss",
                $log['learner_id'],
                $embedding,
                $log['match_score'],
                $verified,
                $log['quality_score'],
                $livenessPassed,
                $log['verification_type'],
                $cameraFacing,
                $failureReason,
                $deviceInfo,
                $log['attempted_at']
            );

            if ($stmt->execute()) {
                $syncedCount++;
                // Add the client-side log ID to synced list
                if (isset($log['id'])) {
                    $syncedIds[] = $log['id'];
                }
            } else {
                $failedCount++;
                $errors[] = "Log $index: " . $stmt->error;
            }

            $stmt->close();

        } catch (Exception $e) {
            $failedCount++;
            $errors[] = "Log $index: " . $e->getMessage();
        }
    }

    // Return results with synced_ids array for client confirmation
    echo json_encode([
        'success' => true,
        'synced_count' => $syncedCount,
        'synced_ids' => $syncedIds, // Client uses this to mark logs as synced
        'failed_count' => $failedCount,
        'total_received' => count($logs),
        'errors' => $errors
    ]);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Server error: ' . $e->getMessage(),
        'synced_count' => $syncedCount,
        'failed_count' => $failedCount
    ]);
}

$conn->close();
?>
