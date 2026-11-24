<?php
/**
 * Web Module Database Connection
 * Loads the database connection from parent directory
 */

// Get the parent connection file
$root_connection = __DIR__ . '/../connection.php';

if (!file_exists($root_connection)) {
    // Return path for debugging - let caller handle the error
    $GLOBALS['connection_error'] = 'Database connection file not found at: ' . $root_connection;
    return;
}

@require_once $root_connection;

// Verify connection is established
if (!isset($conn) || !$conn || (isset($conn) && $conn && $conn->connect_error)) {
    $GLOBALS['connection_error'] = 'Database connection failed';
    return;
}
?>
