<?php
/**
 * Sync Clocking Evidence API
 * 
 * Syncs clock-in/out evidence (signatures, photos, GPS) from phone to server
 * 
 * POST payload:
 * {
 *   "evidence": [
 *     {
 *       "learner_id": 11443,
 *       "clock_date": "2026-09-21",
 *       "clock_in_signature": "base64...",
 *       "clock_in_photo": "base64...",
 *       "clock_in_latitude": -26.123456,
 *       "clock_in_longitude": 27.123456,
 *       "clock_in_accuracy": 15.5,
 *       "clock_in_verification_method": "face",
 *       "clock_in_face_log_id": 123,
 *       "clock_in_timestamp": "2026-09-21 08:30:00",
 *       "clock_out_signature": "base64...",
 *       "clock_out_latitude": -26.123456,
 *       "clock_out_longitude": 27.123456,
 *       "clock_out_accuracy": 12.3,
 *       "clock_out_verification_method": "signature",
 *       "clock_out_timestamp": "2026-09-21 16:30:00"
 *     }
 *   ]
 * }
 */

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

// Handle preflight
if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    exit(0);
}

// Logging
error_reporting(E_ALL);
ini_set('display_errors', 0);
ini_set('log_errors', 1);

require_once '../connection.php';

// Only accept POST
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Method not allowed']);
    exit;
}

