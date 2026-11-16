<?php
/**
 * mobile/upload_learner_confirmation.php
 * API endpoint for mobile app to upload attendance confirmation with learner list
 * 
 * Request (multipart/form-data):
 * - facilitator_id: int (required)
 * - class_id: int (required)
 * - submission_date: YYYY-MM-DD (required)
 * - learner_ids: JSON array [1,2,3] (required)
 * - pdf_file: File (required, max 2MB, PDF only)
 * 
 * Response:
 * {
 *   "success": true/false,
 *   "message": "...",
 *   "data": {
 *     "confirmation_id": 123,
 *     "manual_id": 456,
 *     "learners_count": 15,
 *     "pdf_filename": "confirmation_xxx.pdf",
 *     "pdf_size_kb": 1234
 *   }
 * }
 */

header('Content-Type: application/json');
require 'connection.php';

// Enable error logging
error_reporting(E_ALL);
ini_set('display_errors', 0);
ini_set('log_errors', 1);

function sendResponse($success, $message, $data = null, $httpCode = 200) {
    http_response_code($httpCode);
    echo json_encode([
        'success' => $success,
        'message' => $message,
        'data' => $data,
        'timestamp' => date('Y-m-d H:i:s')
    ]);
    exit;
}

// Only accept POST
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    sendResponse(false, 'Method not allowed. Use POST.', null, 405);
}

