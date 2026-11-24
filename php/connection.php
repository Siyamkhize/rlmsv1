<?php
/**
 * Secure Database Connection (Local Development)
 * Loads credentials from environment file (config/db.env)
 */

// Load environment variables securely
$envFile = dirname(__DIR__) . '/config/db.env';
if (!file_exists($envFile)) {
    error_log("CRITICAL: config/db.env not found");
    die("Database configuration error.");
}

$env = parse_ini_file($envFile);
if (!$env) {
    error_log("CRITICAL: Failed to parse config/db.env");
    die("Database configuration error.");
}

$servername = $env['DB_HOST'] ?? 'localhost';
$username = $env['DB_USERNAME'] ?? 'root';
$password = $env['DB_PASSWORD'] ?? '';
$dbname = $env['DB_NAME'] ?? 'rlmss';

try {
    // Create connection
    $conn = new mysqli($servername, $username, $password, $dbname);

    // Check connection
    if ($conn->connect_error) {
        throw new Exception("Connection failed: " . $conn->connect_error);
    }

    // Set charset to UTF-8
    $conn->set_charset("utf8");
    
} catch (Exception $e) {
    error_log("Database connection error: " . $e->getMessage());
    file_put_contents('debug_clockin.log', "Database connection failed: " . $e->getMessage() . PHP_EOL, FILE_APPEND);
    throw $e;
}
?>
