<?php
/**
 * Security Middleware - Core Security Functions
 * 
 * Provides:
 * - Input sanitization and validation
 * - Rate limiting
 * - Authentication token validation
 * - File upload security
 * - CSRF protection
 * - Security event logging
 * - Global request monitoring
 * 
 * @version 1.0.0
 * @security CRITICAL - Do not modify without security review
 */

// Prevent direct access
if (!defined('SECURITY_FUNCTIONS_LOADED')) {
    define('SECURITY_FUNCTIONS_LOADED', true);
}

// Load request logger if available
if (file_exists(__DIR__ . '/request_logger.php')) {
    require_once __DIR__ . '/request_logger.php';
}

// Security headers
header('X-Content-Type-Options: nosniff');
header('X-Frame-Options: DENY');
header('X-XSS-Protection: 1; mode=block');
header('Referrer-Policy: strict-origin-when-cross-origin');

// CORS headers - configure based on your needs
header('Access-Control-Allow-Origin: *');  // Change to specific domain in production
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-CSRF-Token');

/**
 * Apply rate limiting with standard limits
 * Convenience function for endpoint protection
 * 
 * @param int $max_requests Maximum requests per minute
 * @param string $action Action identifier for rate limiting
 */
if (!function_exists('applyRateLimit')) {
function applyRateLimit($max_requests = 10, $action = 'api_request') {
    global $conn;
    
    if (!$conn) {
        // If no DB connection, skip rate limiting but log the attempt
        error_log("Rate limiting skipped - no database connection for action: $action");
        return;
    }
    
    $ip = get_client_ip();
    $window_seconds = 60; // 1 minute window
    
    $result = check_rate_limit($conn, $ip, $action, $max_requests, $window_seconds);
    
    if (!$result['allowed']) {
        // Log security event
        log_security_event('RATE_LIMIT_EXCEEDED', 
            "Rate limit exceeded for action: $action", 
            [
                'action' => $action,
                'ip' => $ip,
                'max_requests' => $max_requests,
                'retry_after' => $result['retry_after']
            ]
        );
        
        http_response_code(429);
        header('Retry-After: ' . $result['retry_after']);
        echo json_encode([
            'error' => 'Too Many Requests',
            'message' => $result['message'],
            'retry_after' => $result['retry_after']
        ]);
        exit;
    }
}
}

/**
 * Global rate limiting check
 * Apply broad rate limits to prevent system overload
 * 
 * @param mysqli $conn Database connection
 * @param int $max_requests_per_minute Maximum requests per minute globally
 */
if (!function_exists('applyGlobalRateLimit')) {
function applyGlobalRateLimit($conn, $max_requests_per_minute = 100) {
    $ip = get_client_ip();
    
    // Check global rate limit (all endpoints combined)
    $result = check_rate_limit($conn, $ip, 'global_requests', $max_requests_per_minute, 60);
    
    if (!$result['allowed']) {
        log_security_event('GLOBAL_RATE_LIMIT_EXCEEDED', 
            "Global rate limit exceeded from IP: $ip", 
            [
                'ip' => $ip,
                'max_requests' => $max_requests_per_minute,
                'retry_after' => $result['retry_after']
            ]
        );
        
        http_response_code(429);
        header('Retry-After: ' . $result['retry_after']);
        echo json_encode([
            'error' => 'Global Rate Limit Exceeded',
            'message' => 'Too many requests from your IP address. Please slow down.',
            'retry_after' => $result['retry_after']
        ]);
        exit;
    }
}
}

/**
 * Initialize request monitoring and security
 * Call this at the start of every endpoint
 * 
 * @param mysqli $conn Database connection
 * @param string $endpoint_name Name of the endpoint
 * @return int Request log ID for completion tracking
 */
if (!function_exists('initializeRequestSecurity')) {
function initializeRequestSecurity($conn, $endpoint_name) {
    $log_id = 0;
    
    try {
        // Apply global rate limiting first
        applyGlobalRateLimit($conn, 100); // 100 requests per minute globally per IP
        
        // Log the request if logging is available
        if (function_exists('log_request')) {
            $log_id = log_request($conn, $endpoint_name, [
                'user_agent' => $_SERVER['HTTP_USER_AGENT'] ?? '',
                'content_type' => $_SERVER['CONTENT_TYPE'] ?? ''
            ]);
        }
        
        return $log_id;
        
    } catch (Exception $e) {
        // Don't let security failures break the endpoint
        error_log("Request security initialization failed: " . $e->getMessage());
        return $log_id;
    }
}
}

/**
 * Get client IP address (handles proxies)
 */
