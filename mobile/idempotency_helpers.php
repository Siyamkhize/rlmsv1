<?php
/**
 * Idempotency helpers for offline-first mobile synchronization
 * LAST UPDATED: 2026/11/03
 * 
 * These functions implement proper idempotency handling for mobile apps that
 * generate keys at tap time and replay them after network connectivity returns.
 */

/**
 * Begin idempotency check - call at start of endpoint processing
 * 
 * @param mysqli $conn Database connection
 * @param int $userId User ID from authentication
 * @param string $action Action type (e.g., 'clock_in', 'clock_out')  
 * @param string $key UUID idempotency key from app (generated at tap time)
 * @return array|null Returns null for first-time processing, array with stored response for duplicates
 */
function idem_begin(mysqli $conn, int $userId, string $action, string $key): ?array {
    $stmt = $conn->prepare(
        "INSERT INTO idempotency_keys (idem_key, user_id, action_type, expires_at)
         VALUES (?, ?, ?, DATE_ADD(NOW(), INTERVAL 7 DAY))"
    );
    $stmt->bind_param("sis", $key, $userId, $action);
    
    try {
        $stmt->execute();
        return null; // First time: proceed with processing
    } catch (mysqli_sql_exception $e) {
        if ($e->getCode() !== 1062) {
            throw $e; // Not a duplicate: real error
        }
    }
    
    // Duplicate key: return what we stored previously
    $q = $conn->prepare(
        "SELECT status, response_code, response_body
         FROM idempotency_keys 
         WHERE user_id = ? AND idem_key = ?"
    );
    $q->bind_param("is", $userId, $key);
    $q->execute();
    return $q->get_result()->fetch_assoc();
}

/**
 * Finish idempotency - call after successful processing
 * 
 * @param mysqli $conn Database connection
 * @param int $userId User ID
 * @param string $key Idempotency key
 * @param int $code HTTP response code
 * @param string $body Response body JSON
 */
function idem_finish(mysqli $conn, int $userId, string $key, int $code, string $body): void {
    $stmt = $conn->prepare(
        "UPDATE idempotency_keys
         SET status = 'done', response_code = ?, response_body = ?
         WHERE user_id = ? AND idem_key = ?"
    );
    $stmt->bind_param("isis", $code, $body, $userId, $key);
    $stmt->execute();
}

/**
 * Abort idempotency - call if processing fails and should be retryable
 * 
 * @param mysqli $conn Database connection
 * @param int $userId User ID
 * @param string $key Idempotency key
 */
function idem_abort(mysqli $conn, int $userId, string $key): void {
    $stmt = $conn->prepare(
        "DELETE FROM idempotency_keys 
         WHERE user_id = ? AND idem_key = ? AND status = 'processing'"
    );
    $stmt->bind_param("is", $userId, $key);
    $stmt->execute();
}

/**
 * Validate client timestamp to prevent time abuse
 * 
 * @param string $clientTimestamp ISO 8601 timestamp from client
 * @param int $maxHoursOld Maximum age in hours (default 72 = 3 days)
 * @return array ['valid' => bool, 'timestamp' => DateTime|null, 'error' => string|null]
 */
function validate_client_timestamp(string $clientTimestamp, int $maxHoursOld = 72): array {
    try {
        $clientTime = new DateTime($clientTimestamp, new DateTimeZone('UTC'));
        $now = new DateTime('now', new DateTimeZone('UTC'));
        
        // Reject future timestamps (allow 5 minutes clock skew)
        if ($clientTime > $now->add(new DateInterval('PT5M'))) {
            return ['valid' => false, 'timestamp' => null, 'error' => 'Timestamp in future'];
        }
        
        // Reject very old timestamps
        $maxAge = $now->sub(new DateInterval("PT{$maxHoursOld}H"));
        if ($clientTime < $maxAge) {
            return ['valid' => false, 'timestamp' => null, 'error' => 'Timestamp too old'];
        }
        
        return ['valid' => true, 'timestamp' => $clientTime, 'error' => null];
        
    } catch (Exception $e) {
        return ['valid' => false, 'timestamp' => null, 'error' => 'Invalid timestamp format'];
    }
}

/**
 * Check if idempotency key format is valid (supports both UUID v4 and secure tokens)
 * 
 * @param string $key Idempotency key to validate
 * @return bool True if valid format
 */
function validate_idempotency_key(string $key): bool {
    // Accept UUID v4 format (backward compatibility)
    if (preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i', $key) === 1) {
        return true;
    }
    
    // Accept new secure token format (clk_[32 hex chars])
    if (preg_match('/^clk_[a-f0-9]{32}$/', $key) === 1) {
        return true;
    }
    
    return false;
}
?>