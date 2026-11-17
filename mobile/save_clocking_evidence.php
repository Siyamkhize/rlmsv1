<?php
/**
 * Save Clocking Evidence API (Online Direct Save)
 * 
 * Saves clock-in/out evidence (filenames, GPS) directly to MySQL when online
 * This is separate from clockin.php and clockout.php
 * 
 * POST payload:
 * {
 *   "learner_id": 11443,
 *   "clock_date": "2026-09-21",
 *   "event_type": "clock_in" or "clock_out",
 *   "signature_filename": "learner11443_in_1726995123.png",
 *   "photo_filename": "learner11443_face_1726995123.jpg",
 *   "latitude": -26.123456,
 *   "longitude": 27.123456,
 *   "accuracy": 15.5,
 *   "verification_method": "face",
 *   "face_log_id": 123
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


// Set timezone to South Africa (SAST - UTC+2)
date_default_timezone_set('Africa/Johannesburg');

// Logging
error_reporting(E_ALL);
ini_set('display_errors', 0);
ini_set('log_errors', 1);
ini_set('log_errors_max_len', 0);

// CUSTOM LOG FILE for evidence tracking
$log_file = __DIR__ . '/../logs/evidence_save.log';
$log_dir = dirname($log_file);
if (!file_exists($log_dir)) {
    @mkdir($log_dir, 0755, true);
}

function write_evidence_log($message) {
    global $log_file;
    $timestamp = date('Y-m-d H:i:s');
    $log_message = "[$timestamp] $message\n";
    @file_put_contents($log_file, $log_message, FILE_APPEND);
    error_log($message); // Also write to PHP error log
}

write_evidence_log("========== NEW REQUEST ==========");
write_evidence_log("Request Method: " . $_SERVER['REQUEST_METHOD']);
write_evidence_log("Request URI: " . $_SERVER['REQUEST_URI']);
write_evidence_log("Remote Address: " . ($_SERVER['REMOTE_ADDR'] ?? 'unknown'));

require_once __DIR__ . '/../connection.php';

// Only accept POST
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    write_evidence_log("ERROR: Method not allowed - " . $_SERVER['REQUEST_METHOD']);
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Method not allowed']);
    exit;
}

try {
    // Get raw input
    $raw_input = file_get_contents('php://input');
    write_evidence_log("Raw input length: " . strlen($raw_input) . " bytes");
    write_evidence_log("Raw input: " . substr($raw_input, 0, 500)); // Log first 500 chars
    
    // Get input
    $input = json_decode($raw_input, true);
    
    if (json_last_error() !== JSON_ERROR_NONE) {
        write_evidence_log("ERROR: Invalid JSON - " . json_last_error_msg());
        throw new Exception('Invalid JSON: ' . json_last_error_msg());
    }
    
    write_evidence_log("JSON decoded successfully");
    write_evidence_log("Input keys: " . implode(', ', array_keys($input)));
    
    // Validate required fields
    if (!isset($input['learner_id']) || !isset($input['clock_date']) || !isset($input['event_type'])) {
        $missing = [];
        if (!isset($input['learner_id'])) $missing[] = 'learner_id';
        if (!isset($input['clock_date'])) $missing[] = 'clock_date';
        if (!isset($input['event_type'])) $missing[] = 'event_type';
        write_evidence_log("ERROR: Missing required fields - " . implode(', ', $missing));
        throw new Exception('Missing required fields: ' . implode(', ', $missing));
    }
    
    $learner_id = intval($input['learner_id']);
    $clock_date = $input['clock_date'];
    $event_type = $input['event_type']; // 'clock_in' or 'clock_out'
    
    write_evidence_log("Learner ID: $learner_id");
    write_evidence_log("Clock Date: $clock_date");
    write_evidence_log("Event Type: $event_type");
    
    if (!in_array($event_type, ['clock_in', 'clock_out'])) {
        write_evidence_log("ERROR: Invalid event_type - $event_type");
        throw new Exception('Invalid event_type. Must be "clock_in" or "clock_out"');
    }
    
    // Extract evidence data
    $signature_filename = $input['signature_filename'] ?? null;
    $photo_filename = $input['photo_filename'] ?? null;
    $latitude = isset($input['latitude']) ? floatval($input['latitude']) : null;
    $longitude = isset($input['longitude']) ? floatval($input['longitude']) : null;
    $accuracy = isset($input['accuracy']) ? floatval($input['accuracy']) : null;
    $verification_method = $input['verification_method'] ?? null;
    $face_log_id = isset($input['face_log_id']) ? intval($input['face_log_id']) : null;
    
    $timestamp = date('Y-m-d H:i:s');
    
    write_evidence_log("Signature filename: " . ($signature_filename ?? 'NULL'));
    write_evidence_log("Photo filename: " . ($photo_filename ?? 'NULL'));
    write_evidence_log("GPS: lat=$latitude, lng=$longitude, acc=$accuracy");
    write_evidence_log("Verification method: " . ($verification_method ?? 'NULL'));
    write_evidence_log("Face log ID: " . ($face_log_id ?? 'NULL'));
    write_evidence_log("Timestamp: $timestamp");
    
    // Check if record exists
    write_evidence_log("Checking if record exists for learner $learner_id on $clock_date");
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
        
        write_evidence_log("Record EXISTS - ID: $record_id - will UPDATE");
        
        // Build dynamic UPDATE query based on event_type - USING DIRECT SQL (bind_param crashes)
        if ($event_type === 'clock_in') {
            $update_fields = [];
            
            if ($signature_filename !== null) {
                $update_fields[] = "clock_in_signature = '" . $conn->real_escape_string($signature_filename) . "'";
            }
            if ($photo_filename !== null) {
                $update_fields[] = "clock_in_photo = '" . $conn->real_escape_string($photo_filename) . "'";
            }
            if ($latitude !== null) {
                $update_fields[] = "clock_in_latitude = " . floatval($latitude);
            }
            if ($longitude !== null) {
                $update_fields[] = "clock_in_longitude = " . floatval($longitude);
            }
            if ($accuracy !== null) {
                $update_fields[] = "clock_in_accuracy = " . floatval($accuracy);
            }
            if ($verification_method !== null) {
                $update_fields[] = "clock_in_verification_method = '" . $conn->real_escape_string($verification_method) . "'";
            }
            if ($face_log_id !== null) {
                $update_fields[] = "clock_in_face_log_id = " . intval($face_log_id);
            }
            $update_fields[] = "clock_in_timestamp = '" . $conn->real_escape_string($timestamp) . "'";
            
        } else { // clock_out
            $update_fields = [];
            
            if ($signature_filename !== null) {
                $update_fields[] = "clock_out_signature = '" . $conn->real_escape_string($signature_filename) . "'";
            }
            if ($photo_filename !== null) {
                $update_fields[] = "clock_out_photo = '" . $conn->real_escape_string($photo_filename) . "'";
            }
            if ($latitude !== null) {
                $update_fields[] = "clock_out_latitude = " . floatval($latitude);
            }
            if ($longitude !== null) {
                $update_fields[] = "clock_out_longitude = " . floatval($longitude);
            }
            if ($accuracy !== null) {
                $update_fields[] = "clock_out_accuracy = " . floatval($accuracy);
            }
            if ($verification_method !== null) {
                $update_fields[] = "clock_out_verification_method = '" . $conn->real_escape_string($verification_method) . "'";
            }
            if ($face_log_id !== null) {
                $update_fields[] = "clock_out_face_log_id = " . intval($face_log_id);
            }
            $update_fields[] = "clock_out_timestamp = '" . $conn->real_escape_string($timestamp) . "'";
        }
        
        if (empty($update_fields)) {
            throw new Exception('No evidence data provided to update');
        }
        
        $update_sql = "UPDATE learner_clocking_evidence SET " . 
                     implode(', ', $update_fields) . 
                     ", updated_at = NOW() WHERE id = " . intval($record_id);
        
        write_evidence_log("UPDATE SQL: $update_sql");
        
        if (!$conn->query($update_sql)) {
            write_evidence_log("ERROR: Failed to update - " . $conn->error);
            throw new Exception('Failed to update evidence: ' . $conn->error);
        }
        
        write_evidence_log("SUCCESS: Updated $event_type evidence for learner $learner_id");
        
        error_log("[EVIDENCE] Updated $event_type evidence for learner $learner_id on $clock_date");
        
        write_evidence_log("Returning success response (UPDATE)");
        echo json_encode([
            'success' => true,
            'message' => ucfirst($event_type) . ' evidence updated successfully',
            'action' => 'updated',
            'learner_id' => $learner_id,
            'clock_date' => $clock_date,
            'signature_saved' => $signature_filename !== null && $signature_filename !== '',
            'photo_saved' => $photo_filename !== null && $photo_filename !== ''
        ]);
        
    } else {
        // INSERT new record
        $check_stmt->close();
        
        write_evidence_log("Record DOES NOT EXIST - will INSERT new record");
        
        // Use direct SQL instead of prepared statements (bind_param has issues on this server)
        // Escape all string values for security
        $signature_filename_escaped = $signature_filename ? $conn->real_escape_string($signature_filename) : null;
        $photo_filename_escaped = $photo_filename ? $conn->real_escape_string($photo_filename) : null;
        $verification_method_escaped = $verification_method ? $conn->real_escape_string($verification_method) : null;
        $timestamp_escaped = $conn->real_escape_string($timestamp);
        $clock_date_escaped = $conn->real_escape_string($clock_date);
        
        write_evidence_log("Escaped values for SQL");
        
        if ($event_type === 'clock_in') {
            $sql = "INSERT INTO learner_clocking_evidence (
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
                created_at
            ) VALUES (
                $learner_id,
                " . ($clock_date_escaped ? "'$clock_date_escaped'" : "NULL") . ",
                " . ($signature_filename_escaped ? "'$signature_filename_escaped'" : "NULL") . ",
                " . ($photo_filename_escaped ? "'$photo_filename_escaped'" : "NULL") . ",
                " . ($latitude !== null ? $latitude : "NULL") . ",
                " . ($longitude !== null ? $longitude : "NULL") . ",
                " . ($accuracy !== null ? $accuracy : "NULL") . ",
                " . ($verification_method_escaped ? "'$verification_method_escaped'" : "NULL") . ",
                " . ($face_log_id !== null ? $face_log_id : "NULL") . ",
                '$timestamp_escaped',
                NOW()
            )";
        } else { // clock_out
            $sql = "INSERT INTO learner_clocking_evidence (
                LearnerID,
                clock_date,
                clock_out_signature,
                clock_out_photo,
                clock_out_latitude,
                clock_out_longitude,
                clock_out_accuracy,
                clock_out_verification_method,
                clock_out_face_log_id,
                clock_out_timestamp,
                created_at
            ) VALUES (
                $learner_id,
                " . ($clock_date_escaped ? "'$clock_date_escaped'" : "NULL") . ",
                " . ($signature_filename_escaped ? "'$signature_filename_escaped'" : "NULL") . ",
                " . ($photo_filename_escaped ? "'$photo_filename_escaped'" : "NULL") . ",
                " . ($latitude !== null ? $latitude : "NULL") . ",
                " . ($longitude !== null ? $longitude : "NULL") . ",
                " . ($accuracy !== null ? $accuracy : "NULL") . ",
                " . ($verification_method_escaped ? "'$verification_method_escaped'" : "NULL") . ",
                " . ($face_log_id !== null ? $face_log_id : "NULL") . ",
                '$timestamp_escaped',
                NOW()
            )";
        }
        
        write_evidence_log("Executing direct SQL INSERT");
        
        if ($conn->query($sql)) {
            $inserted_id = $conn->insert_id;
            write_evidence_log("SUCCESS: Inserted $event_type evidence with ID: $inserted_id");
        } else {
            write_evidence_log("ERROR: Failed to execute SQL - " . $conn->error);
            throw new Exception('Failed to insert evidence: ' . $conn->error);
        }
        
        error_log("[EVIDENCE] Inserted $event_type evidence for learner $learner_id on $clock_date");
        
        write_evidence_log("Returning success response (INSERT)");
        echo json_encode([
            'success' => true,
            'message' => ucfirst($event_type) . ' evidence saved successfully',
            'action' => 'inserted',
            'learner_id' => $learner_id,
            'clock_date' => $clock_date,
            'signature_saved' => $signature_filename !== null && $signature_filename !== '',
            'photo_saved' => $photo_filename !== null && $photo_filename !== ''
        ]);
    }
    
} catch (Exception $e) {
    http_response_code(400);
    write_evidence_log("EXCEPTION: " . $e->getMessage());
    write_evidence_log("Stack trace: " . $e->getTraceAsString());
    error_log("[EVIDENCE] Error: " . $e->getMessage());
    echo json_encode([
        'success' => false,
        'message' => $e->getMessage()
    ]);
}

write_evidence_log("========== END REQUEST ==========\n");
