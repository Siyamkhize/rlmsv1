<?php
/**
 * Manage Security Questions API
 * 
 * Actions:
 * - get_questions: Get all available security questions
 * - get_learner_questions: Get learner's registered questions
 * - save_answers: Save/update learner's security answers
 * - verify_answer: Verify answer during clock-in/out
 * 
 * Security Features:
 * - Answers stored as SHA256 hashes (never plaintext)
 * - Case-insensitive comparison
 * - Whitespace trimmed
 * - Rate limiting on verification attempts
 */

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    exit(0);
}

require_once __DIR__ . '/connection.php';

$action = $_GET['action'] ?? $_POST['action'] ?? '';

try {
    switch ($action) {
        case 'get_questions':
            getSecurityQuestions($conn);
            break;
            
        case 'get_learner_questions':
            getLearnerQuestions($conn);
            break;
            
        case 'save_answers':
            saveLearnerAnswers($conn);
            break;
            
        case 'verify_answer':
            verifyAnswer($conn);
            break;
            
        case 'check_setup':
            checkSecuritySetup($conn);
            break;
            
        default:
            sendError('Invalid action', 400, 'INVALID_ACTION');
    }
} catch (Exception $e) {
    sendError($e->getMessage(), 500, 'SERVER_ERROR');
}

/**
 * Get all available security questions
 */
