<?php
/**
 * Deploy Security Questions Tables to MySQL
 */

require_once __DIR__ . '/mobile/connection.php';

echo "Deploying Security Questions Tables...\n\n";

// Create security_questions table
$sql1 = "CREATE TABLE IF NOT EXISTS security_questions (
    id INT AUTO_INCREMENT PRIMARY KEY,
    question_text VARCHAR(255) NOT NULL UNIQUE,
    active TINYINT(1) DEFAULT 1,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_active (active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci";

if ($conn->query($sql1)) {
    echo "✓ Created security_questions table\n";
} else {
    echo "✗ Error creating security_questions: " . $conn->error . "\n";
}

// Create learner_security_answers table
$sql2 = "CREATE TABLE IF NOT EXISTS learner_security_answers (
    id INT AUTO_INCREMENT PRIMARY KEY,
    LearnerID INT NOT NULL,
    question_id INT NOT NULL,
    answer_hash VARCHAR(64) NOT NULL,
    answer_hint VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY unique_learner_question (LearnerID, question_id),
    FOREIGN KEY (question_id) REFERENCES security_questions(id) ON DELETE CASCADE,
    INDEX idx_learner (LearnerID)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci";

if ($conn->query($sql2)) {
    echo "✓ Created learner_security_answers table\n";
} else {
    echo "✗ Error creating learner_security_answers: " . $conn->error . "\n";
}

// Create verification log table
$sql3 = "CREATE TABLE IF NOT EXISTS security_question_verification_log (
    id INT AUTO_INCREMENT PRIMARY KEY,
    LearnerID INT NOT NULL,
    question_id INT NOT NULL,
    verification_type VARCHAR(50),
    success TINYINT(1) NOT NULL,
    attempt_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    ip_address VARCHAR(45),
    INDEX idx_learner_log (LearnerID),
    INDEX idx_timestamp (attempt_timestamp)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci";

if ($conn->query($sql3)) {
    echo "✓ Created security_question_verification_log table\n";
} else {
    echo "✗ Error creating verification_log: " . $conn->error . "\n";
}

// Insert default questions
$questions = [
    "What is your mother's maiden name?",
    "What is the name of your first pet?",
    "What is the name of the street you grew up on?",
    "What is your favorite color?",
    "What is the name of your best friend from childhood?",
    "What is the name of your first school?",
    "What is your father's middle name?",
    "In what city were you born?",
    "What is your favorite food?",
    "What is the name of your favorite teacher?",
    "What was your first car (make/model)?",
    "What is your favorite sport or team?",
    "What is the name of your favorite book or movie?",
    "What is your grandmother's first name?",
    "What was your childhood nickname?"
];

echo "\nInserting default questions...\n";
$inserted = 0;

foreach ($questions as $question) {
    $stmt = $conn->prepare("INSERT IGNORE INTO security_questions (question_text) VALUES (?)");
    $stmt->bind_param('s', $question);
    if ($stmt->execute() && $stmt->affected_rows > 0) {
        $inserted++;
    }
}

echo "✓ Inserted $inserted new questions\n";

// Check final counts
$result = $conn->query("SELECT COUNT(*) as count FROM security_questions");
$row = $result->fetch_assoc();
echo "\nTotal questions in database: " . $row['count'] . "\n";

$result2 = $conn->query("SELECT COUNT(*) as count FROM learner_security_answers");
$row2 = $result2->fetch_assoc();
echo "Total learner answers: " . $row2['count'] . "\n";

echo "\n✅ Deployment complete!\n";

$conn->close();
?>
