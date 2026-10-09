<?php
/**
 * Get today's learner clocking evidence records
 * Used to sync server records to local database
 */

require_once '../connection.php';
// Authentication removed for backup clock-in sync functionality
header('Content-Type: application/json');

try {
    $data = json_decode(file_get_contents('php://input'), true);
    $clockDate = $data['date'] ?? date('Y-m-d');
    
    // Validate date format
    if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $clockDate)) {
        throw new Exception('Invalid date format');
    }
    
    // Fetch all evidence records for the specified date
    $query = "SELECT 
        LearnerID,
        clock_date,
        clock_in_timestamp,
        clock_out_timestamp,
        clock_in_signature,
        clock_out_signature,
        clock_in_photo,
        clock_out_photo,
        clock_in_latitude,
        clock_in_longitude,
        clock_in_accuracy,
        clock_out_latitude,
        clock_out_longitude,
        clock_out_accuracy,
        clock_in_verification_method,
        clock_in_face_log_id
    FROM learner_clocking_evidence
    WHERE clock_date = ?
    ORDER BY LearnerID";
    
    $stmt = $conn->prepare($query);
    $stmt->bind_param('s', $clockDate);
    $stmt->execute();
    $result = $stmt->get_result();
    
    $records = [];
    while ($row = $result->fetch_assoc()) {
        // Map MySQL column names to SQLite column names for the app
        $records[] = [
            'learner_id' => $row['LearnerID'],
            'clock_date' => $row['clock_date'],
            'clock_in_timestamp' => $row['clock_in_timestamp'],
            'clock_out_timestamp' => $row['clock_out_timestamp'],
            'clock_in_signature' => $row['clock_in_signature'],
            'clock_out_signature' => $row['clock_out_signature'],
            'clock_in_photo' => $row['clock_in_photo'],
            'clock_out_photo' => $row['clock_out_photo'],
            'clock_in_latitude' => $row['clock_in_latitude'],
            'clock_in_longitude' => $row['clock_in_longitude'],
            'clock_in_accuracy' => $row['clock_in_accuracy'],
            'clock_out_latitude' => $row['clock_out_latitude'],
            'clock_out_longitude' => $row['clock_out_longitude'],
            'clock_out_accuracy' => $row['clock_out_accuracy'],
            'verification_method' => $row['clock_in_verification_method'],
            'face_log_id' => $row['clock_in_face_log_id'],
        ];
    }
    
    echo json_encode([
        'success' => true,
        'date' => $clockDate,
        'count' => count($records),
        'records' => $records
    ]);
    
} catch (Exception $e) {
    echo json_encode([
        'success' => false,
        'message' => $e->getMessage()
    ]);
}
?>
