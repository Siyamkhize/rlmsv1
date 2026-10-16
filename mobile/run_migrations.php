<?php
/**
 * Database Migration Script for Security Tables
 * 
 * Run this script once during deployment to create required security tables.
 * DO NOT run this in the per-request path - it's a one-time setup operation.
 * 
 * Usage: php run_migrations.php
 */

require_once __DIR__ . '/connection.php';

echo "[MIGRATION] Starting security table migrations...\n";

try {
    // 1. Rate limiting table
    echo "[MIGRATION] Creating rate_limit table...\n";
    $conn->query("
        CREATE TABLE IF NOT EXISTS rate_limit (
            id INT AUTO_INCREMENT PRIMARY KEY,
            ip_address VARCHAR(45) NOT NULL,
            action VARCHAR(50) NOT NULL,
            attempt_time DATETIME NOT NULL,
            INDEX idx_ip_action_time (ip_address, action, attempt_time),
            INDEX idx_attempt_time (attempt_time)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ");
    echo "[MIGRATION] ✅ rate_limit table created\n";

    // 2. Security event logging table
    echo "[MIGRATION] Creating security_log table...\n";
    $conn->query("
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
            INDEX idx_created_at (created_at),
            INDEX idx_user_id (user_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ");
    echo "[MIGRATION] ✅ security_log table created\n";

    // 3. Authentication tokens table
    echo "[MIGRATION] Creating auth_tokens table...\n";
    $conn->query("
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
            INDEX idx_expires_at (expires_at),
            INDEX idx_expires_active (expires_at, is_active),
            INDEX idx_user_active (user_id, is_active)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ");
    echo "[MIGRATION] ✅ auth_tokens table created\n";

    // 4. Request monitoring table
    echo "[MIGRATION] Creating request_log table...\n";
    $conn->query("
        CREATE TABLE IF NOT EXISTS request_log (
            id INT AUTO_INCREMENT PRIMARY KEY,
            endpoint VARCHAR(100) NOT NULL,
            ip_address VARCHAR(45),
            user_id INT DEFAULT NULL,
            request_time DATETIME DEFAULT CURRENT_TIMESTAMP,
            response_code INT DEFAULT NULL,
            processing_time_ms INT DEFAULT NULL,
            metadata JSON,
            INDEX idx_endpoint_time (endpoint, request_time),
            INDEX idx_ip_time (ip_address, request_time),
            INDEX idx_response_code (response_code)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ");
    echo "[MIGRATION] ✅ request_log table created\n";

    // 5. Performance indexes for manual_clocking table (if exists)
    echo "[MIGRATION] Adding performance indexes to existing tables...\n";
    
    // Check if manual_clocking table exists before adding indexes
    $table_check = $conn->query("SHOW TABLES LIKE 'manual_clocking'");
    if ($table_check && $table_check->num_rows > 0) {
        // Add indexes if they don't exist
        $conn->query("ALTER TABLE manual_clocking ADD INDEX idx_learner_date (LearnerID, clock_date)");
        echo "[MIGRATION] ✅ Added idx_learner_date to manual_clocking\n";
    }

    // Check if manual_clocking_evidence table exists
    $evidence_check = $conn->query("SHOW TABLES LIKE 'manual_clocking_evidence'");
    if ($evidence_check && $evidence_check->num_rows > 0) {
        $conn->query("ALTER TABLE manual_clocking_evidence ADD INDEX idx_learner_date (LearnerID, clock_date)");
        $conn->query("ALTER TABLE manual_clocking_evidence ADD INDEX idx_synced (synced)");
        echo "[MIGRATION] ✅ Added performance indexes to manual_clocking_evidence\n";
    }

    echo "[MIGRATION] 🎉 All migrations completed successfully!\n";

} catch (Exception $e) {
    echo "[MIGRATION] ❌ Migration failed: " . $e->getMessage() . "\n";
    exit(1);
}

if (isset($conn)) {
    $conn->close();
}

echo "[MIGRATION] Migration script finished.\n";
?>