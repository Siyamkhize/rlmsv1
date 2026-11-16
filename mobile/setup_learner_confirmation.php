<?php
/**
 * Setup script for Learner Confirmation feature
 * Run this once to create the table and folder structure
 */

require_once 'connection.php';

header('Content-Type: application/json');

$results = [
    'timestamp' => date('Y-m-d H:i:s'),
    'steps' => []
];

// Step 1: Create the database table
$sql = "CREATE TABLE IF NOT EXISTS `learner_submission_confirmations` (
  `id` INT(11) NOT NULL AUTO_INCREMENT,
  `facilitator_id` INT(11) NOT NULL,
  `class_id` INT(11) NOT NULL,
  `submission_date` DATE NOT NULL,
  `learners_counted` INT(11) NOT NULL,
  `learner_ids` TEXT NOT NULL COMMENT 'Comma-separated list of learner IDs',
  `register_pdf_path` VARCHAR(500) NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_facilitator` (`facilitator_id`),
  KEY `idx_class` (`class_id`),
  KEY `idx_submission_date` (`submission_date`),
  UNIQUE KEY `unique_submission` (`class_id`, `submission_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci";

if ($conn->query($sql) === TRUE) {
    $results['steps'][] = [
        'step' => 'create_table',
        'status' => 'success',
        'message' => 'Table learner_submission_confirmations created/verified'
    ];
} else {
    $results['steps'][] = [
        'step' => 'create_table',
        'status' => 'error',
        'message' => 'Error: ' . $conn->error
    ];
}

// Step 2: Create uploads directory (one level up from mobile/)
$uploadDir = dirname(__DIR__) . '/uploads';
if (!file_exists($uploadDir)) {
    mkdir($uploadDir, 0777, true);
    $results['steps'][] = [
        'step' => 'create_uploads_dir',
        'status' => 'success',
        'message' => "Created directory: $uploadDir"
    ];
} else {
    $results['steps'][] = [
        'step' => 'create_uploads_dir',
        'status' => 'exists',
        'message' => "Directory already exists: $uploadDir"
    ];
}

// Step 3: Create learner_confirmations subdirectory
$confirmationsDir = $uploadDir . '/learner_confirmations';
if (!file_exists($confirmationsDir)) {
    mkdir($confirmationsDir, 0777, true);
    chmod($confirmationsDir, 0777);
    $results['steps'][] = [
        'step' => 'create_confirmations_dir',
        'status' => 'success',
        'message' => "Created directory: $confirmationsDir"
    ];
} else {
    chmod($confirmationsDir, 0777);
    $results['steps'][] = [
        'step' => 'create_confirmations_dir',
        'status' => 'exists',
        'message' => "Directory already exists: $confirmationsDir"
    ];
}

// Step 4: Test write permissions
$testFile = $confirmationsDir . '/test_' . time() . '.txt';
if (file_put_contents($testFile, 'test') !== false) {
    unlink($testFile);
    $results['steps'][] = [
        'step' => 'test_write_permission',
        'status' => 'success',
        'message' => 'Write permissions verified'
    ];
} else {
    $results['steps'][] = [
        'step' => 'test_write_permission',
        'status' => 'error',
        'message' => 'Cannot write to directory. Check permissions.'
    ];
}

// Step 5: Verify table structure
$structure = $conn->query("DESCRIBE learner_submission_confirmations");
if ($structure) {
    $columns = [];
    while ($row = $structure->fetch_assoc()) {
        $columns[] = $row['Field'];
    }
    $results['steps'][] = [
        'step' => 'verify_table_structure',
        'status' => 'success',
        'columns' => $columns
    ];
} else {
    $results['steps'][] = [
        'step' => 'verify_table_structure',
        'status' => 'error',
        'message' => $conn->error
    ];
}

// Final status
$allSuccess = true;
foreach ($results['steps'] as $step) {
    if ($step['status'] === 'error') {
        $allSuccess = false;
        break;
    }
}

$results['setup_complete'] = $allSuccess;
$results['upload_path'] = $confirmationsDir;

echo json_encode($results, JSON_PRETTY_PRINT);
?>
