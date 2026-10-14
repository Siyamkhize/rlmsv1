<?php
/**
 * Server Time Endpoint
 * 
 * Returns server UTC timestamp for device time verification.
 * SECURITY: Both device and server must compare UTC timestamps to ensure
 * timezone differences don't cause false positives in clock validation.
 */

header('Content-Type: application/json');

// IMPORTANT: Return UTC time for proper comparison
// Device time validator must convert device time to UTC before comparing
$utcNow = new DateTime('now', new DateTimeZone('UTC'));
$serverLocalTime = new DateTime('now', new DateTimeZone('Africa/Johannesburg'));

$response = [
    'success' => true,
    // PRIMARY: UTC timestamp for device time comparison (required for accuracy)
    'server_time_utc' => $utcNow->format('c'), // ISO 8601 with Z suffix
    'server_timestamp_utc' => $utcNow->getTimestamp(),
    
    // SECONDARY: Local South African time for reference only
    'server_time_local' => $serverLocalTime->format('Y-m-d H:i:s'),
    'timezone_local' => 'Africa/Johannesburg',
    'utc_offset_hours' => 2, // SAST is UTC+2
    
    // Processing time for RTT calculation (optional future enhancement)
    'server_processing_ms' => 0, // Minimal processing, <1ms
];

echo json_encode($response);
?>