try {
    // Get input
    $input = json_decode(file_get_contents('php://input'), true);
    
    if (json_last_error() !== JSON_ERROR_NONE) {
        throw new Exception('Invalid JSON: ' . json_last_error_msg());
    }
    
    if (!isset($input['evidence']) || !is_array($input['evidence'])) {
        throw new Exception('Missing or invalid evidence array');
    }
    
    $evidence_list = $input['evidence'];
    $synced_count = 0;
    $error_count = 0;
    $errors = [];
    
    foreach ($evidence_list as $evidence) {
        try {
            // Validate required fields
            if (!isset($evidence['learner_id']) || !isset($evidence['clock_date'])) {
                throw new Exception('Missing learner_id or clock_date');
            }
            
            $learner_id = intval($evidence['learner_id']);
            $clock_date = $evidence['clock_date'];
            
            // Check if record exists
            $check_stmt = $conn->prepare("
                SELECT id FROM learner_clocking_evidence 
                WHERE LearnerID = ? AND clock_date = ?
            ");
            $check_stmt->bind_param('is', $learner_id, $clock_date);
            $check_stmt->execute();
            $check_result = $check_stmt->get_result();
            
            if ($check_result->num_rows > 0) {
                // UPDATE existing record
                $existing = $check_result->fetch_assoc();
                $record_id = $existing['id'];
                $check_stmt->close();
                
                // Build dynamic UPDATE query
                $update_fields = [];
                $update_values = [];
                $update_types = '';
                
                // Clock-in fields
                if (isset($evidence['clock_in_signature']) && $evidence['clock_in_signature']) {
                    $update_fields[] = 'clock_in_signature = ?';
                    $update_values[] = $evidence['clock_in_signature'];
                    $update_types .= 's';
                }
                if (isset($evidence['clock_in_photo']) && $evidence['clock_in_photo']) {
                    $update_fields[] = 'clock_in_photo = ?';
                    $update_values[] = $evidence['clock_in_photo'];
                    $update_types .= 's';
                }
                if (isset($evidence['clock_in_latitude'])) {
                    $update_fields[] = 'clock_in_latitude = ?';
                    $update_values[] = $evidence['clock_in_latitude'];
                    $update_types .= 'd';
                }
                if (isset($evidence['clock_in_longitude'])) {
                    $update_fields[] = 'clock_in_longitude = ?';
                    $update_values[] = $evidence['clock_in_longitude'];
                    $update_types .= 'd';
                }
                if (isset($evidence['clock_in_accuracy'])) {
                    $update_fields[] = 'clock_in_accuracy = ?';
                    $update_values[] = $evidence['clock_in_accuracy'];
                    $update_types .= 'd';
                }
                if (isset($evidence['clock_in_verification_method'])) {
                    $update_fields[] = 'clock_in_verification_method = ?';
                    $update_values[] = $evidence['clock_in_verification_method'];
                    $update_types .= 's';
                }
                if (isset($evidence['clock_in_face_log_id'])) {
                    $update_fields[] = 'clock_in_face_log_id = ?';
                    $update_values[] = $evidence['clock_in_face_log_id'];
                    $update_types .= 'i';
                }
                if (isset($evidence['clock_in_timestamp'])) {
                    $update_fields[] = 'clock_in_timestamp = ?';
                    $update_values[] = $evidence['clock_in_timestamp'];
                    $update_types .= 's';
                }
                
                // Clock-out fields
                if (isset($evidence['clock_out_signature']) && $evidence['clock_out_signature']) {
                    $update_fields[] = 'clock_out_signature = ?';
                    $update_values[] = $evidence['clock_out_signature'];
                    $update_types .= 's';
                }
                if (isset($evidence['clock_out_photo']) && $evidence['clock_out_photo']) {
                    $update_fields[] = 'clock_out_photo = ?';
                    $update_values[] = $evidence['clock_out_photo'];
                    $update_types .= 's';
                }
                if (isset($evidence['clock_out_latitude'])) {
                    $update_fields[] = 'clock_out_latitude = ?';
                    $update_values[] = $evidence['clock_out_latitude'];
                    $update_types .= 'd';
                }
                if (isset($evidence['clock_out_longitude'])) {
                    $update_fields[] = 'clock_out_longitude = ?';
                    $update_values[] = $evidence['clock_out_longitude'];
                    $update_types .= 'd';
                }
                if (isset($evidence['clock_out_accuracy'])) {
                    $update_fields[] = 'clock_out_accuracy = ?';
                    $update_values[] = $evidence['clock_out_accuracy'];
                    $update_types .= 'd';
                }
                if (isset($evidence['clock_out_verification_method'])) {
                    $update_fields[] = 'clock_out_verification_method = ?';
                    $update_values[] = $evidence['clock_out_verification_method'];
                    $update_types .= 's';
                }
                if (isset($evidence['clock_out_face_log_id'])) {
                    $update_fields[] = 'clock_out_face_log_id = ?';
                    $update_values[] = $evidence['clock_out_face_log_id'];
                    $update_types .= 'i';
                }
                if (isset($evidence['clock_out_timestamp'])) {
                    $update_fields[] = 'clock_out_timestamp = ?';
                    $update_values[] = $evidence['clock_out_timestamp'];
                    $update_types .= 's';
                }
                
                if (empty($update_fields)) {
                    // Nothing to update
                    continue;
                }
                
                // Add record_id to values
                $update_values[] = $record_id;
                $update_types .= 'i';
                
                $update_sql = "UPDATE learner_clocking_evidence SET " . 
                             implode(', ', $update_fields) . 
                             ", updated_at = NOW() WHERE id = ?";
                
                $update_stmt = $conn->prepare($update_sql);
                $update_stmt->bind_param($update_types, ...$update_values);
                $update_stmt->execute();
                $update_stmt->close();
                
                $synced_count++;
                
            } else {
                // INSERT new record
                $check_stmt->close();
                
                $insert_stmt = $conn->prepare("
                    INSERT INTO learner_clocking_evidence (
                        LearnerID,
                        clock_date,
                        clock_in_signature,
                        clock_in_photo,
                        clock_in_latitude,
                        clock_in_longitude,
                        clock_in_accuracy,
                        clock_in_verification_method,
                        clock_in_face_log_id,
                        clock_in_timestamp,
                        clock_out_signature,
                        clock_out_photo,
                        clock_out_latitude,
                        clock_out_longitude,
                        clock_out_accuracy,
                        clock_out_verification_method,
                        clock_out_face_log_id,
                        clock_out_timestamp
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ");
                
                $clock_in_sig = $evidence['clock_in_signature'] ?? null;
                $clock_in_photo = $evidence['clock_in_photo'] ?? null;
                $clock_in_lat = $evidence['clock_in_latitude'] ?? null;
                $clock_in_lng = $evidence['clock_in_longitude'] ?? null;
                $clock_in_acc = $evidence['clock_in_accuracy'] ?? null;
                $clock_in_method = $evidence['clock_in_verification_method'] ?? null;
                $clock_in_log_id = $evidence['clock_in_face_log_id'] ?? null;
                $clock_in_ts = $evidence['clock_in_timestamp'] ?? null;
                
                $clock_out_sig = $evidence['clock_out_signature'] ?? null;
                $clock_out_photo = $evidence['clock_out_photo'] ?? null;
                $clock_out_lat = $evidence['clock_out_latitude'] ?? null;
                $clock_out_lng = $evidence['clock_out_longitude'] ?? null;
                $clock_out_acc = $evidence['clock_out_accuracy'] ?? null;
                $clock_out_method = $evidence['clock_out_verification_method'] ?? null;
                $clock_out_log_id = $evidence['clock_out_face_log_id'] ?? null;
                $clock_out_ts = $evidence['clock_out_timestamp'] ?? null;
                
                $insert_stmt->bind_param(
                    'isssdddsississddsisi',
                    $learner_id,
                    $clock_date,
                    $clock_in_sig,
                    $clock_in_photo,
                    $clock_in_lat,
                    $clock_in_lng,
                    $clock_in_acc,
                    $clock_in_method,
                    $clock_in_log_id,
                    $clock_in_ts,
                    $clock_out_sig,
                    $clock_out_photo,
                    $clock_out_lat,
                    $clock_out_lng,
                    $clock_out_acc,
                    $clock_out_method,
                    $clock_out_log_id,
                    $clock_out_ts
                );
                
                $insert_stmt->execute();
                $insert_stmt->close();
                
                $synced_count++;
            }
            
        } catch (Exception $e) {
            $error_count++;
            $errors[] = [
                'learner_id' => $evidence['learner_id'] ?? 'unknown',
                'clock_date' => $evidence['clock_date'] ?? 'unknown',
                'error' => $e->getMessage()
            ];
        }
    }
    
    echo json_encode([
        'success' => true,
        'synced' => $synced_count,
        'errors' => $error_count,
        'error_details' => $errors,
        'message' => "Synced $synced_count evidence records" . 
                    ($error_count > 0 ? " ($error_count errors)" : "")
    ]);
    
} catch (Exception $e) {
    http_response_code(400);
    echo json_encode([
        'success' => false,
        'message' => $e->getMessage()
    ]);
}
