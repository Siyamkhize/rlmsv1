<?php
/**
 * Secure Database Connection
 * Loads credentials from environment file (config/db.env)
 * NEVER hardcode credentials in this file!
 */

// Set timezone to South Africa (SAST = UTC+2) - CRITICAL for date/time consistency
date_default_timezone_set('Africa/Johannesburg');

require_once __DIR__ . '/security_functions.php';
require_once __DIR__ . '/security_middleware.php';

// Load environment variables securely
$envFile = dirname(__DIR__) . '/config/db.env';
if (!file_exists($envFile)) {
    error_log("CRITICAL: config/db.env not found. Copy config/db.env.example and configure it.");
    die("Database configuration error. Please contact administrator.");
}

// Parse .env file
$env = parse_ini_file($envFile);
if (!$env) {
    error_log("CRITICAL: Failed to parse config/db.env");
    die("Database configuration error. Please contact administrator.");
}

// Get database credentials from environment
$servername = $env['DB_HOST'] ?? 'localhost';
$username = $env['DB_USERNAME'] ?? '';
$password = $env['DB_PASSWORD'] ?? '';
$dbname = $env['DB_NAME'] ?? '';
$tblname = $env['DB_TABLE'] ?? 'sdp';

// Validate credentials are set
if (empty($username) || empty($dbname)) {
    error_log("CRITICAL: Database credentials not configured in config/db.env");
    die("Database configuration error. Please contact administrator.");
}

// Create connection
$conn = new mysqli($servername, $username, $password, $dbname);
if ($conn->connect_error) {
    error_log("Database connection failed: " . $conn->connect_error);
    die("Connection failed: " . $conn->connect_error);
}

// Make MySQL's NOW() / CURRENT_TIMESTAMP agree with PHP (SAST, no daylight saving)
$conn->set_charset('utf8mb4');
$conn->query("SET time_zone = '+02:00'");