if (!function_exists('get_client_ip')) {
function get_client_ip() {
    $ip = $_SERVER['REMOTE_ADDR'] ?? '0.0.0.0';
    
    // Check for IP from proxy
    if (!empty($_SERVER['HTTP_CLIENT_IP'])) {
        $ip = $_SERVER['HTTP_CLIENT_IP'];
    } elseif (!empty($_SERVER['HTTP_X_FORWARDED_FOR'])) {
        $ip = explode(',', $_SERVER['HTTP_X_FORWARDED_FOR'])[0];
    } elseif (!empty($_SERVER['HTTP_CF_CONNECTING_IP'])) {
        // Cloudflare
        $ip = $_SERVER['HTTP_CF_CONNECTING_IP'];
    }
    
    return filter_var($ip, FILTER_VALIDATE_IP) ? $ip : '0.0.0.0';
}
}

/**
 * Sanitize input string
 * 
 * @param string $input Raw input
 * @return string Sanitized input
 */
if (!function_exists('sanitize_input')) {
function sanitize_input($input) {
    if ($input === null) {
        return '';
    }
    
    // Remove null bytes
    $input = str_replace(chr(0), '', $input);
    
    // Strip tags and encode special characters
    $input = htmlspecialchars(strip_tags(trim($input)), ENT_QUOTES, 'UTF-8');
    
    return $input;
}
}

/**
 * Validate integer input
 * 
 * @param mixed $input Input value
 * @param int $min Minimum value
 * @param int $max Maximum value
 * @return int|false Validated integer or false
 */
if (!function_exists('validate_int')) {
function validate_int($input, $min = PHP_INT_MIN, $max = PHP_INT_MAX) {
    $value = filter_var($input, FILTER_VALIDATE_INT);
    
    if ($value === false) {
        return false;
    }
    
    if ($value < $min || $value > $max) {
        return false;
    }
    
    return $value;
}
}

/**
 * Validate email address
 * 
 * @param string $email Email address
 * @return string|false Validated email or false
 */
if (!function_exists('validate_email')) {
function validate_email($email) {
    return filter_var($email, FILTER_VALIDATE_EMAIL);
}
}

/**
 * Validate South African ID number
 * 
 * @param string $id_number ID number
 * @return bool True if valid
 */
if (!function_exists('validate_sa_id')) {
function validate_sa_id($id_number) {
    // Remove spaces and dashes
    $id = preg_replace('/[\s\-]/', '', $id_number);
    
    // Check length
    if (strlen($id) !== 13) {
        return false;
    }
    
    // Check if all digits
    if (!ctype_digit($id)) {
        return false;
    }
    
    // Validate date of birth (first 6 digits)
    $year = substr($id, 0, 2);
    $month = substr($id, 2, 2);
    $day = substr($id, 4, 2);
    
    if ($month < 1 || $month > 12 || $day < 1 || $day > 31) {
        return false;
    }
    
    // Luhn algorithm checksum
    $sum = 0;
    for ($i = 0; $i < 12; $i++) {
        $digit = (int)$id[$i];
        if ($i % 2 === 1) {
            $digit *= 2;
            if ($digit > 9) {
                $digit = $digit - 9;
            }
        }
        $sum += $digit;
    }
    
    $checkDigit = (10 - ($sum % 10)) % 10;
    
    return $checkDigit === (int)$id[12];
}
}

/**
 * Validate file upload
 * 
 * @param array $file $_FILES array element
 * @param array $options Validation options
 * @return array ['valid' => bool, 'error' => string|null, 'sanitized_name' => string]
 */
