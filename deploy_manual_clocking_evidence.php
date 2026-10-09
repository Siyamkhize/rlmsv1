<?php
/**
 * Deploy Manual Clocking Evidence Table
 * 
 * Creates the manual_clocking_evidence table for storing signature and face photos
 * Run this once to set up the table: php deploy_manual_clocking_evidence.php
 */

require_once 'connection.php';

try {
    echo "Creating manual_clocking_evidence table...\n";
    
    $sql = "
    CREATE TABLE IF NOT EXISTS manual_clocking_evidence (
        evidence_id INT(11) NOT NULL AUTO_INCREMENT PRIMARY KEY,
        LearnerID INT(11) NOT NULL,
        clock_date DATE NOT NULL,
        
        -- Signature images (base64 encoded)
        signature_in TEXT NULL COMMENT 'Base64 signature image for clock-in',
        signature_out TEXT NULL COMMENT 'Base64 signature image for clock-out',
        
        -- Face capture images (base64 encoded)
        face_in TEXT NULL COMMENT 'Base64 face photo for clock-in',
        face_out TEXT NULL COMMENT 'Base64 face photo for clock-out',
        
        -- Timestamps
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        
        -- Indexes
        KEY idx_learner_date (LearnerID, clock_date),
        KEY idx_clock_date (clock_date),
        
        -- Unique constraint: one evidence record per learner per day
        UNIQUE KEY unique_learner_date_evidence (LearnerID, clock_date),
        
        -- Foreign key
        FOREIGN KEY (LearnerID) REFERENCES learnerdetails(LearnerID) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Evidence photos for manual clocking (signature + face)'
    ";
    
    if ($conn->query($sql)) {
        echo "✓ Table 'manual_clocking_evidence' created successfully\n";
    } else {
        throw new Exception("Error creating table: " . $conn->error);
    }
    
    // Check if manual_clocking table exists
    $result = $conn->query("SHOW TABLES LIKE 'manual_clocking'");
    if ($result && $result->num_rows > 0) {
        echo "✓ Table 'manual_clocking' already exists\n";
        
        // Check structure
        $result = $conn->query("DESC manual_clocking");
        echo "\nmanual_clocking table structure:\n";
        while ($row = $result->fetch_assoc()) {
            echo "  - {$row['Field']}: {$row['Type']}\n";
        }
    } else {
        echo "⚠ Warning: 'manual_clocking' table does not exist. Please create it first.\n";
    }
    
    echo "\n✓ Deployment complete!\n";
    echo "\nNew endpoints available:\n";
    echo "  - mobile/save_manual_clockin.php\n";
    echo "  - mobile/save_manual_clockout.php\n";
    echo "  - mobile/get_manual_clocking_status.php\n";
    
} catch (Exception $e) {
    echo "✗ Error: " . $e->getMessage() . "\n";
    exit(1);
}

$conn->close();
?>
