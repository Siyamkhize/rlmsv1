<?php
date_default_timezone_set('Africa/Johannesburg');

header('Content-Type: application/json');

// Return current server time in multiple formats for verification
$response = [
    'success' => true,
    'server_time' => date('Y-m-d H:i:s'),
    'server_timestamp' => time(),
    'timezone' => date_default_timezone_get(),
    'utc_offset' => date('Z') / 3600, // Hours from UTC
];

echo json_encode($response);
?>
