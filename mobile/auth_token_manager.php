<?php
/**
 * Auth Token Manager
 * 
 * Centralized token management with automatic cleanup and validation
 * This handles token creation, validation, revocation, and cleanup
 */

require_once 'connection.php';

/**
 * Generate a cryptographically secure random token
 */
function generateSecureToken($length = 64) {
    return bin2hex(random_bytes($length / 2));
}

/**
 * Revoke all existing tokens for a user
 * Called automatically before creating a new token on login
 */
function revokeAllUserTokens($conn, $user_id, $user_role) {
    $stmt = $conn->prepare("
        UPDATE auth_tokens 
        SET revoked_at = NOW() 
        WHERE user_id = ? 
          AND user_role = ? 
          AND revoked_at IS NULL
    ");
    
    if ($stmt) {
        $stmt->bind_param("ss", $user_id, $user_role);
        $stmt->execute();
        $affected = $stmt->affected_rows;
        $stmt->close();
        
        error_log("[AUTH_TOKEN] Revoked $affected existing tokens for user $user_id ($user_role)");
        return $affected;
    }
    
    return 0;
}

/**
 * Delete expired tokens (cleanup)
 * Run this periodically to keep the table clean
 */
function deleteExpiredTokens($conn) {
    $stmt = $conn->prepare("
        DELETE FROM auth_tokens 
        WHERE expires_at < NOW()
    ");
    
    if ($stmt) {
        $stmt->execute();
        $affected = $stmt->affected_rows;
        $stmt->close();
        
        error_log("[AUTH_TOKEN] Deleted $affected expired tokens");
        return $affected;
    }
    
    return 0;
}

/**
 * Delete revoked tokens older than a certain time
 * Keep revoked tokens for audit purposes, but clean up old ones
 */
function deleteOldRevokedTokens($conn, $days = 30) {
    $stmt = $conn->prepare("
        DELETE FROM auth_tokens 
        WHERE revoked_at IS NOT NULL 
          AND revoked_at < DATE_SUB(NOW(), INTERVAL ? DAY)
    ");
    
    if ($stmt) {
        $stmt->bind_param("i", $days);
        $stmt->execute();
        $affected = $stmt->affected_rows;
        $stmt->close();
        
        error_log("[AUTH_TOKEN] Deleted $affected old revoked tokens (older than $days days)");
        return $affected;
    }
    
    return 0;
}

/**
 * Create or update an auth token for a user
 * This is the main function to call after successful login
 * 
 * @param mysqli $conn Database connection
 * @param string $user_id User identifier (email or ID)
 * @param string $user_role User role (sdp, facilitator, assessor, etc.)
 * @param int $expires_hours Token expiry in hours (default 7 days = 168 hours)
 * @return array ['success' => bool, 'token' => string, 'expires_at' => string, 'message' => string]
 */
function createAuthToken($conn, $user_id, $user_role, $expires_hours = 168) {
    error_log("[AUTH_TOKEN] Creating token for user $user_id ($user_role)");
    
    // Step 1: Clean up expired tokens (system maintenance)
    deleteExpiredTokens($conn);
    
    // Step 2: Revoke all existing tokens for this user
    // This ensures only one valid token per user at a time
    $revoked_count = revokeAllUserTokens($conn, $user_id, $user_role);
    
    // Step 3: Generate new token
    $token = generateSecureToken();
    $token_hash = hash('sha256', $token);
    $expires_at = date('Y-m-d H:i:s', time() + ($expires_hours * 3600));
    
    // Step 4: Insert new token
    $stmt = $conn->prepare("
        INSERT INTO auth_tokens 
        (user_id, user_role, token_hash, expires_at) 
        VALUES (?, ?, ?, ?)
    ");
    
    if (!$stmt) {
        error_log("[AUTH_TOKEN] ERROR: Failed to prepare statement: " . $conn->error);
        return [
            'success' => false,
            'token' => null,
            'expires_at' => null,
            'message' => 'Failed to create token: Database error'
        ];
    }
    
    $stmt->bind_param("ssss", $user_id, $user_role, $token_hash, $expires_at);
    
    if (!$stmt->execute()) {
        error_log("[AUTH_TOKEN] ERROR: Failed to insert token: " . $stmt->error);
        $stmt->close();
        return [
            'success' => false,
            'token' => null,
            'expires_at' => null,
            'message' => 'Failed to create token: Insert failed'
        ];
    }
    
    $stmt->close();
    
    error_log("[AUTH_TOKEN] ✅ Successfully created token for $user_id ($user_role). Revoked $revoked_count old tokens. Expires: $expires_at");
    
    return [
        'success' => true,
        'token' => $token,
        'expires_at' => $expires_at,
        'message' => 'Token created successfully',
        'revoked_count' => $revoked_count
    ];
}

/**
 * Validate an auth token
 * Returns user info if valid, null if invalid
 * 
 * @param mysqli $conn Database connection
 * @param string $token The raw token from client
 * @return array|null ['user_id' => string, 'user_role' => string] or null
 */
function validateAuthToken($conn, $token) {
    // Sanitize token
    $token = preg_replace('/[^a-zA-Z0-9]/', '', $token);
    
    if (empty($token)) {
        error_log("[AUTH_TOKEN] ❌ Empty token provided");
        return null;
    }
    
    // Hash token to match stored hash
    $token_hash = hash('sha256', $token);
    
    // Query database
    $stmt = $conn->prepare("
        SELECT user_id, user_role, created_at, expires_at, last_used_at
        FROM auth_tokens 
        WHERE token_hash = ? 
          AND expires_at > NOW()
          AND revoked_at IS NULL
    ");
    
    if (!$stmt) {
        error_log("[AUTH_TOKEN] ERROR: Failed to prepare validation statement: " . $conn->error);
        return null;
    }
    
    $stmt->bind_param("s", $token_hash);
    $stmt->execute();
    $result = $stmt->get_result();
    
    if ($result->num_rows === 0) {
        error_log("[AUTH_TOKEN] ❌ Invalid or expired token (hash: " . substr($token_hash, 0, 16) . "...)");
        $stmt->close();
        return null;
    }
    
    $row = $result->fetch_assoc();
    $stmt->close();
    
    // Update last_used_at timestamp
    $update_stmt = $conn->prepare("
        UPDATE auth_tokens 
        SET last_used_at = NOW() 
        WHERE token_hash = ?
    ");
    
    if ($update_stmt) {
        $update_stmt->bind_param("s", $token_hash);
        $update_stmt->execute();
        $update_stmt->close();
    }
    
    error_log("[AUTH_TOKEN] ✅ Valid token for user {$row['user_id']} ({$row['user_role']})");
    
    return [
        'user_id' => $row['user_id'],
        'user_role' => $row['user_role'],
        'created_at' => $row['created_at'],
        'expires_at' => $row['expires_at']
    ];
}

/**
 * Revoke a specific token
 * Useful for logout functionality
 */
function revokeToken($conn, $token) {
    $token = preg_replace('/[^a-zA-Z0-9]/', '', $token);
    
    if (empty($token)) {
        return false;
    }
    
    $token_hash = hash('sha256', $token);
    
    $stmt = $conn->prepare("
        UPDATE auth_tokens 
        SET revoked_at = NOW() 
        WHERE token_hash = ? 
          AND revoked_at IS NULL
    ");
    
    if ($stmt) {
        $stmt->bind_param("s", $token_hash);
        $stmt->execute();
        $success = $stmt->affected_rows > 0;
        $stmt->close();
        
        if ($success) {
            error_log("[AUTH_TOKEN] ✅ Token revoked successfully");
        } else {
            error_log("[AUTH_TOKEN] ⚠️ Token already revoked or not found");
        }
        
        return $success;
    }
    
    return false;
}

/**
 * Get token statistics for monitoring
 */
function getTokenStats($conn) {
    $stats = [];
    
    // Total tokens
    $result = $conn->query("SELECT COUNT(*) as total FROM auth_tokens");
    $stats['total'] = $result ? $result->fetch_assoc()['total'] : 0;
    
    // Valid tokens
    $result = $conn->query("
        SELECT COUNT(*) as valid 
        FROM auth_tokens 
        WHERE expires_at > NOW() 
          AND revoked_at IS NULL
    ");
    $stats['valid'] = $result ? $result->fetch_assoc()['valid'] : 0;
    
    // Expired tokens
    $result = $conn->query("
        SELECT COUNT(*) as expired 
        FROM auth_tokens 
        WHERE expires_at <= NOW() 
          AND revoked_at IS NULL
    ");
    $stats['expired'] = $result ? $result->fetch_assoc()['expired'] : 0;
    
    // Revoked tokens
    $result = $conn->query("
        SELECT COUNT(*) as revoked 
        FROM auth_tokens 
        WHERE revoked_at IS NOT NULL
    ");
    $stats['revoked'] = $result ? $result->fetch_assoc()['revoked'] : 0;
    
    return $stats;
}