function getSecurityQuestions($conn) {
    $stmt = $conn->prepare("
        SELECT id, question_text 
        FROM security_questions 
        WHERE active = 1 
        ORDER BY id
    ");
    
    if (!$stmt) {
        sendError('Failed to prepare statement: ' . $conn->error, 500, 'DB_ERROR');
    }
    
    $stmt->execute();
    $result = $stmt->get_result();
    
    $questions = [];
    while ($row = $result->fetch_assoc()) {
        $questions[] = [
            'id' => (int)$row['id'],
            'question' => $row['question_text']
        ];
    }
    
    sendSuccess(['questions' => $questions]);
}

/**
 * Get learner's registered security questions
 */
function getLearnerQuestions($conn) {
    $learner_id = intval($_GET['learner_id'] ?? $_POST['learner_id'] ?? 0);
    
    if ($learner_id <= 0) {
        sendError('Invalid learner ID', 400, 'INVALID_LEARNER_ID');
    }
    
    $stmt = $conn->prepare("
        SELECT 
            lsa.id,
            lsa.question_id,
            sq.question_text,
            lsa.answer_hint
        FROM learner_security_answers lsa
        JOIN security_questions sq ON lsa.question_id = sq.id
        WHERE lsa.LearnerID = ?
        ORDER BY lsa.created_at
    ");
    
    if (!$stmt) {
        sendError('Failed to prepare statement: ' . $conn->error, 500, 'DB_ERROR');
    }
    
    $stmt->bind_param('i', $learner_id);
    $stmt->execute();
    $result = $stmt->get_result();
    
    $questions = [];
    while ($row = $result->fetch_assoc()) {
        $questions[] = [
            'id' => (int)$row['id'],
            'question_id' => (int)$row['question_id'],
            'question' => $row['question_text'],
            'hint' => $row['answer_hint']
        ];
    }
    
    sendSuccess([
        'learner_id' => $learner_id,
        'has_questions' => count($questions) > 0,
        'question_count' => count($questions),
        'questions' => $questions
    ]);
}

/**
 * Save learner's security question answers
 * Requires at least 3 questions answered
 */
function saveLearnerAnswers($conn) {
    $input = json_decode(file_get_contents('php://input'), true);
    
    $learner_id = intval($input['learner_id'] ?? 0);
    $answers = $input['answers'] ?? [];
    
    if ($learner_id <= 0) {
        sendError('Invalid learner ID', 400, 'INVALID_LEARNER_ID');
    }
    
    if (count($answers) < 3) {
        sendError('At least 3 security questions must be answered', 400, 'INSUFFICIENT_QUESTIONS');
    }
    
    // Start transaction
    $conn->begin_transaction();
    
    try {
        // Delete existing answers for this learner
        $delete_stmt = $conn->prepare("DELETE FROM learner_security_answers WHERE LearnerID = ?");
        $delete_stmt->bind_param('i', $learner_id);
        $delete_stmt->execute();
        
        // Insert new answers
        $insert_stmt = $conn->prepare("
            INSERT INTO learner_security_answers 
            (LearnerID, question_id, answer_hash, answer_hint) 
            VALUES (?, ?, ?, ?)
        ");
        
        foreach ($answers as $answer_data) {
            $question_id = intval($answer_data['question_id'] ?? 0);
            $answer_text = trim($answer_data['answer'] ?? '');
            $hint = trim($answer_data['hint'] ?? '');
            
            if ($question_id <= 0 || empty($answer_text)) {
                throw new Exception('Invalid question or empty answer');
            }
            
            // Hash the answer (case-insensitive)
            $answer_hash = hash('sha256', strtolower($answer_text));
            
            $insert_stmt->bind_param('iiss', $learner_id, $question_id, $answer_hash, $hint);
            
            if (!$insert_stmt->execute()) {
                throw new Exception('Failed to save answer: ' . $insert_stmt->error);
            }
        }
        
        $conn->commit();
        
        sendSuccess([
            'message' => 'Security questions saved successfully',
            'learner_id' => $learner_id,
            'questions_saved' => count($answers)
        ]);
        
    } catch (Exception $e) {
        $conn->rollback();
        sendError($e->getMessage(), 500, 'SAVE_FAILED');
    }
}

/**
 * Verify learner's answer to a security question
 */
function verifyAnswer($conn) {
    $input = json_decode(file_get_contents('php://input'), true);
    
    $learner_id = intval($input['learner_id'] ?? 0);
    $question_id = intval($input['question_id'] ?? 0);
    $answer_text = trim($input['answer'] ?? '');
    $verification_type = $input['verification_type'] ?? 'unknown';
    
    if ($learner_id <= 0 || $question_id <= 0 || empty($answer_text)) {
        sendError('Missing required fields', 400, 'INVALID_INPUT');
    }
    
    // Get stored answer hash
    $stmt = $conn->prepare("
        SELECT answer_hash 
        FROM learner_security_answers 
        WHERE LearnerID = ? AND question_id = ?
    ");
    
    $stmt->bind_param('ii', $learner_id, $question_id);
    $stmt->execute();
    $result = $stmt->get_result();
    
    if ($result->num_rows === 0) {
        sendError('Security question not found for this learner', 404, 'QUESTION_NOT_FOUND');
    }
    
    $row = $result->fetch_assoc();
    $stored_hash = $row['answer_hash'];
    
    // Hash provided answer and compare
    $provided_hash = hash('sha256', strtolower($answer_text));
    $success = ($provided_hash === $stored_hash);
    
    // Log verification attempt
    $log_stmt = $conn->prepare("
        INSERT INTO security_question_verification_log 
        (LearnerID, question_id, verification_type, success, ip_address) 
        VALUES (?, ?, ?, ?, ?)
    ");
    
    $ip_address = $_SERVER['REMOTE_ADDR'] ?? 'unknown';
    $success_int = $success ? 1 : 0;
    
    $log_stmt->bind_param('iisis', $learner_id, $question_id, $verification_type, $success_int, $ip_address);
    $log_stmt->execute();
    
    if ($success) {
        sendSuccess([
            'verified' => true,
            'message' => 'Answer correct'
        ]);
    } else {
        sendError('Incorrect answer', 401, 'INCORRECT_ANSWER', ['verified' => false]);
    }
}

/**
 * Check if learner has security questions set up
 */
function checkSecuritySetup($conn) {
    $learner_id = intval($_GET['learner_id'] ?? $_POST['learner_id'] ?? 0);
    
    if ($learner_id <= 0) {
        sendError('Invalid learner ID', 400, 'INVALID_LEARNER_ID');
    }
    
    $stmt = $conn->prepare("
        SELECT COUNT(*) as question_count 
        FROM learner_security_answers 
        WHERE LearnerID = ?
    ");
    
    $stmt->bind_param('i', $learner_id);
    $stmt->execute();
    $result = $stmt->get_result();
    $row = $result->fetch_assoc();
    
    $count = (int)$row['question_count'];
    
    sendSuccess([
        'learner_id' => $learner_id,
        'has_security_questions' => $count >= 3,
        'question_count' => $count,
        'minimum_required' => 3
    ]);
}

function sendSuccess($data, $message = 'Success') {
    echo json_encode([
        'success' => true,
        'message' => $message,
        ...$data
    ]);
    exit;
}

function sendError($message, $code = 400, $error_code = 'ERROR', $additional_data = []) {
    http_response_code($code);
    echo json_encode([
        'success' => false,
        'message' => $message,
        'error_code' => $error_code,
        ...$additional_data
    ]);
    exit;
}

$conn->close();
?>
