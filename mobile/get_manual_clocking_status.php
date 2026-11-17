<?php
/**
 * Get Manual Clocking Status for Class
 * 
 * Fetches ALL learners in a class with their clocking status for a specific date
 * Used by signature_geofence_clock_in_page to show all learners with status
 * 
 * LAST UPDATED: 2026/11/03 - No changes (Flutter side updated for cross-device sync)
 */

header('Content-Type: application/json');
require_once 'connection.php';
require_once '../security_functions.php';

try {
    $clockDate = isset($_GET['clock_date']) ? $_GET['clock_date'] : date('Y-m-d');
    $classID = isset($_GET['classID']) ? $_GET['classID'] : null;
    
    if (!$classID) {
        throw new Exception('classID is required');
    }
    
    // Fetch ALL learners in the class with their clocking status for the date
    $stmt = $conn->prepare("
        SELECT 
            ld.LearnerID,
            ld.Name,
            ld.Surname,
            ld.IDNumber,
            ld.classID,
            mc.manual_id,
            mc.clock_in_time,
            mc.clock_out_time,
            mc.contact_time
        FROM learnerdetails ld
        LEFT JOIN manual_clocking mc ON ld.LearnerID = mc.LearnerID 
            AND mc.clock_date = ? 
            AND mc.is_manual_attendance = 1
        WHERE ld.classID = ?
        ORDER BY ld.Name ASC, ld.Surname ASC
    ");
    
    $stmt->bind_param("ss", $clockDate, $classID);
    
    if (!$stmt->execute()) {
        throw new Exception('Query failed: ' . $stmt->error);
    }
    
    $result = $stmt->get_result();
    $data = [];
    
    while ($row = $result->fetch_assoc()) {
        $data[] = [
            'LearnerID' => $row['LearnerID'],
            'learner_id' => $row['LearnerID'],  // Flutter expects lowercase with underscore
            'Name' => $row['Name'],
            'Surname' => $row['Surname'],
            'IDNumber' => $row['IDNumber'],
            'classID' => $row['classID'],
            'manual_id' => $row['manual_id'],
            'clock_in_time' => $row['clock_in_time'],
            'clock_out_time' => $row['clock_out_time'],
            'contact_time' => $row['contact_time'],
            'is_clocked_in' => !empty($row['clock_in_time']),
            'is_clocked_out' => !empty($row['clock_out_time']),
            'is_complete' => !empty($row['clock_in_time']) && !empty($row['clock_out_time'])
        ];
    }
    
    $stmt->close();
    
    echo json_encode([
        'success' => true,      // Flutter expects 'success' boolean field
        'status' => 'success',
        'clock_date' => $clockDate,
        'classID' => $classID,
        'count' => count($data),
        'records' => $data,     // Flutter expects 'records' array
        'data' => $data         // Keep 'data' for backward compatibility
    ]);
    
} catch (Exception $e) {
    http_response_code(400);
    echo json_encode([
        'status' => 'error',
        'message' => $e->getMessage()
    ]);
}

if (isset($conn)) {
    $conn->close();
}
?>
