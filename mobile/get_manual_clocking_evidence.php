<?php
/**
 * Get Manual Clocking Evidence with Learner Details
 * 
 * Fetches records from manual_clocking_evidence table with learner names
 * Used to display learners who have submitted face photos and signatures
 * Joins with learnerdetails to get Name and Surname
 */
// Set timezone to South Africa (SAST = UTC+2) - CRITICAL for date/time consistency
date_default_timezone_set('Africa/Johannesburg');
header('Content-Type: application/json');
require_once 'connection.php';
require_once '../security_functions.php';

try {
    $clockDate = isset($_GET['clock_date']) ? $_GET['clock_date'] : date('Y-m-d');
    $learnerID = isset($_GET['learner_id']) ? intval($_GET['learner_id']) : null;
    
    // Build query based on parameters
    if ($learnerID) {
        // Fetch specific learner's evidence for the date
        $stmt = $conn->prepare("
            SELECT 
                mce.evidence_id,
                mce.LearnerID,
                mce.clock_date,
                mce.signature_in,
                mce.signature_out,
                mce.face_in,
                mce.face_out,
                mce.created_at,
                mce.updated_at,
                ld.Name,
                ld.Surname,
                ld.IDNumber
            FROM manual_clocking_evidence mce
            INNER JOIN learnerdetails ld ON mce.LearnerID = ld.LearnerID
            WHERE mce.clock_date = ?
            AND mce.LearnerID = ?
            ORDER BY mce.created_at DESC
        ");
        
        $stmt->bind_param("si", $clockDate, $learnerID);
    } else {
        // Fetch all evidence for the date
        $stmt = $conn->prepare("
            SELECT 
                mce.evidence_id,
                mce.LearnerID,
                mce.clock_date,
                mce.signature_in,
                mce.signature_out,
                mce.face_in,
                mce.face_out,
                mce.created_at,
                mce.updated_at,
                ld.Name,
                ld.Surname,
                ld.IDNumber
            FROM manual_clocking_evidence mce
            INNER JOIN learnerdetails ld ON mce.LearnerID = ld.LearnerID
            WHERE mce.clock_date = ?
            ORDER BY mce.created_at DESC
        ");
        
        $stmt->bind_param("s", $clockDate);
    }
    
    if (!$stmt->execute()) {
        throw new Exception('Query failed: ' . $stmt->error);
    }
    
    $result = $stmt->get_result();
    $records = [];
    
    while ($row = $result->fetch_assoc()) {
        $records[] = [
            'evidence_id' => $row['evidence_id'],
            'learner_id' => $row['LearnerID'],
            'learner_name' => $row['Name'],
            'learner_surname' => $row['Surname'],
            'learner_full_name' => trim($row['Name'] . ' ' . $row['Surname']),
            'id_number' => $row['IDNumber'],
            'clock_date' => $row['clock_date'],
            'signature_in' => $row['signature_in'],
            'signature_out' => $row['signature_out'],
            'face_in' => $row['face_in'],
            'face_out' => $row['face_out'],
            'created_at' => $row['created_at'],
            'updated_at' => $row['updated_at'],
            // Status flags
            'has_face_in' => !empty($row['face_in']),
            'has_face_out' => !empty($row['face_out']),
            'has_signature_in' => !empty($row['signature_in']),
            'has_signature_out' => !empty($row['signature_out']),
            'is_clocked_in' => !empty($row['face_in']) && !empty($row['signature_in']),
            'is_clocked_out' => !empty($row['face_out']) && !empty($row['signature_out']),
            'is_complete' => !empty($row['face_in']) && !empty($row['signature_in']) && 
                           !empty($row['face_out']) && !empty($row['signature_out'])
        ];
    }
    
    $stmt->close();
    
    echo json_encode([
        'success' => true,
        'clock_date' => $clockDate,
        'count' => count($records),
        'records' => $records
    ]);
    
} catch (Exception $e) {
    http_response_code(400);
    echo json_encode([
        'success' => false,
        'error' => $e->getMessage()
    ]);
}

if (isset($conn)) {
    $conn->close();
}
?>
