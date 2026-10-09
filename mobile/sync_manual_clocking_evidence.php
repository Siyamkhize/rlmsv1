<?php
/**
 * Sync Manual Clocking Evidence (Offline → Online)
 * 
 * Receives manual clocking evidence records with base64-encoded images from offline app
 * Saves images to server and inserts/updates manual_clocking_evidence table
 * Supports batch sync of multiple records
 */

header('Content-Type: application/json');
require_once 'connection.php';
require_once '../security_functions.php';

// Enable error logging
error_reporting(E_ALL);
ini_set('display_errors', 1);

try {
    // Get JSON input
    $input = json_decode(file_get_contents('php://input'), true);
    
    if (!$input || !isset($input['records']) || !is_array($input['records'])) {
        throw new Exception('Invalid input. Expected "records" array.');
    }
    
    $records = $input['records'];
    $results = [];
    $successCount = 0;
    $failCount = 0;
    
    // Ensure directories exist
    $baseDir = __DIR__;
    $facesDir = $baseDir . '/manual_clocking_evidence/faces';
    $signaturesDir = $baseDir . '/manual_clocking_evidence/signatures';
    
    if (!file_exists($facesDir)) {
        mkdir($facesDir, 0755, true);
    }
    if (!file_exists($signaturesDir)) {
        mkdir($signaturesDir, 0755, true);
    }
    
    // Process each record
    foreach ($records as $index => $record) {
        try {
            // Validate required fields
            if (!isset($record['LearnerID']) || !isset($record['clock_date'])) {
                throw new Exception("Record $index: Missing LearnerID or clock_date");
            }
            
            $learnerID = intval($record['LearnerID']);
            $clockDate = $record['clock_date'];
            
            // Process images and get filenames
            $signatureInFilename = null;
            $signatureOutFilename = null;
            $faceInFilename = null;
            $faceOutFilename = null;
            
            // Save signature_in image
            if (!empty($record['signature_in_base64'])) {
                $signatureInFilename = saveImage(
                    $record['signature_in_base64'], 
                    $signaturesDir, 
                    "signature_in_{$learnerID}_{$clockDate}_" . time() . ".png",
                    'png'
                );
            } elseif (!empty($record['signature_in'])) {
                // Already a filename
                $signatureInFilename = $record['signature_in'];
            }
            
            // Save signature_out image
            if (!empty($record['signature_out_base64'])) {
                $signatureOutFilename = saveImage(
                    $record['signature_out_base64'], 
                    $signaturesDir, 
                    "signature_out_{$learnerID}_{$clockDate}_" . time() . ".png",
                    'png'
                );
            } elseif (!empty($record['signature_out'])) {
                $signatureOutFilename = $record['signature_out'];
            }
            
            // Save face_in image
            if (!empty($record['face_in_base64'])) {
                $faceInFilename = saveImage(
                    $record['face_in_base64'], 
                    $facesDir, 
                    "face_in_{$learnerID}_{$clockDate}_" . time() . ".jpg",
                    'jpg'
                );
            } elseif (!empty($record['face_in'])) {
                $faceInFilename = $record['face_in'];
            }
            
            // Save face_out image
            if (!empty($record['face_out_base64'])) {
                $faceOutFilename = saveImage(
                    $record['face_out_base64'], 
                    $facesDir, 
                    "face_out_{$learnerID}_{$clockDate}_" . time() . ".jpg",
                    'jpg'
                );
            } elseif (!empty($record['face_out'])) {
                $faceOutFilename = $record['face_out'];
            }
            
            // Insert or update database record
            $stmt = $conn->prepare("
                INSERT INTO manual_clocking_evidence 
                (LearnerID, clock_date, signature_in, signature_out, face_in, face_out, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, NOW(), NOW())
                ON DUPLICATE KEY UPDATE
                    signature_in = COALESCE(VALUES(signature_in), signature_in),
                    signature_out = COALESCE(VALUES(signature_out), signature_out),
                    face_in = COALESCE(VALUES(face_in), face_in),
                    face_out = COALESCE(VALUES(face_out), face_out),
                    updated_at = NOW()
            ");
            
            $stmt->bind_param("isssss", 
                $learnerID, 
                $clockDate, 
                $signatureInFilename, 
                $signatureOutFilename, 
                $faceInFilename, 
                $faceOutFilename
            );
            
            if (!$stmt->execute()) {
                throw new Exception("Database error: " . $stmt->error);
            }
            
            $stmt->close();
            
            $results[] = [
                'index' => $index,
                'learner_id' => $learnerID,
                'clock_date' => $clockDate,
                'success' => true,
                'files' => [
                    'signature_in' => $signatureInFilename,
                    'signature_out' => $signatureOutFilename,
                    'face_in' => $faceInFilename,
                    'face_out' => $faceOutFilename
                ]
            ];
            
            $successCount++;
            
        } catch (Exception $e) {
            $results[] = [
                'index' => $index,
                'success' => false,
                'error' => $e->getMessage()
            ];
            $failCount++;
        }
    }
    
    echo json_encode([
        'success' => true,
        'message' => "Sync complete: $successCount succeeded, $failCount failed",
        'total' => count($records),
        'success_count' => $successCount,
        'fail_count' => $failCount,
        'results' => $results
    ]);
    
} catch (Exception $e) {
    http_response_code(400);
    echo json_encode([
        'success' => false,
        'error' => $e->getMessage()
    ]);
}

/**
 * Save base64-encoded image to file
 * 
 * @param string $base64Data Base64-encoded image data
 * @param string $directory Target directory
 * @param string $filename Filename to save as
 * @param string $format Image format ('jpg' or 'png')
 * @return string Filename on success
 * @throws Exception on failure
 */
function saveImage($base64Data, $directory, $filename, $format = 'jpg') {
    // Remove data URI prefix if present
    $base64Data = preg_replace('/^data:image\/\w+;base64,/', '', $base64Data);
    $imageData = base64_decode($base64Data);
    
    if ($imageData === false) {
        throw new Exception('Invalid image data');
    }
    
    $filepath = $directory . '/' . $filename;
    
    // Save image
    if (file_put_contents($filepath, $imageData) === false) {
        throw new Exception("Failed to save image: $filename");
    }
    
    return $filename;
}

if (isset($conn)) {
    $conn->close();
}
?>
