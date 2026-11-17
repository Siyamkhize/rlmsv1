<?php
/**
 * Class Batch Clocking Endpoint - Processes entire class clocking in single request
 * 
 * Optimized for rural connectivity - reduces multiple individual requests to 1 batch
 * Uses same security and idempotency as individual clocking
 */
 
 // Set timezone to South Africa (SAST = UTC+2) - CRITICAL for date/time consistency
date_default_timezone_set('Africa/Johannesburg');

require_once('connection.php');
require_once('require_auth.php');
require_once('idempotency_helpers.php');

header('Content-Type: application/json');
header('X-Powered-By: RLMSS-Batch-Clocking/1.0');

// Validate request method
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['error' => 'Method not allowed', 'allowed' => 'POST']);
    exit;
}

// Get authenticated user
$user = requireAuth($conn);
$userId = $user['user_id'];

try {
    // Get JSON input
    $input = file_get_contents('php://input');
    $data = json_decode($input, true);
    
    if (!$data) {
        throw new Exception('Invalid JSON input');
    }
    
    // Validate required batch fields
    $requiredFields = ['batch_id', 'class_id', 'learner_clockings', 'total_learners'];
    foreach ($requiredFields as $field) {
        if (!isset($data[$field])) {
            throw new Exception("Missing required field: $field");
        }
    }
    
    $batchId = $data['batch_id'];
    $classId = $data['class_id'];
    $learnerClockings = $data['learner_clockings'];
    $totalLearners = $data['total_learners'];
    $clientTimestamp = $data['client_timestamp'] ?? date('c');
    
    // Validate learner clockings array
    if (!is_array($learnerClockings) || empty($learnerClockings)) {
        throw new Exception('learner_clockings must be non-empty array');
    }
    
    if (count($learnerClockings) !== $totalLearners) {
        throw new Exception('learner_clockings count does not match total_learners');
    }
    
    // Check batch idempotency
    $batchIdempotencyKey = $_SERVER['HTTP_X_BATCH_IDEMPOTENCY_KEY'] ?? $batchId;
    $existing = idem_begin($conn, $userId, 'class_batch_clocking', $batchIdempotencyKey);
    if ($existing) {
        // Return previous batch result
        http_response_code($existing['response_code'] ?? 200);
        echo $existing['response_body'];
        exit;
    }
    
    $results = [];
    $successCount = 0;
    $errorCount = 0;
    $errors = [];
    
    // Start transaction for batch processing
    $conn->begin_transaction();
    
    try {
        foreach ($learnerClockings as $index => $clocking) {
            try {
                // Validate individual clocking data
                $requiredClockingFields = ['learner_id', 'type', 'latitude', 'longitude'];
                foreach ($requiredClockingFields as $field) {
                    if (!isset($clocking[$field])) {
                        throw new Exception("Learner clocking $index missing field: $field");
                    }
                }
                
                $learnerId = $clocking['learner_id'];
                $clockType = $clocking['type']; // 'in' or 'out'
                $latitude = $clocking['latitude'];
                $longitude = $clocking['longitude'];
                $accuracy = $clocking['accuracy'] ?? null;
                $faceImage = $clocking['face_image'] ?? null;
                $signatureImage = $clocking['signature_image'] ?? null;
                $clockDate = $clocking['clock_date'] ?? date('Y-m-d');
                
                // Individual learner idempotency key
                $learnerIdempotencyKey = $clocking['idempotency_key'] ?? 
                    ($batchId . '_' . $learnerId . '_' . $clockType);
                
                // Check if this specific learner clocking already processed
                $learnerExisting = idem_begin($conn, $userId, 'learner_clocking', $learnerIdempotencyKey);
                if ($learnerExisting) {
                    $results[] = [
                        'learner_id' => $learnerId,
                        'status' => 'duplicate',
                        'message' => 'Already processed',
                        'idempotency_key' => $learnerIdempotencyKey
                    ];
                    $successCount++;
                    continue;
                }
                
                // Insert clocking record
                $stmt = $conn->prepare("
                    INSERT INTO manual_clocking 
                    (user_id, class_id, learner_id, clock_date, clock_time, type, 
                     latitude, longitude, accuracy, batch_id, client_timestamp, created_at) 
                    VALUES (?, ?, ?, ?, NOW(), ?, ?, ?, ?, ?, ?, NOW())
                ");
                
                $stmt->bind_param(
                    "issssddsss",
                    $userId, $classId, $learnerId, $clockDate, $clockType,
                    $latitude, $longitude, $accuracy, $batchId, $clientTimestamp
                );
                
                if (!$stmt->execute()) {
                    throw new Exception("Failed to insert clocking for learner $learnerId: " . $stmt->error);
                }
                
                $clockingId = $conn->insert_id;
                
                // Save evidence images if provided
                if ($faceImage || $signatureImage) {
                    try {
                        $evidenceResult = saveClockingEvidence($conn, $clockingId, $learnerId, [
                            'face_image' => $faceImage,
                            'signature_image' => $signatureImage,
                            'batch_id' => $batchId
                        ]);
                    } catch (Exception $e) {
                        // Evidence save failure shouldn't fail the clocking
                        error_log("Evidence save failed for learner $learnerId: " . $e->getMessage());
                    }
                }
                
                // Mark learner clocking as complete
                idem_finish($conn, $userId, $learnerIdempotencyKey, 200, json_encode([
                    'success' => true,
                    'clocking_id' => $clockingId,
                    'learner_id' => $learnerId
                ]));
                
                $results[] = [
                    'learner_id' => $learnerId,
                    'status' => 'success',
                    'clocking_id' => $clockingId,
                    'type' => $clockType,
                    'timestamp' => date('c'),
                    'idempotency_key' => $learnerIdempotencyKey
                ];
                
                $successCount++;
                
            } catch (Exception $e) {
                $errorCount++;
                $error = [
                    'learner_id' => $clocking['learner_id'] ?? "unknown_$index",
                    'status' => 'error',
                    'error' => $e->getMessage(),
                    'index' => $index
                ];
                $results[] = $error;
                $errors[] = $error;
                
                error_log("Batch clocking error for learner {$clocking['learner_id']}: " . $e->getMessage());
            }
        }
        
        // Commit transaction if we have at least some successes
        if ($successCount > 0) {
            $conn->commit();
            
            // Mark batch as complete
            $batchResult = [
                'success' => true,
                'batch_id' => $batchId,
                'class_id' => $classId,
                'total_learners' => $totalLearners,
                'successful_clockings' => $successCount,
                'failed_clockings' => $errorCount,
                'results' => $results,
                'processed_at' => date('c'),
                'has_errors' => $errorCount > 0
            ];
            
            if ($errorCount > 0) {
                $batchResult['errors'] = $errors;
            }
            
            // Store batch result in idempotency system
            idem_finish($conn, $userId, $batchIdempotencyKey, 200, json_encode($batchResult));
            
            http_response_code(200);
            echo json_encode($batchResult);
            
        } else {
            // All clockings failed
            $conn->rollback();
            
            $batchError = [
                'success' => false,
                'batch_id' => $batchId,
                'error' => 'All learner clockings failed',
                'total_learners' => $totalLearners,
                'failed_clockings' => $errorCount,
                'results' => $results,
                'errors' => $errors
            ];
            
            idem_finish($conn, $userId, $batchIdempotencyKey, 400, json_encode($batchError));
            
            http_response_code(400);
            echo json_encode($batchError);
        }
        
    } catch (Exception $e) {
        $conn->rollback();
        throw $e;
    }
    
} catch (Exception $e) {
    error_log("Batch clocking error: " . $e->getMessage());
    
    // Store error in idempotency system if we have keys and user ID
    if (isset($batchIdempotencyKey) && isset($userId)) {
        idem_abort($conn, $userId, $batchIdempotencyKey, $e->getMessage());
    }
    
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'error' => $e->getMessage(),
        'batch_id' => $batchId ?? null
    ]);
}

