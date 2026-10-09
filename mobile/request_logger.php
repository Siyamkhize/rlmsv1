<?php
/**
 * Request Logger - Comprehensive Request Monitoring and Analysis
 * 
 * Provides:
 * - Real-time request tracking
 * - Rate limit monitoring
 * - Security event logging
 * - Performance monitoring
 * - Attack pattern detection
 * 
 * @version 1.0.0
 * @security CRITICAL - Monitors all incoming requests for analysis
 */

// Prevent direct access
if (!defined('REQUEST_LOGGER_LOADED')) {
    define('REQUEST_LOGGER_LOADED', true);
}

/**
 * Log incoming request details
 * Call this at the beginning of every endpoint
 * 
 * @param mysqli $conn Database connection
 * @param string $endpoint_name Name of the endpoint (e.g., 'save_manual_clockin')
 * @param array $additional_data Additional data to log
 * @return int Log entry ID for correlation
 */
if (!function_exists('log_request')) {
function log_request($conn, $endpoint_name, $additional_data = []) {
    try {
        // Create request_log table if it doesn't exist
        create_request_log_table($conn);
        
        // Collect request data
        $request_data = [
            'endpoint' => $endpoint_name,
            'method' => $_SERVER['REQUEST_METHOD'] ?? 'UNKNOWN',
            'ip_address' => get_client_ip(),
            'user_agent' => $_SERVER['HTTP_USER_AGENT'] ?? '',
            'referer' => $_SERVER['HTTP_REFERER'] ?? '',
            'request_uri' => $_SERVER['REQUEST_URI'] ?? '',
            'query_string' => $_SERVER['QUERY_STRING'] ?? '',
            'content_type' => $_SERVER['CONTENT_TYPE'] ?? '',
            'content_length' => $_SERVER['CONTENT_LENGTH'] ?? 0,
            'request_time' => $_SERVER['REQUEST_TIME_FLOAT'] ?? microtime(true),
            'additional_data' => json_encode($additional_data)
        ];
        
        // Insert log entry
        $stmt = $conn->prepare("
            INSERT INTO request_log 
            (endpoint, method, ip_address, user_agent, referer, request_uri, query_string, 
             content_type, content_length, request_time, additional_data, created_at) 
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())
        ");
        
        $stmt->bind_param(
            "sssssssssss",
            $request_data['endpoint'],
            $request_data['method'],
            $request_data['ip_address'],
            $request_data['user_agent'],
            $request_data['referer'],
            $request_data['request_uri'],
            $request_data['query_string'],
            $request_data['content_type'],
            $request_data['content_length'],
            $request_data['request_time'],
            $request_data['additional_data']
        );
        
        $stmt->execute();
        $log_id = $conn->insert_id;
        $stmt->close();
        
        // Check for suspicious patterns
        check_request_patterns($conn, $request_data);
        
        return $log_id;
        
    } catch (Exception $e) {
        error_log("Request logging error: " . $e->getMessage());
        return 0; // Don't fail the request if logging fails
    }
}
}

/**
 * Log request completion with response details
 * 
 * @param mysqli $conn Database connection
 * @param int $log_id Log entry ID from log_request()
 * @param int $response_code HTTP response code
 * @param string $status 'success' or 'error'
 * @param string $message Response message
 * @param float $execution_time Execution time in seconds
 */