if (!function_exists('validate_file_upload')) {
function validate_file_upload($file, $options = []) {
    // Default options
    $defaults = [
        'allowed_extensions' => ['jpg', 'jpeg', 'png', 'gif', 'pdf'],
        'allowed_mime_types' => ['image/jpeg', 'image/png', 'image/gif', 'application/pdf'],
        'max_size' => 5 * 1024 * 1024,  // 5MB
        'allow_svg' => false
    ];
    
    $options = array_merge($defaults, $options);
    
    // Check for upload errors
    if (!isset($file['error']) || is_array($file['error'])) {
        return ['valid' => false, 'error' => 'Invalid file upload'];
    }
    
    switch ($file['error']) {
        case UPLOAD_ERR_OK:
            break;
        case UPLOAD_ERR_INI_SIZE:
        case UPLOAD_ERR_FORM_SIZE:
            return ['valid' => false, 'error' => 'File too large'];
        case UPLOAD_ERR_NO_FILE:
            return ['valid' => false, 'error' => 'No file uploaded'];
        default:
            return ['valid' => false, 'error' => 'File upload error'];
    }
    
    // Check file size
    if ($file['size'] > $options['max_size']) {
        return ['valid' => false, 'error' => 'File exceeds maximum size of ' . ($options['max_size'] / 1024 / 1024) . 'MB'];
    }
    
    // Check file extension
    $file_extension = strtolower(pathinfo($file['name'], PATHINFO_EXTENSION));
    if (!in_array($file_extension, $options['allowed_extensions'])) {
        return ['valid' => false, 'error' => 'File type not allowed. Allowed: ' . implode(', ', $options['allowed_extensions'])];
    }
    
    // Check MIME type
    $finfo = finfo_open(FILEINFO_MIME_TYPE);
    $mime_type = finfo_file($finfo, $file['tmp_name']);
    finfo_close($finfo);
    
    if (!in_array($mime_type, $options['allowed_mime_types'])) {
        return ['valid' => false, 'error' => 'Invalid file type'];
    }
    
    // Additional image checks
    if (strpos($mime_type, 'image/') === 0) {
        $image_info = getimagesize($file['tmp_name']);
        if ($image_info === false) {
            return ['valid' => false, 'error' => 'Invalid image file'];
        }
        
        // Check for SVG (potential XSS vector)
        if ($image_info['mime'] === 'image/svg+xml' && !$options['allow_svg']) {
            return ['valid' => false, 'error' => 'SVG files not allowed'];
        }
    }
    
    // Sanitize filename
    $sanitized_name = preg_replace('/[^a-zA-Z0-9_\-\.]/', '_', basename($file['name']));
    
    return [
        'valid' => true,
        'error' => null,
        'sanitized_name' => $sanitized_name,
        'mime_type' => $mime_type,
        'extension' => $file_extension
    ];
}
}

/**
 * Check rate limit
 * 
 * @param mysqli $conn Database connection
 * @param string $ip Client IP address
 * @param string $action Action being rate limited
 * @param int $max_attempts Maximum attempts allowed
 * @param int $window_seconds Time window in seconds
 * @return array ['allowed' => bool, 'message' => string, 'retry_after' => int|null]
 */