try {
    // ══════════════════════════════════════════════════════════════════════════
    // 1. VALIDATE INPUT
    // ══════════════════════════════════════════════════════════════════════════
    
    $facilitator_id  = isset($_POST['facilitator_id']) ? (int)$_POST['facilitator_id'] : 0;
    $class_id        = isset($_POST['class_id']) ? (int)$_POST['class_id'] : 0;
    $submission_date = isset($_POST['submission_date']) ? trim($_POST['submission_date']) : '';
    $learner_ids_json = isset($_POST['learner_ids']) ? trim($_POST['learner_ids']) : '';
    
    // Validate required fields
    if (!$facilitator_id) {
        sendResponse(false, 'facilitator_id is required', null, 400);
    }
    
    if (!$class_id) {
        sendResponse(false, 'class_id is required', null, 400);
    }
    
    if (!$submission_date || !preg_match('/^\d{4}-\d{2}-\d{2}$/', $submission_date)) {
        sendResponse(false, 'Valid submission_date (YYYY-MM-DD) is required', null, 400);
    }
    
    // Date must be TODAY only - no past or future dates
    $today = date('Y-m-d');
    if ($submission_date !== $today) {
        sendResponse(false, "Only current date ($today) is allowed. You cannot upload for past or future dates.", null, 400);
    }
    
    // Parse learner IDs
    $learner_ids = json_decode($learner_ids_json, true);
    if (!is_array($learner_ids) || empty($learner_ids)) {
        sendResponse(false, 'learner_ids must be a non-empty JSON array', null, 400);
    }
    
    // Sanitize learner IDs
    $learner_ids = array_map('intval', $learner_ids);
    $learner_ids = array_filter($learner_ids, function($id) { return $id > 0; });
    
    if (empty($learner_ids)) {
        sendResponse(false, 'No valid learner IDs provided', null, 400);
    }
    
    $learners_count = count($learner_ids);
    
    // ══════════════════════════════════════════════════════════════════════════
    // 2. VERIFY FACILITATOR & CLASS
    // ══════════════════════════════════════════════════════════════════════════
    
    // Check facilitator exists and is assigned to this class
    $fac_check = $conn->prepare("
        SELECT f.facilitator_id, f.firstName, f.lastName, f.classID,
               c.className, c.siteID, s.siteName
        FROM facilitator f
        JOIN class c ON c.classID = f.classID
        JOIN sites s ON s.siteID = c.siteID
        WHERE f.facilitator_id = ? AND f.classID = ?
        LIMIT 1
    ");
    $fac_check->bind_param('ii', $facilitator_id, $class_id);
    $fac_check->execute();
    $fac_result = $fac_check->get_result();
    
    if ($fac_result->num_rows === 0) {
        $fac_check->close();
        sendResponse(false, 'Facilitator not found or not assigned to this class', null, 403);
    }
    
    $facilitator = $fac_result->fetch_assoc();
    $fac_check->close();
    
    // ══════════════════════════════════════════════════════════════════════════
    // 3. VERIFY LEARNERS BELONG TO THIS CLASS
    // ══════════════════════════════════════════════════════════════════════════
    
    $placeholders = implode(',', array_fill(0, count($learner_ids), '?'));
    $types = str_repeat('i', count($learner_ids));
    
    $learner_check = $conn->prepare("
        SELECT LearnerID FROM learnerdetails 
        WHERE LearnerID IN ($placeholders) AND classID = ?
    ");
    
    // Bind learner IDs and class ID
    $bind_params = array_merge($learner_ids, [$class_id]);
    $types .= 'i';
    $learner_check->bind_param($types, ...$bind_params);
    $learner_check->execute();
    $valid_learners = $learner_check->get_result()->fetch_all(MYSQLI_ASSOC);
    $learner_check->close();
    
    $valid_count = count($valid_learners);
    if ($valid_count !== $learners_count) {
        sendResponse(false, 
            "Only $valid_count of $learners_count learners belong to this class", 
            null, 400
        );
    }
    
    // ══════════════════════════════════════════════════════════════════════════
    // 4. HANDLE PDF UPLOAD
    // ══════════════════════════════════════════════════════════════════════════
    
    if (!isset($_FILES['pdf_file']) || $_FILES['pdf_file']['error'] !== UPLOAD_ERR_OK) {
        $error_msg = 'PDF file upload failed';
        if (isset($_FILES['pdf_file']['error'])) {
            switch ($_FILES['pdf_file']['error']) {
                case UPLOAD_ERR_INI_SIZE:
                case UPLOAD_ERR_FORM_SIZE:
                    $error_msg = 'File exceeds maximum size (2MB)';
                    break;
                case UPLOAD_ERR_NO_FILE:
                    $error_msg = 'No file was uploaded';
                    break;
                default:
                    $error_msg = 'File upload error code: ' . $_FILES['pdf_file']['error'];
            }
        }
        sendResponse(false, $error_msg, null, 400);
    }
    
    $file = $_FILES['pdf_file'];
    $file_size = $file['size'];
    $file_tmp = $file['tmp_name'];
    $file_name = $file['name'];
    
    // Validate file size (2MB = 2097152 bytes)
    $max_size = 2 * 1024 * 1024;
    if ($file_size > $max_size) {
        $size_mb = round($file_size / (1024 * 1024), 2);
        sendResponse(false, "File too large: {$size_mb}MB. Maximum is 2MB", null, 400);
    }
    
    // Validate file type
    $file_ext = strtolower(pathinfo($file_name, PATHINFO_EXTENSION));
    if ($file_ext !== 'pdf') {
        sendResponse(false, 'Only PDF files are allowed', null, 400);
    }
    
    // Verify it's actually a PDF (check magic bytes)
    $finfo = finfo_open(FILEINFO_MIME_TYPE);
    $mime_type = finfo_file($finfo, $file_tmp);
    finfo_close($finfo);
    
    if ($mime_type !== 'application/pdf') {
        sendResponse(false, 'File is not a valid PDF', null, 400);
    }
    
    // Generate filename matching existing pattern: att_register_{facilitatorId}_{timestamp}.pdf
    $timestamp = date('Ymd_His');
    $new_filename = "att_register_{$facilitator_id}_{$timestamp}.pdf";
    
    // Determine upload directory (../uploads/ relative to mobile folder)
    $upload_dir = dirname(__DIR__) . '/uploads/';
    
    // Create uploads directory if it doesn't exist
    if (!is_dir($upload_dir)) {
        if (!mkdir($upload_dir, 0755, true)) {
            sendResponse(false, 'Failed to create uploads directory', null, 500);
        }
    }
    
    // Check if directory is writable
    if (!is_writable($upload_dir)) {
        sendResponse(false, 'Uploads directory is not writable', null, 500);
    }
    
    $destination = $upload_dir . $new_filename;
    
    // Move uploaded file
    if (!move_uploaded_file($file_tmp, $destination)) {
        sendResponse(false, 'Failed to save uploaded file', null, 500);
    }
    
    // ══════════════════════════════════════════════════════════════════════════
    // 5. CHECK FOR DUPLICATE LEARNERS (Per-learner check, not per-facilitator)
    // ══════════════════════════════════════════════════════════════════════════
    
    // Find which learners already have records for this date
    $placeholders_dup = implode(',', array_fill(0, count($learner_ids), '?'));
    $types_dup = str_repeat('i', count($learner_ids)) . 's';
    
    $duplicate_check = $conn->prepare("
        SELECT DISTINCT LearnerID 
        FROM manual_clocking 
        WHERE LearnerID IN ($placeholders_dup) 
        AND clock_date = ?
    ");
    
    $bind_params_dup = array_merge($learner_ids, [$submission_date]);
    $duplicate_check->bind_param($types_dup, ...$bind_params_dup);
    $duplicate_check->execute();
    $duplicate_learners = $duplicate_check->get_result()->fetch_all(MYSQLI_ASSOC);
    $duplicate_check->close();
    
    if (!empty($duplicate_learners)) {
        // Get list of duplicate learner IDs
        $duplicate_ids = array_column($duplicate_learners, 'LearnerID');
        $duplicate_count = count($duplicate_ids);
        
        // Delete uploaded file since we're rejecting this
        if (file_exists($destination)) {
            @unlink($destination);
        }
        
        sendResponse(false, 
            "$duplicate_count learner(s) already have attendance records for $submission_date. Please unselect them and try again.", 
            [
                'duplicate_learner_ids' => $duplicate_ids,
                'duplicate_count' => $duplicate_count,
                'submission_date' => $submission_date
            ],
            409 // Conflict
        );
    }
    
    // ══════════════════════════════════════════════════════════════════════════
    // 6. INSERT DATABASE RECORDS
    // ══════════════════════════════════════════════════════════════════════════
    
    $conn->begin_transaction();
    
    try {
        $now = date('Y-m-d H:i:s');
        $first_manual_id = null;
        $inserted_count = 0;
        
        // Insert manual_clocking for each of the 36 learners
        foreach ($learner_ids as $learner_id) {
            // Check if record already exists for this learner on this date
            $exists_check = $conn->prepare("
                SELECT manual_id FROM manual_clocking 
                WHERE LearnerID = ? AND clock_date = ?
                LIMIT 1
            ");
            $exists_check->bind_param('is', $learner_id, $submission_date);
            $exists_check->execute();
            $existing = $exists_check->get_result()->fetch_assoc();
            $exists_check->close();
            
            if ($existing) {
                // Use existing manual_id
                if (!$first_manual_id) {
                    $first_manual_id = $existing['manual_id'];
                }
                continue;
            }
            
            // Insert new manual_clocking record for this learner
            $insert_stmt = $conn->prepare("
                INSERT INTO manual_clocking (LearnerID, clock_date, fdp_document, status)
                VALUES (?, ?, ?, 'Pending')
            ");
            
            if (!$insert_stmt) {
                throw new Exception('Prepare failed for manual_clocking: ' . $conn->error);
            }
            
            $insert_stmt->bind_param('iss', 
                $learner_id, 
                $submission_date, 
                $new_filename
            );
            
            if (!$insert_stmt->execute()) {
                throw new Exception('Failed to insert manual_clocking record: ' . $insert_stmt->error);
            }
            
            if (!$first_manual_id) {
                $first_manual_id = $insert_stmt->insert_id;
            }
            
            $inserted_count++;
            $insert_stmt->close();
        }
        
        if (!$first_manual_id) {
            throw new Exception('No manual_clocking records were created');
        }
        
        // Insert confirmation record linked to first manual_clocking record
        $facilitator_confirmation = isset($_POST['facilitator_confirmation']) ? (int)$_POST['facilitator_confirmation'] : 1;
        
        $conf_stmt = $conn->prepare("
            INSERT INTO learner_submission_confirmations
                (facilitator_id, manual_id, submission_date, learners_counted, pdf_filename, facilitator_confirmation)
            VALUES (?, ?, ?, ?, ?, ?)
        ");
        
        if (!$conf_stmt) {
            throw new Exception('Prepare failed for confirmation: ' . $conn->error);
        }
        
        $conf_stmt->bind_param('iisisi',
            $facilitator_id,             // facilitator_id (int)
            $first_manual_id,            // manual_id (int)
            $submission_date,            // submission_date (string)
            $learners_count,             // learners_counted (int)
            $new_filename,               // pdf_filename (string)
            $facilitator_confirmation    // facilitator_confirmation (int: 1 = confirmed)
        );
        
        if (!$conf_stmt->execute()) {
            throw new Exception('Failed to insert confirmation record: ' . $conf_stmt->error);
        }
        
        $confirmation_id = $conf_stmt->insert_id;
        $conf_stmt->close();
        
        $conn->commit();
        
        // ══════════════════════════════════════════════════════════════════════
        // 6. SUCCESS RESPONSE
        // ══════════════════════════════════════════════════════════════════════
        
        $response_data = [
            'confirmation_id' => $confirmation_id,
            'manual_id' => $first_manual_id,
            'learners_count' => $learners_count,
            'manual_clocking_inserted' => $inserted_count,
            'pdf_filename' => $new_filename,
            'pdf_size_kb' => round($file_size / 1024, 2),
            'submission_date' => $submission_date,
            'facilitator' => [
                'id' => $facilitator['facilitator_id'],
                'name' => $facilitator['firstName'] . ' ' . $facilitator['lastName']
            ],
            'class' => [
                'id' => $class_id,
                'name' => $facilitator['className']
            ]
        ];
        
        sendResponse(true, 
            "Successfully uploaded confirmation for $learners_count learner(s). Created $inserted_count manual clocking records.", 
            $response_data
        );
        
    } catch (Exception $e) {
        $conn->rollback();
        
        // Delete uploaded file on database error
        if (file_exists($destination)) {
            @unlink($destination);
        }
        
        sendResponse(false, 'Database error: ' . $e->getMessage(), null, 500);
    }
    
} catch (Exception $e) {
    error_log('Upload confirmation error: ' . $e->getMessage());
    sendResponse(false, 'Server error: ' . $e->getMessage(), null, 500);
}
?>
