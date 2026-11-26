<?php
/**
 * Token Revocation Endpoint
 * 
 * Uses centralized auth_token_manager.php revokeToken() function
 * Called when:
 * - Session validation fails
 * - User logs out
 * - MTL API returns 401
 * - Security violation detected
 */

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

// Handle preflight OPTIONS request
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

// Only accept POST requests
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode([
        'success' => false,
        'error' => 'Method not allowed'
    ]);
    exit();
}

// Include centralized token manager and database connection
require_once __DIR__ . '/auth_token_manager.php';
require_once __DIR__ . '/connection.php';

/**
 * Extract Bearer token from Authorization header
 */
function getBearerToken() {
    $headers = getallheaders();
    
    if (isset($headers['Authorization'])) {
        $authHeader = $headers['Authorization'];
        
        // Check if it starts with 'Bearer '
        if (preg_match('/Bearer\s+(.*)$/i', $authHeader, $matches)) {
            return $matches[1];
        }
    }
    
    return null;
}

try {
    // Get token from Authorization header
    $token = getBearerToken();
    
    if (!$token) {
        http_response_code(401);
        echo json_encode([
            'success' => false,
            'error' => 'Missing or invalid Authorization header'
        ]);
        exit();
    }
    
    // Get reason from request body (optional)
    $input = json_decode(file_get_contents('php://input'), true);
    $reason = $input['reason'] ?? 'manual_revoke';
    
    // ✅ Use centralized revokeToken() function from auth_token_manager.php
    $success = revokeToken($conn, $token);
    
    if ($success) {
        http_response_code(200);
        echo json_encode([
            'success' => true,
            'message' => 'Token revoked successfully',
            'reason' => $reason
        ]);
        
        error_log("[REVOKE_TOKEN] ✅ Token revoked successfully. Reason: $reason");
        
    } else {
        // Token already revoked or not found (still return 200)
        http_response_code(200);
        echo json_encode([
            'success' => false,
            'message' => 'Token already revoked or not found',
            'reason' => $reason
        ]);
        
        error_log("[REVOKE_TOKEN] ⚠️ Token not found or already revoked. Reason: $reason");
    }
    
} catch (Exception $e) {
    error_log("[REVOKE_TOKEN] Error: " . $e->getMessage());
    
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'error' => 'Server error'
    ]);
}

$conn->close();
?>