if (!function_exists('log_request_completion')) {
function log_request_completion($conn, $log_id, $response_code = 200, $status = 'success', $message = '', $execution_time = null) {
    try {
        if ($log_id <= 0) return;
        
        if ($execution_time === null) {
            $execution_time = microtime(true) - $_SERVER['REQUEST_TIME_FLOAT'];
        }
        
        $stmt = $conn->prepare("
            UPDATE request_log 
            SET response_code = ?, status = ?, response_message = ?, 
                execution_time = ?, completed_at = NOW()
            WHERE id = ?
        ");
        
        $stmt->bind_param("issdi", $response_code, $status, $message, $execution_time, $log_id);
        $stmt->execute();
        $stmt->close();
        
        // Log slow requests (> 5 seconds)
        if ($execution_time > 5.0) {
            log_security_event('SLOW_REQUEST', 
                "Slow request detected: {$_SERVER['REQUEST_URI']} took {$execution_time}s",
                ['execution_time' => $execution_time, 'log_id' => $log_id]
            );
        }
        
    } catch (Exception $e) {
        error_log("Request completion logging error: " . $e->getMessage());
    }
}
}

/**
 * Create request log table
 */
if (!function_exists('create_request_log_table')) {
function create_request_log_table($conn) {
    $create_table = "
        CREATE TABLE IF NOT EXISTS request_log (
            id INT AUTO_INCREMENT PRIMARY KEY,
            endpoint VARCHAR(100) NOT NULL,
            method VARCHAR(10) NOT NULL,
            ip_address VARCHAR(45) NOT NULL,
            user_agent TEXT,
            referer TEXT,
            request_uri TEXT,
            query_string TEXT,
            content_type VARCHAR(100),
            content_length INT DEFAULT 0,
            request_time DECIMAL(16,6),
            additional_data JSON,
            response_code INT DEFAULT NULL,
            status ENUM('pending', 'success', 'error') DEFAULT 'pending',
            response_message TEXT,
            execution_time DECIMAL(10,6) DEFAULT NULL,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            completed_at DATETIME DEFAULT NULL,
            
            INDEX idx_endpoint (endpoint),
            INDEX idx_ip_address (ip_address),
            INDEX idx_created_at (created_at),
            INDEX idx_status (status),
            INDEX idx_response_code (response_code),
            INDEX idx_execution_time (execution_time)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ";
    
    $conn->query($create_table);
}
}

/**
 * Check for suspicious request patterns
 * 
 * @param mysqli $conn Database connection
 * @param array $request_data Request data
 */
if (!function_exists('check_request_patterns')) {
function check_request_patterns($conn, $request_data) {
    $ip = $request_data['ip_address'];
    $endpoint = $request_data['endpoint'];
    
    // Check for rapid requests from same IP (last 1 minute)
    $stmt = $conn->prepare("
        SELECT COUNT(*) as request_count
        FROM request_log 
        WHERE ip_address = ? 
          AND created_at > DATE_SUB(NOW(), INTERVAL 1 MINUTE)
    ");
    $stmt->bind_param("s", $ip);
    $stmt->execute();
    $result = $stmt->get_result();
    $row = $result->fetch_assoc();
    $stmt->close();
    
    $request_count = $row['request_count'];
    
    // Alert for suspicious patterns
    if ($request_count > 50) { // More than 50 requests per minute
        log_security_event('RAPID_REQUESTS', 
            "Rapid requests detected from IP: $ip ($request_count requests/minute)",
            [
                'ip' => $ip,
                'endpoint' => $endpoint,
                'request_count' => $request_count,
                'time_window' => '1 minute'
            ]
        );
    }
    
    // Check for failed authentication attempts
    $stmt = $conn->prepare("
        SELECT COUNT(*) as failed_count
        FROM request_log 
        WHERE ip_address = ? 
          AND response_code = 401
          AND created_at > DATE_SUB(NOW(), INTERVAL 5 MINUTE)
    ");
    $stmt->bind_param("s", $ip);
    $stmt->execute();
    $result = $stmt->get_result();
    $row = $result->fetch_assoc();
    $stmt->close();
    
    $failed_count = $row['failed_count'];
    
    if ($failed_count > 5) { // More than 5 failed auth attempts in 5 minutes
        log_security_event('BRUTE_FORCE_ATTEMPT', 
            "Potential brute force attempt from IP: $ip ($failed_count failed attempts)",
            [
                'ip' => $ip,
                'failed_count' => $failed_count,
                'time_window' => '5 minutes'
            ]
        );
    }
}
}

/**
 * Get request statistics for monitoring dashboard
 * 
 * @param mysqli $conn Database connection
 * @param string $timeframe '1hour', '1day', '1week'
 * @return array Statistics
 */
if (!function_exists('get_request_statistics')) {
function get_request_statistics($conn, $timeframe = '1hour') {
    $interval_map = [
        '1hour' => '1 HOUR',
        '1day' => '1 DAY',
        '1week' => '7 DAY'
    ];
    
    $interval = $interval_map[$timeframe] ?? '1 HOUR';
    
    try {
        // Total requests
        $stmt = $conn->prepare("
            SELECT 
                COUNT(*) as total_requests,
                COUNT(DISTINCT ip_address) as unique_ips,
                AVG(execution_time) as avg_execution_time,
                MAX(execution_time) as max_execution_time,
                COUNT(CASE WHEN response_code >= 400 THEN 1 END) as error_count,
                COUNT(CASE WHEN response_code = 401 THEN 1 END) as auth_failures,
                COUNT(CASE WHEN response_code = 429 THEN 1 END) as rate_limited
            FROM request_log 
            WHERE created_at > DATE_SUB(NOW(), INTERVAL $interval)
        ");
        
        $stmt->execute();
        $result = $stmt->get_result();
        $stats = $result->fetch_assoc();
        $stmt->close();
        
        // Top endpoints
        $stmt = $conn->prepare("
            SELECT endpoint, COUNT(*) as request_count
            FROM request_log 
            WHERE created_at > DATE_SUB(NOW(), INTERVAL $interval)
            GROUP BY endpoint
            ORDER BY request_count DESC
            LIMIT 10
        ");
        
        $stmt->execute();
        $result = $stmt->get_result();
        $top_endpoints = [];
        while ($row = $result->fetch_assoc()) {
            $top_endpoints[] = $row;
        }
        $stmt->close();
        
        // Top IPs
        $stmt = $conn->prepare("
            SELECT ip_address, COUNT(*) as request_count
            FROM request_log 
            WHERE created_at > DATE_SUB(NOW(), INTERVAL $interval)
            GROUP BY ip_address
            ORDER BY request_count DESC
            LIMIT 10
        ");
        
        $stmt->execute();
        $result = $stmt->get_result();
        $top_ips = [];
        while ($row = $result->fetch_assoc()) {
            $top_ips[] = $row;
        }
        $stmt->close();
        
        return [
            'timeframe' => $timeframe,
            'summary' => $stats,
            'top_endpoints' => $top_endpoints,
            'top_ips' => $top_ips,
            'generated_at' => date('Y-m-d H:i:s')
        ];
        
    } catch (Exception $e) {
        error_log("Request statistics error: " . $e->getMessage());
        return ['error' => $e->getMessage()];
    }
}
}

/**
 * Clean old request logs (keep last 30 days)
 * Call this periodically via cron or manual cleanup
 * 
 * @param mysqli $conn Database connection
 * @return int Number of records deleted
 */
if (!function_exists('cleanup_old_request_logs')) {
function cleanup_old_request_logs($conn) {
    try {
        $stmt = $conn->prepare("
            DELETE FROM request_log 
            WHERE created_at < DATE_SUB(NOW(), INTERVAL 30 DAY)
        ");
        
        $stmt->execute();
        $deleted_count = $conn->affected_rows;
        $stmt->close();
        
        error_log("Request log cleanup: Deleted $deleted_count old records");
        return $deleted_count;
        
    } catch (Exception $e) {
        error_log("Request log cleanup error: " . $e->getMessage());
        return 0;
    }
}
}

// Auto-cleanup on load (1% chance)
if (isset($conn) && $conn instanceof mysqli && mt_rand(1, 100) === 1) {
    cleanup_old_request_logs($conn);
}

?>