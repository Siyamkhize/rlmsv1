<?php
/**
 * Get Manual Clocking Status
 * 
 * Fetches manual clocking records for a specific date
 * Used by signature_geofence_clock_in_page to show clocking status
 */

header('Content-Type: application/json');
require_once 'connection.php';
require_once '../security_functions.php';

try {
    $clockDate = isset($_GET['clock_date']) ? $_GET['clock_date'] : date('Y-m-d');
    
    // Fetch all manual clocking records for the date
    $stmt = $conn->prepare("
        SELECT 
            mc.manual_id,
            mc.LearnerID,
            mc.clock_date,
            mc.clock_in_time,
            mc.clock_out_time,
            mc.contact_time,
            ld.Name,
            ld.Surname,
            ld.IDNumber
        FROM manual_clocking mc
        INNER JOIN learnerdetails ld ON mc.LearnerID = ld.LearnerID
        WHERE mc.clock_date = ?
        AND mc.is_manual_attendance = 1
        ORDER BY mc.clock_in_time DESC
    ");
    
    $stmt->bind_param("s", $clockDate);
    
    if (!$stmt->execute()) {
        throw new Exception('Query failed: ' . $stmt->error);
    }
    
    $result = $stmt->get_result();
    $records = [];
    
    while ($row = $result->fetch_assoc()) {
        $records[] = [
            'manual_id' => $row['manual_id'],
            'learner_id' => $row['LearnerID'],
            'clock_date' => $row['clock_date'],
            'clock_in_time' => $row['clock_in_time'],
            'clock_out_time' => $row['clock_out_time'],
            'contact_time' => $row['contact_time'],
            'first_name' => $row['Name'],
            'last_name' => $row['Surname'],
            'id_number' => $row['IDNumber'],
            'is_clocked_in' => !empty($row['clock_in_time']),
            'is_clocked_out' => !empty($row['clock_out_time']),
            'is_complete' => !empty($row['clock_in_time']) && !empty($row['clock_out_time'])
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
