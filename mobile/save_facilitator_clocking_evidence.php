<?php
/**
 * Save Facilitator Clocking Evidence
 * Handles signature and face photo files for facilitator clock-in/out
 * Files are saved to disk, only filenames stored in database
 * Similar to learner clocking evidence system
 */

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST');
header('Access-Control-Allow-Headers: Content-Type');

require_once '../db.php';

// Handle preflight requests
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Method not allowed']);
    exit();
}

try {
    // Get JSON input
    $json = file_get_contents('php://input');
    $data = json_decode($json, true);
    
    if (!$data) {
        throw new Exception('Invalid JSON data');
    }
    
    // Required fields
    $facilitator_id = $data['facilitator_id'] ?? null;
    $clock_date = $data['clock_date'] ?? null;
    $action = $data['action'] ?? null; // 'in' or 'out'
    
    if (!$facilitator_id || !$clock_date || !$action) {
        throw new Exception('Missing required fields: facilitator_id, clock_date, action');
    }
    
    // Validate action
    if (!in_array($action, ['in', 'out'])) {
        throw new Exception('Invalid action. Must be "in" or "out"');
    }
    
    // Setup folders for facilitator clocking evidence
    $baseFolder = '../mobile/facilitator_clocking_evidence';
    $yearMonth = date('Y-m', strtotime($clock_date)); // e.g., "2026-09"
    $facilitatorFolder = "$baseFolder/$facilitator_id/$yearMonth";
    
    // Create folders if they don't exist
    if (!file_exists($facilitatorFolder)) {
        mkdir($facilitatorFolder, 0755, true);
    }
    
    // Prepare fields based on action
    $signature_field = "clock_{$action}_signature";
    $photo_field = "clock_{$action}_photo";
    $latitude_field = "clock_{$action}_latitude";
    $longitude_field = "clock_{$action}_longitude";
    $accuracy_field = "clock_{$action}_accuracy";
    $method_field = "clock_{$action}_verification_method";
    $log_id_field = "clock_{$action}_face_log_id";
    $timestamp_field = "clock_{$action}_timestamp";
    
    // Get evidence data
    $signature_base64 = $data['signature'] ?? null;
    $photo_base64 = $data['photo'] ?? null;
    $latitude = $data['latitude'] ?? null;
    $longitude = $data['longitude'] ?? null;
    $accuracy = $data['accuracy'] ?? null;
    $verification_method = $data['verification_method'] ?? null;
    $face_log_id = $data['face_log_id'] ?? null;
    $timestamp = $data['timestamp'] ?? date('Y-m-d H:i:s');
    
    // Save files and get filenames
    $signatureFilename = null;
    $photoFilename = null;
    
    if ($signature_base64) {
        // Remove data URI prefix if present
        $signature_base64 = preg_replace('#^data:image/\w+;base64,#i', '', $signature_base64);
        $signatureData = base64_decode($signature_base64);
        
        if ($signatureData === false) {
            throw new Exception('Invalid signature image data');
        }
        
        $signatureFilename = "facilitator_{$facilitator_id}_{$clock_date}_{$action}_signature.png";
        $signaturePath = "$facilitatorFolder/$signatureFilename";
        
        if (file_put_contents($signaturePath, $signatureData) === false) {
            throw new Exception('Failed to save signature image');
        }
    }
    
    if ($photo_base64) {
        // Remove data URI prefix if present
        $photo_base64 = preg_replace('#^data:image/\w+;base64,#i', '', $photo_base64);
        $photoData = base64_decode($photo_base64);
        
        if ($photoData === false) {
            throw new Exception('Invalid photo image data');
        }
        
        $photoFilename = "facilitator_{$facilitator_id}_{$clock_date}_{$action}_photo.jpg";
        $photoPath = "$facilitatorFolder/$photoFilename";
        
        if (file_put_contents($photoPath, $photoData) === false) {
            throw new Exception('Failed to save photo image');
        }
    }
    
    // Check if record exists
    $checkStmt = $conn->prepare("
        SELECT id FROM facilitator_clocking_evidence 
        WHERE facilitator_id = ? AND clock_date = ?
    ");
    $checkStmt->bind_param("is", $facilitator_id, $clock_date);
    $checkStmt->execute();
    $result = $checkStmt->get_result();
    
    if ($result->num_rows > 0) {
        // Update existing record
        $row = $result->fetch_assoc();
        $id = $row['id'];
        
        $updateFields = [];
        $updateValues = [];
        $types = "";
        
        if ($signatureFilename !== null) {
            $updateFields[] = "$signature_field = ?";
            $updateValues[] = $signatureFilename;
            $types .= "s";
        }
        if ($photoFilename !== null) {
            $updateFields[] = "$photo_field = ?";
            $updateValues[] = $photoFilename;
            $types .= "s";
        }
        if ($latitude !== null) {
            $updateFields[] = "$latitude_field = ?";
            $updateValues[] = $latitude;
            $types .= "d";
        }
        if ($longitude !== null) {
            $updateFields[] = "$longitude_field = ?";
            $updateValues[] = $longitude;
            $types .= "d";
        }
        if ($accuracy !== null) {
            $updateFields[] = "$accuracy_field = ?";
            $updateValues[] = $accuracy;
            $types .= "d";
        }
        if ($verification_method !== null) {
            $updateFields[] = "$method_field = ?";
            $updateValues[] = $verification_method;
            $types .= "s";
        }
        if ($face_log_id !== null) {
            $updateFields[] = "$log_id_field = ?";
            $updateValues[] = $face_log_id;
            $types .= "i";
        }
        if ($timestamp !== null) {
            $updateFields[] = "$timestamp_field = ?";
            $updateValues[] = $timestamp;
            $types .= "s";
        }
        
        if (empty($updateFields)) {
            throw new Exception('No data to update');
        }
        
        $updateSql = "UPDATE facilitator_clocking_evidence SET " . 
                     implode(", ", $updateFields) . 
                     " WHERE id = ?";
        
        $updateValues[] = $id;
        $types .= "i";
        
        $updateStmt = $conn->prepare($updateSql);
        $updateStmt->bind_param($types, ...$updateValues);
        
        if (!$updateStmt->execute()) {
            throw new Exception('Failed to update evidence: ' . $updateStmt->error);
        }
        
        echo json_encode([
            'success' => true,
            'message' => 'Evidence updated successfully',
            'action' => 'updated',
            'id' => $id,
            'signature_filename' => $signatureFilename,
            'photo_filename' => $photoFilename
        ]);
        
    } else {
        // Insert new record
        $insertStmt = $conn->prepare("
            INSERT INTO facilitator_clocking_evidence (
                facilitator_id,
                clock_date,
                $signature_field,
                $photo_field,
                $latitude_field,
                $longitude_field,
                $accuracy_field,
                $method_field,
                $log_id_field,
                $timestamp_field,
                synced
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)
        ");
        
        $insertStmt->bind_param(
            "isssdddsss",
            $facilitator_id,
            $clock_date,
            $signatureFilename,
            $photoFilename,
            $latitude,
            $longitude,
            $accuracy,
            $verification_method,
            $face_log_id,
            $timestamp
        );
        
        if (!$insertStmt->execute()) {
            throw new Exception('Failed to insert evidence: ' . $insertStmt->error);
        }
        
        $newId = $insertStmt->insert_id;
        
        echo json_encode([
            'success' => true,
            'message' => 'Evidence saved successfully',
            'action' => 'inserted',
            'id' => $newId,
            'signature_filename' => $signatureFilename,
            'photo_filename' => $photoFilename
        ]);
    }
    
} catch (Exception $e) {
    http_response_code(400);
    echo json_encode([
        'success' => false,
        'message' => $e->getMessage()
    ]);
}

$conn->close();
?>