if (!function_exists('check_rate_limit')) {
function check_rate_limit($conn, $ip, $action = 'api_request', $max_attempts = 60, $window_seconds = 60) {
    // Create rate_limit table if it doesn't exist
    $create_table = "
        CREATE TABLE IF NOT EXISTS rate_limit (
            id INT AUTO_INCREMENT PRIMARY KEY,
            ip_address VARCHAR(45) NOT NULL,
            action VARCHAR(50) NOT NULL,
            attempt_time DATETIME NOT NULL,
            INDEX idx_ip_action_time (ip_address, action, attempt_time)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ";
    $conn->query($create_table);
    
    // Clean old entries
    $cleanup_stmt = $conn->prepare("DELETE FROM rate_limit WHERE attempt_time < DATE_SUB(NOW(), INTERVAL ? SECOND)");
    $cleanup_window = $window_seconds * 2;
    $cleanup_stmt->bind_param("i", $cleanup_window);
    $cleanup_stmt->execute();
    $cleanup_stmt->close();
    
    // Count recent attempts
    $count_stmt = $conn->prepare("
        SELECT COUNT(*) as attempt_count,
               MIN(attempt_time) as first_attempt
        FROM rate_limit 
        WHERE ip_address = ? 
          AND action = ? 
          AND attempt_time > DATE_SUB(NOW(), INTERVAL ? SECOND)
    ");
    $count_stmt->bind_param("ssi", $ip, $action, $window_seconds);
    $count_stmt->execute();
    $result = $count_stmt->get_result();
    $row = $result->fetch_assoc();
    $count_stmt->close();
    
    $attempt_count = (int)$row['attempt_count'];
    
    // Check if limit exceeded
    if ($attempt_count >= $max_attempts) {
        $first_attempt = new DateTime($row['first_attempt']);
        $now = new DateTime();
        $elapsed = $now->getTimestamp() - $first_attempt->getTimestamp();
        $retry_after = max(1, $window_seconds - $elapsed);
        
        return [
            'allowed' => false,
            'message' => "Too many requests. Please try again in {$retry_after} seconds.",
            'retry_after' => $retry_after
        ];
    }
    
    // Log this attempt
    $log_stmt = $conn->prepare("INSERT INTO rate_limit (ip_address, action, attempt_time) VALUES (?, ?, NOW())");
    $log_stmt->bind_param("ss", $ip, $action);
    $log_stmt->execute();
    $log_stmt->close();
    
    return [
        'allowed' => true,
        'message' => 'OK',
        'remaining' => $max_attempts - $attempt_count - 1
    ];
}
}

/**
 * Validate authentication token
 * 
 * @param mysqli $conn Database connection
 * @param string $token Authentication token
 * @param string|null $required_role Required role
 * @return array|false User data or false if invalid
 */
if (!function_exists('validate_auth_token')) {
function validate_auth_token($conn, $token, $required_role = null) {
    // Sanitize token
    $token = preg_replace('/[^a-zA-Z0-9]/', '', $token);
    
    if (empty($token)) {
        return false;
    }
    
    // Query auth_tokens table
    $stmt = $conn->prepare("
        SELECT user_id, user_role, created_at, expires_at 
        FROM auth_tokens 
        WHERE token = ? 
          AND expires_at > NOW()
          AND is_active = 1
    ");
    
    $stmt->bind_param("s", $token);
    $stmt->execute();
    $result = $stmt->get_result();
    
    if ($result->num_rows === 0) {
        $stmt->close();
        return false;
    }
    
    $user = $result->fetch_assoc();
    $stmt->close();
    
    // Check role if specified
    if ($required_role !== null && $user['user_role'] !== $required_role) {
        return false;
    }
    
    // Update last_used timestamp
    $update_stmt = $conn->prepare("UPDATE auth_tokens SET last_used = NOW() WHERE token = ?");
    $update_stmt->bind_param("s", $token);
    $update_stmt->execute();
    $update_stmt->close();
    
    return $user;
}
}

/**
 * Log security event
 * 
 * @param string $event_type Type of security event
 * @param string $description Description of event
 * @param array $metadata Additional metadata
 */
if (!function_exists('log_security_event')) {
function log_security_event($event_type, $description, $metadata = []) {
    // Get database connection
    global $conn;
    
    if (!$conn) {
        return;  // Silently fail if no connection
    }
    
    // Create security_log table if it doesn't exist
    $create_table = "
        CREATE TABLE IF NOT EXISTS security_log (
            id INT AUTO_INCREMENT PRIMARY KEY,
            event_type VARCHAR(50) NOT NULL,
            description TEXT,
            ip_address VARCHAR(45),
            user_id INT DEFAULT NULL,
            metadata JSON,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_event_type (event_type),
            INDEX idx_ip_address (ip_address),
            INDEX idx_created_at (created_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ";
    $conn->query($create_table);
    
    // Prepare metadata
    $metadata_json = json_encode($metadata);
    $ip = get_client_ip();
    $user_id = $metadata['user_id'] ?? null;
    
    // Insert log entry
    $stmt = $conn->prepare("
        INSERT INTO security_log (event_type, description, ip_address, user_id, metadata) 
        VALUES (?, ?, ?, ?, ?)
    ");
    
    $stmt->bind_param("sssis", $event_type, $description, $ip, $user_id, $metadata_json);
    $stmt->execute();
    $stmt->close();
}
}

/**
 * Generate CSRF token
 * 
 * @return string CSRF token
 */
if (!function_exists('generate_csrf_token')) {
function generate_csrf_token() {
    if (session_status() === PHP_SESSION_NONE) {
        session_start();
    }
    
    if (!isset($_SESSION['csrf_token'])) {
        $_SESSION['csrf_token'] = bin2hex(random_bytes(32));
    }
    
    return $_SESSION['csrf_token'];
}
}

/**
 * Verify CSRF token
 * 
 * @param string $token Token to verify
 * @return bool True if valid
 */
if (!function_exists('verify_csrf_token')) {
function verify_csrf_token($token) {
    if (session_status() === PHP_SESSION_NONE) {
        session_start();
    }
    
    if (!isset($_SESSION['csrf_token'])) {
        return false;
    }
    
    return hash_equals($_SESSION['csrf_token'], $token);
}
}

/**
 * Create auth_tokens table if it doesn't exist
 */
if (!function_exists('ensure_auth_tokens_table')) {
function ensure_auth_tokens_table($conn) {
    $create_table = "
        CREATE TABLE IF NOT EXISTS auth_tokens (
            id INT AUTO_INCREMENT PRIMARY KEY,
            token VARCHAR(64) NOT NULL UNIQUE,
            user_id INT NOT NULL,
            user_role VARCHAR(50) NOT NULL,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            expires_at DATETIME NOT NULL,
            last_used DATETIME DEFAULT NULL,
            is_active TINYINT(1) DEFAULT 1,
            INDEX idx_token (token),
            INDEX idx_user_id (user_id),
            INDEX idx_expires_at (expires_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ";
    
    $conn->query($create_table);
}
}

// Initialize auth_tokens table on load
if (isset($conn) && $conn instanceof mysqli) {
    ensure_auth_tokens_table($conn);
}

?>
