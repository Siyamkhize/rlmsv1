<?php
/**
 * Authentication Middleware for RLMSS API
 * 
 * Validates Bearer tokens on API requests and enforces role-based access control
 * 
 * Usage:
 *   require_once('auth_middleware.php');
 *   $auth = validateAuthToken($conn);
 *   if (!$auth['valid']) {
 *       http_response_code(401);
 *       echo json_encode(['error' => $auth['reason']]);
 *       exit;
 *   }
 * 
 * @author RLMSS Development Team
 * @version 1.0
 * @date 2026-10-14
 */

/**
 * Validates the authentication token from the Authorization header
 * 
 * @param mysqli $conn Database connection
 * @return array ['valid' => bool, 'user_id' => string|null, 'user_role' => string|null, 'reason' => string|null]
 */
function validateAuthToken($conn) {
    // Get Authorization header
    $headers = getallheaders();
    
    // Check if Authorization header exists
    if (!isset($headers['Authorization']) && !isset($headers['authorization'])) {
        return [
            'valid' => false,
            'reason' => 'Missing Authorization header',
            'user_id' => null,
            'user_role' => null
        ];
    }
    
    // Get the authorization header (case-insensitive)
    $auth_header = $headers['Authorization'] ?? $headers['authorization'] ?? '';
    
    // Extract Bearer token
    if (!preg_match('/Bearer\s+(.*)$/i', $auth_header, $matches)) {
        return [
            'valid' => false,
            'reason' => 'Invalid Authorization header format. Expected: Bearer <token>',
            'user_id' => null,
            'user_role' => null
        ];
    }
    
    $token = trim($matches[1]);
    
    // Check if token is empty
    if (empty($token)) {
        return [
            'valid' => false,
            'reason' => 'Empty authentication token',
            'user_id' => null,
            'user_role' => null
        ];
    }
    
    // Hash the token to match against database
    $token_hash = hash('sha256', $token);
    
    // Query the database for valid token
    $stmt = $conn->prepare("
        SELECT user_id, user_role, expires_at 
        FROM auth_tokens 
        WHERE token_hash = ? 
        AND expires_at > NOW()
    ");
    
    if (!$stmt) {
        return [
            'valid' => false,
            'reason' => 'Database error: ' . $conn->error,
            'user_id' => null,
            'user_role' => null
        ];
    }
    
    $stmt->bind_param("s", $token_hash);
    $stmt->execute();
    $result = $stmt->get_result();
    
    // Check if token exists and is valid
    if ($result->num_rows === 0) {
        return [
            'valid' => false,
            'reason' => 'Invalid or expired authentication token',
            'user_id' => null,
            'user_role' => null
        ];
    }
    
    // Token is valid
    $row = $result->fetch_assoc();
    $stmt->close();
    
    return [
        'valid' => true,
        'user_id' => $row['user_id'],
        'user_role' => $row['user_role'],
        'reason' => null
    ];
}

/**
 * Validates that the authenticated user has one of the required roles
 * 
 * @param array $auth_result Result from validateAuthToken()
 * @param array $allowed_roles Array of allowed role names
 * @return array ['authorized' => bool, 'reason' => string|null]
 */
function checkRoleAuthorization($auth_result, $allowed_roles) {
    if (!$auth_result['valid']) {
        return [
            'authorized' => false,
            'reason' => 'User not authenticated'
        ];
    }
    
    $user_role = $auth_result['user_role'];
    
    // Check if user's role is in the allowed list
    if (!in_array($user_role, $allowed_roles)) {
        return [
            'authorized' => false,
            'reason' => "Access denied. Required roles: " . implode(', ', $allowed_roles)
        ];
    }
    
    return [
        'authorized' => true,
        'reason' => null
    ];
}

/**
 * Sends a 401 Unauthorized response and exits
 * 
 * @param string $message Error message
 */
function sendUnauthorizedResponse($message = 'Unauthorized') {
    http_response_code(401);
    header('Content-Type: application/json');
    echo json_encode([
        'success' => false,
        'error' => $message
    ]);
    exit;
}

/**
 * Sends a 403 Forbidden response and exits
 * 
 * @param string $message Error message
 */
function sendForbiddenResponse($message = 'Forbidden') {
    http_response_code(403);
    header('Content-Type: application/json');
    echo json_encode([
        'success' => false,
        'error' => $message
    ]);
    exit;
}

/**
 * Complete authentication and authorization check
 * Returns auth result if successful, sends error response and exits if not
 * 
 * @param mysqli $conn Database connection
 * @param array|null $allowed_roles Array of allowed roles, or null to skip role check
 * @return array Auth result with user_id and user_role
 */
function requireAuth($conn, $allowed_roles = null) {
    // Validate token
    $auth = validateAuthToken($conn);
    
    if (!$auth['valid']) {
        sendUnauthorizedResponse($auth['reason']);
    }
    
    // Check role authorization if roles specified
    if ($allowed_roles !== null) {
        $authz = checkRoleAuthorization($auth, $allowed_roles);
        
        if (!$authz['authorized']) {
            sendForbiddenResponse($authz['reason']);
        }
    }
    
    return $auth;
}

/**
 * Logs authentication events for security monitoring
 * 
 * @param mysqli $conn Database connection
 * @param string $event_type Type of event (e.g., 'login', 'token_validation', 'unauthorized_access')
 * @param string|null $user_id User ID if available
 * @param string|null $user_role User role if available
 * @param string|null $ip_address Client IP address
 * @param string|null $details Additional details about the event
 */
function logAuthEvent($conn, $event_type, $user_id = null, $user_role = null, $ip_address = null, $details = null) {
    // Get IP address if not provided
    if ($ip_address === null) {
        $ip_address = $_SERVER['REMOTE_ADDR'] ?? 'unknown';
    }
    
    // Get request URI
    $request_uri = $_SERVER['REQUEST_URI'] ?? 'unknown';
    
    // Insert into auth_logs table (create this table if it doesn't exist)
    $stmt = $conn->prepare("
        INSERT INTO auth_logs 
        (event_type, user_id, user_role, ip_address, request_uri, details, created_at) 
        VALUES (?, ?, ?, ?, ?, ?, NOW())
    ");
    
    if ($stmt) {
        $stmt->bind_param("ssssss", $event_type, $user_id, $user_role, $ip_address, $request_uri, $details);
        $stmt->execute();
        $stmt->close();
    }
}

/**
 * Creates the auth_logs table if it doesn't exist
 * Call this during system setup/migration
 * 
 * @param mysqli $conn Database connection
 * @return bool Success status
 */
function createAuthLogsTable($conn) {
    $sql = "
    CREATE TABLE IF NOT EXISTS auth_logs (
        log_id INT AUTO_INCREMENT PRIMARY KEY,
        event_type VARCHAR(50) NOT NULL,
        user_id VARCHAR(50),
        user_role VARCHAR(50),
        ip_address VARCHAR(45),
        request_uri VARCHAR(255),
        details TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_event_type (event_type),
        INDEX idx_user_id (user_id),
        INDEX idx_created_at (created_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ";
    
    return $conn->query($sql);
}

/**
 * Revokes all tokens for a specific user
 * Useful for logout or security lockout
 * 
 * @param mysqli $conn Database connection
 * @param string $user_id User ID
 * @param string $user_role User role
 * @return bool Success status
 */
function revokeUserTokens($conn, $user_id, $user_role) {
    $stmt = $conn->prepare("
        DELETE FROM auth_tokens 
        WHERE user_id = ? AND user_role = ?
    ");
    
    if (!$stmt) {
        return false;
    }
    
    $stmt->bind_param("ss", $user_id, $user_role);
    $success = $stmt->execute();
    $stmt->close();
    
    return $success;
}

/**
 * Cleans up expired tokens from the database
 * Should be called periodically (e.g., via cron job)
 * 
 * @param mysqli $conn Database connection
 * @return int Number of tokens deleted
 */
function cleanupExpiredTokens($conn) {
    $result = $conn->query("
        DELETE FROM auth_tokens 
        WHERE expires_at < NOW()
    ");
    
    if ($result) {
        return $conn->affected_rows;
    }
    
    return 0;
}

?>
