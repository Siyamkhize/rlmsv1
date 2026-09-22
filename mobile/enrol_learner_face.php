<?php
/**
 * Face Enrollment Endpoint (Multi-Camera Support)
 * 
 * Receives face embedding(s) from the mobile app and stores them for a learner.
 * Supports both single and multi-camera enrollment (front/back).
 * 
 * Expected POST payload (Single camera - backward compatible):
 * {
 *   "learner_id": 12345,
 *   "embedding": [0.123, -0.456, ...], // 192 floats from MobileFaceNet
 *   "quality_score": 0.85,
 *   "consent_given": true,
 *   "camera_facing": "back"  // optional, defaults to "back"
 * }
 * 
 * OR (Multi-camera - new format):
 * {
 *   "learner_id": 12345,
 *   "embeddings": [
 *     {
 *       "embedding": [0.123, -0.456, ...],
 *       "quality_score": 0.85,
 *       "camera_facing": "back"
 *     },
 *     {
 *       "embedding": [0.789, -0.321, ...],
 *       "quality_score": 0.82,
 *       "camera_facing": "front"
 *     }
 *   ],
 *   "consent_given": true
 * }
 */

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

// Handle preflight requests
if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    exit(0);
}

// Log errors server-side; never emit HTML warnings into JSON responses
error_reporting(E_ALL);
ini_set('display_errors', 0);
ini_set('log_errors', 1);

// Include database connection and face recognition config
require_once '../connection.php';
require_once 'face_recognition_config.php';

// Only accept POST requests
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode([
        'success' => false,
        'message' => 'Method not allowed. Use POST.'
    ]);
    exit;
}

