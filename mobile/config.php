<?php
/**
 * Database Configuration - RLMS
 * 
 * This file manages database credentials securely using environment variables.
 * NEVER commit actual credentials to version control!
 * 
 * Setup:
 * 1. Create a .env file in the mobile/ directory (add to .gitignore)
 * 2. Add your database credentials there
 * 3. OR set environment variables on your server
 */

// Load environment variables from .env file if it exists (local development)
if (file_exists(__DIR__ . '/.env')) {
    $lines = file(__DIR__ . '/.env', FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    foreach ($lines as $line) {
        if (strpos(trim($line), '#') === 0) continue; // Skip comments
        list($name, $value) = explode('=', $line, 2);
        $_ENV[trim($name)] = trim($value);
    }
}

// Database configuration from environment variables
// Falls back to localhost defaults for local development
$servername = getenv('DB_HOST') ?: ($_ENV['DB_HOST'] ?? 'localhost');
$username = getenv('DB_USER') ?: ($_ENV['DB_USER'] ?? 'root');
$password = getenv('DB_PASSWORD') ?: ($_ENV['DB_PASSWORD'] ?? '');
$dbname = getenv('DB_NAME') ?: ($_ENV['DB_NAME'] ?? 'rlmsrlmsco_ezxcmacd_rlms');

// Detect environment
function isLocalEnvironment() {
    $host = strtolower($_SERVER['HTTP_HOST'] ?? '');
    return $host === 'localhost'
        || strpos($host, 'localhost:') === 0
        || $host === '127.0.0.1'
        || strpos($host, '127.0.0.1:') === 0
        || strpos($host, '192.168.') === 0;
}

// Security check: Don't allow empty password in production
if (!isLocalEnvironment() && empty($password)) {
    error_log("[SECURITY] Empty database password in production environment!");
    die(json_encode([
        'success' => false,
        'message' => 'Database configuration error'
    ]));
}

// Create connection
$conn = new mysqli($servername, $username, $password, $dbname);

// Check connection
if ($conn->connect_error) {
    error_log("[DATABASE] Connection failed: " . $conn->connect_error);
    die(json_encode([
        'success' => false,
        'message' => 'Database connection failed'
    ]));
}

// Set charset to UTF-8
$conn->set_charset("utf8mb4");

// Set timezone to South Africa (SAST = UTC+2)
date_default_timezone_set('Africa/Johannesburg');