/**
 * Save clocking evidence images
 */
function saveClockingEvidence($conn, $clockingId, $learnerId, $evidence) {
    if (empty($evidence['face_image']) && empty($evidence['signature_image'])) {
        return true;
    }
    
    $batchId = $evidence['batch_id'] ?? null;
    $evidenceDir = __DIR__ . '/clocking_evidence/';
    
    if (!is_dir($evidenceDir)) {
        mkdir($evidenceDir, 0755, true);
    }
    
    $savedFiles = [];
    
    try {
        // Save face image
        if (!empty($evidence['face_image'])) {
            $faceFilename = "face_{$clockingId}_{$learnerId}_" . date('Ymd_His') . '.jpg';
            $facePath = $evidenceDir . $faceFilename;
            
            $faceData = base64_decode($evidence['face_image']);
            if ($faceData && file_put_contents($facePath, $faceData)) {
                $savedFiles[] = $faceFilename;
            }
        }
        
        // Save signature image
        if (!empty($evidence['signature_image'])) {
            $sigFilename = "signature_{$clockingId}_{$learnerId}_" . date('Ymd_His') . '.png';
            $sigPath = $evidenceDir . $sigFilename;
            
            $sigData = base64_decode($evidence['signature_image']);
            if ($sigData && file_put_contents($sigPath, $sigData)) {
                $savedFiles[] = $sigFilename;
            }
        }
        
        // Store evidence record in database
        if (!empty($savedFiles)) {
            $stmt = $conn->prepare("
                INSERT INTO learner_clocking_evidence 
                (clocking_id, learner_id, face_filename, signature_filename, batch_id, created_at) 
                VALUES (?, ?, ?, ?, ?, NOW())
            ");
            
            $faceFile = isset($savedFiles[0]) && strpos($savedFiles[0], 'face_') === 0 ? $savedFiles[0] : null;
            $sigFile = isset($savedFiles[1]) && strpos($savedFiles[1], 'signature_') === 0 ? $savedFiles[1] : 
                      (isset($savedFiles[0]) && strpos($savedFiles[0], 'signature_') === 0 ? $savedFiles[0] : null);
            
            $stmt->bind_param("issss", $clockingId, $learnerId, $faceFile, $sigFile, $batchId);
            $stmt->execute();
        }
        
        return true;
        
    } catch (Exception $e) {
        error_log("Evidence save error: " . $e->getMessage());
        
        // Clean up any partial files
        foreach ($savedFiles as $filename) {
            $filepath = $evidenceDir . $filename;
            if (file_exists($filepath)) {
                unlink($filepath);
            }
        }
        
        throw $e;
    }
}
?>