try {
    // Get POST data
    $input = json_decode(file_get_contents('php://input'), true);
    
    if (json_last_error() !== JSON_ERROR_NONE) {
        throw new Exception('Invalid JSON input: ' . json_last_error_msg());
    }
    
    // Determine format: single embedding or multi-camera embeddings
    $isSingleFormat = isset($input['embedding']);
    $isMultiFormat = isset($input['embeddings']) && is_array($input['embeddings']);
    
    if (!isset($input['learner_id']) || (!$isSingleFormat && !$isMultiFormat)) {
        throw new Exception('Missing required fields: learner_id and (embedding OR embeddings) are required');
    }
    
    $learner_id = intval($input['learner_id']);
    $allow_reenroll = isset($input['allow_reenroll']) ? (bool)$input['allow_reenroll'] : false;
    
    // Convert single format to multi format for unified processing
    $embeddings_to_process = [];
    
    if ($isSingleFormat) {
        // Single camera format (backward compatible)
        $embeddings_to_process[] = [
            'embedding' => $input['embedding'],
            'quality_score' => isset($input['quality_score']) ? floatval($input['quality_score']) : null,
            'camera_facing' => isset($input['camera_facing']) ? strtolower(trim($input['camera_facing'])) : 'back',
            'consent_given' => isset($input['consent_given']) ? (bool)$input['consent_given'] : false
        ];
    } else {
        // Multi-camera format
        $consent_given = isset($input['consent_given']) ? (bool)$input['consent_given'] : false;
        
        foreach ($input['embeddings'] as $emb) {
            $embeddings_to_process[] = [
                'embedding' => $emb['embedding'] ?? null,
                'quality_score' => isset($emb['quality_score']) ? floatval($emb['quality_score']) : null,
                'camera_facing' => isset($emb['camera_facing']) ? strtolower(trim($emb['camera_facing'])) : 'back',
                'consent_given' => $consent_given  // Use global consent for all
            ];
        }
    }
    
    // Validate learner_id
    if ($learner_id <= 0) {
        throw new Exception('Invalid learner_id');
    }
    
    // Validate embeddings array
    if (empty($embeddings_to_process)) {
        throw new Exception('No embeddings provided');
    }
    
    // Check if learner exists
    $stmt = $conn->prepare("SELECT LearnerID FROM learnerdetails WHERE LearnerID = ?");
    $stmt->bind_param('i', $learner_id);
    $stmt->execute();
    $result = $stmt->get_result();
    
    if ($result->num_rows === 0) {
        throw new Exception('Learner not found: ' . $learner_id);
    }
    $stmt->close();
    
    // Process each embedding
    $enrolled_count = 0;
    $results = [];
    
    foreach ($embeddings_to_process as $emb_data) {
        $embedding = $emb_data['embedding'];
        $quality_score = $emb_data['quality_score'];
        $camera_facing = $emb_data['camera_facing'];
        $consent_given = $emb_data['consent_given'];
        
        // Validate camera_facing
        if (!in_array($camera_facing, ['front', 'back'])) {
            $results[] = [
                'camera' => $camera_facing,
                'success' => false,
                'message' => 'Invalid camera_facing: must be front or back'
            ];
            continue;
        }
        
        // Validate consent
        if (!$consent_given) {
            $results[] = [
                'camera' => $camera_facing,
                'success' => false,
                'message' => 'Learner consent is required for face enrollment'
            ];
            continue;
        }
        
        // Validate embedding
        $validated_embedding = validateEmbedding($embedding);
        if ($validated_embedding === false) {
            $results[] = [
                'camera' => $camera_facing,
                'success' => false,
                'message' => 'Invalid embedding: must be an array of ' . FACE_EMBEDDING_LENGTH . ' numeric values'
            ];
            continue;
        }
        
        // Validate quality score
        if ($quality_score !== null && $quality_score < MIN_ENROLLMENT_QUALITY) {
            $results[] = [
                'camera' => $camera_facing,
                'success' => false,
                'message' => 'Quality score too low: ' . $quality_score . ' (minimum: ' . MIN_ENROLLMENT_QUALITY . ')'
            ];
            continue;
        }
        
        // Convert embedding to JSON for storage
        $embedding_json = json_encode($validated_embedding);
        
        // Check if learner already has an active enrollment for this camera
        $stmt = $conn->prepare("SELECT id FROM learner_face WHERE learner_id = ? AND camera_facing = ? AND active = 1");
        if (!$stmt) {
            $results[] = [
                'camera' => $camera_facing,
                'success' => false,
                'message' => 'Failed to prepare enrollment check: ' . $conn->error
            ];
            continue;
        }
        $stmt->bind_param('is', $learner_id, $camera_facing);
        if (!$stmt->execute()) {
            $results[] = [
                'camera' => $camera_facing,
                'success' => false,
                'message' => 'Failed to check existing enrollment: ' . $stmt->error
            ];
            $stmt->close();
            continue;
        }
        $result = $stmt->get_result();
        
        if ($result->num_rows > 0) {
            $existing_row = $result->fetch_assoc();
            $existing_id = $existing_row['id'];
            $stmt->close();

            if (!$allow_reenroll) {
                $results[] = [
                    'camera' => $camera_facing,
                    'success' => false,
                    'message' => 'Learner already has an active face enrollment for ' . $camera_facing . ' camera. Use verification instead.'
                ];
                continue;
            }

            // Re-enrollment path (only used when allow_reenroll=true)
            $stmt = $conn->prepare("
                UPDATE learner_face 
                SET embedding_vector = ?, 
                    quality_score = ?, 
                    model_version = ?,
                    updated_at = CURRENT_TIMESTAMP
                WHERE id = ?
            ");
            if (!$stmt) {
                $results[] = [
                    'camera' => $camera_facing,
                    'success' => false,
                    'message' => 'Failed to prepare enrollment update: ' . $conn->error
                ];
                continue;
            }
            $model_version = FACE_MODEL_VERSION;
            $quality_val = $quality_score ?? 0.0;
            $stmt->bind_param('sdsi', $embedding_json, $quality_val, $model_version, $existing_id);
            if (!$stmt->execute()) {
                $results[] = [
                    'camera' => $camera_facing,
                    'success' => false,
                    'message' => 'Failed to update enrollment: ' . $stmt->error
                ];
                $stmt->close();
                continue;
            }

            if ($stmt->affected_rows > 0) {
                $results[] = [
                    'camera' => $camera_facing,
                    'success' => true,
                    'message' => 'Face re-enrolled successfully',
                    'enrollment_id' => $existing_id,
                    'action' => 'updated'
                ];
                $enrolled_count++;
            } else {
                $results[] = [
                    'camera' => $camera_facing,
                    'success' => false,
                    'message' => 'Failed to update enrollment'
                ];
            }
            $stmt->close();
        } else {
            // Insert new enrollment
            $stmt->close();

            $stmt = $conn->prepare("
                INSERT INTO learner_face 
                (learner_id, embedding_vector, camera_facing, quality_score, consent_given, model_version, active) 
                VALUES (?, ?, ?, ?, ?, ?, ?)
            ");
            if (!$stmt) {
                $results[] = [
                    'camera' => $camera_facing,
                    'success' => false,
                    'message' => 'Failed to prepare enrollment insert: ' . $conn->error
                ];
                continue;
            }
            $consent_int = $consent_given ? 1 : 0;
            $active_one = 1;
            $model_version = FACE_MODEL_VERSION;
            $quality_val = $quality_score ?? 0.0;
            $stmt->bind_param('issdisi', $learner_id, $embedding_json, $camera_facing, $quality_val, $consent_int, $model_version, $active_one);
            if (!$stmt->execute()) {
                $results[] = [
                    'camera' => $camera_facing,
                    'success' => false,
                    'message' => 'Failed to insert enrollment: ' . $stmt->error
                ];
                $stmt->close();
                continue;
            }

            if ($stmt->affected_rows > 0) {
                $enrollment_id = $conn->insert_id;

                // Log the enrollment as a test verification
                $log_similarity = 1.0;
                $log_threshold = FACE_MATCH_THRESHOLD;
                $log_passed = 1;
                $log_verification_type = 'enrollment_test';
                $log_quality = $quality_val;

                $log_stmt = $conn->prepare("
                    INSERT INTO learner_face_verification_log 
                    (learner_id, similarity_score, threshold_used, passed, verification_type, quality_score)
                    VALUES (?, ?, ?, ?, ?, ?)
                ");
                if ($log_stmt) {
                    $log_stmt->bind_param(
                        'iddisd',
                        $learner_id,
                        $log_similarity,
                        $log_threshold,
                        $log_passed,
                        $log_verification_type,
                        $log_quality
                    );
                    $log_stmt->execute();
                    $log_stmt->close();
                }

                $results[] = [
                    'camera' => $camera_facing,
                    'success' => true,
                    'message' => 'Face enrolled successfully',
                    'enrollment_id' => $enrollment_id,
                    'action' => 'created'
                ];
                $enrolled_count++;
            } else {
                $results[] = [
                    'camera' => $camera_facing,
                    'success' => false,
                    'message' => 'Failed to insert enrollment'
                ];
            }
            $stmt->close();
        }
    }
    
    // Return appropriate response
    if ($enrolled_count === 0) {
        throw new Exception('No embeddings were successfully enrolled');
    }
    
    $response = [
        'success' => true,
        'message' => $enrolled_count === 1 ? 'Face enrolled successfully' : "$enrolled_count faces enrolled successfully",
        'enrolled_count' => $enrolled_count,
        'results' => $results
    ];
    
    echo json_encode($response);
    
} catch (Exception $e) {
    http_response_code(400);
    echo json_encode([
        'success' => false,
        'message' => $e->getMessage(),
        'error' => true
    ]);
}
