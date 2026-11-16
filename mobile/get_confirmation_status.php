<?php
/**
 * mobile/get_confirmation_status.php
 * Get upload status and history for learner confirmations
 * 
 * Request (GET):
 * - facilitator_id: int (required)
 * - class_id: int (optional - filter by class)
 * - submission_date: YYYY-MM-DD (optional - filter by date)
 * - limit: int (optional - default 50, max 200)
 * 
 * Response:
 * {
 *   "success": true,
 *   "data": {
 *     "confirmations": [...],
 *     "summary": {
 *       "total_submissions": 10,
 *       "total_learners": 150,
 *       "pending": 5,
 *       "confirmed": 5
 *     }
 *   }
 * }
 */

header('Content-Type: application/json');
require '../connection.php';

function sendResponse($success, $message, $data = null, $httpCode = 200) {
    http_response_code($httpCode);
    echo json_encode([
        'success' => $success,
        'message' => $message,
        'data' => $data,
        'timestamp' => date('Y-m-d H:i:s')
    ]);
    exit;
}

// Only accept GET
if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    sendResponse(false, 'Method not allowed. Use GET.', null, 405);
}

try {
    // ══════════════════════════════════════════════════════════════════════════
    // 1. VALIDATE INPUT
    // ══════════════════════════════════════════════════════════════════════════
    
    $facilitator_id  = isset($_GET['facilitator_id']) ? (int)$_GET['facilitator_id'] : 0;
    $class_id        = isset($_GET['class_id']) ? (int)$_GET['class_id'] : null;
    $submission_date = isset($_GET['submission_date']) ? trim($_GET['submission_date']) : null;
    $limit           = isset($_GET['limit']) ? min((int)$_GET['limit'], 200) : 50;
    
    if (!$facilitator_id) {
        sendResponse(false, 'facilitator_id is required', null, 400);
    }
    
    if ($submission_date && !preg_match('/^\d{4}-\d{2}-\d{2}$/', $submission_date)) {
        sendResponse(false, 'Invalid submission_date format. Use YYYY-MM-DD', null, 400);
    }
    
    // ══════════════════════════════════════════════════════════════════════════
    // 2. VERIFY FACILITATOR EXISTS
    // ══════════════════════════════════════════════════════════════════════════
    
    $fac_check = $conn->prepare("
        SELECT facilitator_id, firstName, lastName, classID 
        FROM facilitator 
        WHERE facilitator_id = ?
        LIMIT 1
    ");
    $fac_check->bind_param('i', $facilitator_id);
    $fac_check->execute();
    
    if ($fac_check->get_result()->num_rows === 0) {
        $fac_check->close();
        sendResponse(false, 'Facilitator not found', null, 404);
    }
    $fac_check->close();
    
    // ══════════════════════════════════════════════════════════════════════════
    // 3. BUILD QUERY WITH FILTERS
    // ══════════════════════════════════════════════════════════════════════════
    
    $query = "
        SELECT 
            lsc.id AS confirmation_id,
            lsc.manual_id,
            lsc.submission_date,
            lsc.learners_claimed,
            lsc.learners_counted,
            lsc.uploader_confirmation,
            lsc.dispute_reason,
            lsc.facilitator_confirmed_at,
            lsc.uploader_responded_at,
            lsc.created_at,
            mc.fdp_document,
            mc.status AS manual_status,
            c.classID,
            c.className,
            s.siteName,
            COUNT(DISTINCT mc2.manual_id) AS total_records
        FROM learner_submission_confirmations lsc
        JOIN manual_clocking mc ON mc.manual_id = lsc.manual_id
        JOIN learnerdetails ld ON ld.LearnerID = mc.LearnerID
        JOIN class c ON c.classID = ld.classID
        JOIN sites s ON s.siteID = c.siteID
        LEFT JOIN manual_clocking mc2 ON mc2.fdp_document = mc.fdp_document
        WHERE lsc.facilitator_id = ?
    ";
    
    $params = [$facilitator_id];
    $types = 'i';
    
    if ($class_id) {
        $query .= " AND c.classID = ?";
        $params[] = $class_id;
        $types .= 'i';
    }
    
    if ($submission_date) {
        $query .= " AND lsc.submission_date = ?";
        $params[] = $submission_date;
        $types .= 's';
    }
    
    $query .= "
        GROUP BY lsc.id, lsc.manual_id, lsc.submission_date, lsc.learners_claimed,
                 lsc.learners_counted, lsc.uploader_confirmation, lsc.dispute_reason,
                 lsc.facilitator_confirmed_at, lsc.uploader_responded_at, lsc.created_at,
                 mc.fdp_document, mc.status, c.classID, c.className, s.siteName
        ORDER BY lsc.created_at DESC
        LIMIT ?
    ";
    $params[] = $limit;
    $types .= 'i';
    
    $stmt = $conn->prepare($query);
    $stmt->bind_param($types, ...$params);
    $stmt->execute();
    $result = $stmt->get_result();
    
    $confirmations = [];
    while ($row = $result->fetch_assoc()) {
        $confirmations[] = [
            'confirmation_id' => (int)$row['confirmation_id'],
            'manual_id' => (int)$row['manual_id'],
            'submission_date' => $row['submission_date'],
            'learners_claimed' => (int)$row['learners_claimed'],
            'learners_counted' => (int)$row['learners_counted'],
            'total_records' => (int)$row['total_records'],
            'status' => $row['uploader_confirmation'],
            'manual_status' => $row['manual_status'],
            'dispute_reason' => $row['dispute_reason'],
            'pdf_filename' => $row['fdp_document'],
            'pdf_url' => $row['fdp_document'] ? "../uploads/" . $row['fdp_document'] : null,
            'class' => [
                'id' => (int)$row['classID'],
                'name' => $row['className'],
                'site' => $row['siteName']
            ],
            'submitted_at' => $row['created_at'],
            'facilitator_confirmed_at' => $row['facilitator_confirmed_at'],
            'uploader_responded_at' => $row['uploader_responded_at']
        ];
    }
    $stmt->close();
    
    // ══════════════════════════════════════════════════════════════════════════
    // 4. GET SUMMARY STATISTICS
    // ══════════════════════════════════════════════════════════════════════════
    
    $summary_query = "
        SELECT 
            COUNT(*) AS total_submissions,
            SUM(learners_counted) AS total_learners,
            SUM(CASE WHEN uploader_confirmation = 'pending' THEN 1 ELSE 0 END) AS pending,
            SUM(CASE WHEN uploader_confirmation = 'confirmed' THEN 1 ELSE 0 END) AS confirmed,
            SUM(CASE WHEN uploader_confirmation = 'disputed' THEN 1 ELSE 0 END) AS disputed
        FROM learner_submission_confirmations
        WHERE facilitator_id = ?
    ";
    
    $summary_params = [$facilitator_id];
    $summary_types = 'i';
    
    if ($class_id) {
        $summary_query .= " AND manual_id IN (
            SELECT mc.manual_id FROM manual_clocking mc
            JOIN learnerdetails ld ON ld.LearnerID = mc.LearnerID
            WHERE ld.classID = ?
        )";
        $summary_params[] = $class_id;
        $summary_types .= 'i';
    }
    
    $summary_stmt = $conn->prepare($summary_query);
    $summary_stmt->bind_param($summary_types, ...$summary_params);
    $summary_stmt->execute();
    $summary = $summary_stmt->get_result()->fetch_assoc();
    $summary_stmt->close();
    
    // ══════════════════════════════════════════════════════════════════════════
    // 5. RESPONSE
    // ══════════════════════════════════════════════════════════════════════════
    
    $response_data = [
        'confirmations' => $confirmations,
        'summary' => [
            'total_submissions' => (int)$summary['total_submissions'],
            'total_learners' => (int)$summary['total_learners'],
            'pending' => (int)$summary['pending'],
            'confirmed' => (int)$summary['confirmed'],
            'disputed' => (int)$summary['disputed']
        ],
        'filters_applied' => [
            'facilitator_id' => $facilitator_id,
            'class_id' => $class_id,
            'submission_date' => $submission_date,
            'limit' => $limit
        ]
    ];
    
    sendResponse(true, 'Confirmations retrieved successfully', $response_data);
    
} catch (Exception $e) {
    error_log('Get confirmation status error: ' . $e->getMessage());
    sendResponse(false, 'Server error: ' . $e->getMessage(), null, 500);
}
?>
