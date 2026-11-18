<?php
/**
 * Background bulk export processor
 * Runs independently and updates progress file
 */

// Disable output buffering
while (ob_get_level()) {
    ob_end_clean();
}

// Set headers
header('Content-Type: application/json');
header('Connection: close');

// Get and validate parameters
$jobId = $_POST['job_id'] ?? uniqid('job_');

// Validate job ID format (alphanumeric, dash, underscore only)
if (!preg_match('/^[a-zA-Z0-9_-]+$/', $jobId)) {
    http_response_code(400);
    echo json_encode(['error' => 'Invalid job ID format']);
    exit;
}

// Validate and decode learner IDs
$learnerIds = isset($_POST['learner_ids']) ? json_decode($_POST['learner_ids'], true) : [];

if (!is_array($learnerIds) || empty($learnerIds)) {
    http_response_code(400);
    echo json_encode(['error' => 'Invalid or empty learner IDs']);
    exit;
}

// Validate each learner ID is a positive integer
$learnerIds = array_filter($learnerIds, function($id) {
    return filter_var($id, FILTER_VALIDATE_INT) !== false && $id > 0;
});

if (empty($learnerIds)) {
    http_response_code(400);
    echo json_encode(['error' => 'No valid learner IDs provided']);
    exit;
}

// Validate dates
$startDate = $_POST['start_date'] ?? date('Y-m-01');
$endDate = $_POST['end_date'] ?? date('Y-m-t');

if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $startDate)) {
    http_response_code(400);
    echo json_encode(['error' => 'Invalid start date format (use YYYY-MM-DD)']);
    exit;
}

if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $endDate)) {
    http_response_code(400);
    echo json_encode(['error' => 'Invalid end date format (use YYYY-MM-DD)']);
    exit;
}

// Validate project ID if provided
$projectId = $_POST['project_id'] ?? null;
if ($projectId !== null) {
    $projectId = filter_var($projectId, FILTER_VALIDATE_INT);
    if ($projectId === false) {
        http_response_code(400);
        echo json_encode(['error' => 'Invalid project ID']);
        exit;
    }
}

// Create progress file
$progressFile = __DIR__ . '/temp_reports/progress_' . $jobId . '.json';
if (!is_dir(__DIR__ . '/temp_reports')) {
    mkdir(__DIR__ . '/temp_reports', 0777, true);
}

// Initialize progress
$progress = [
    'status' => 'starting',
    'total' => count($learnerIds),
    'processed' => 0,
    'percent' => 0,
    'message' => 'Initializing...',
    'zip_file' => null
];
file_put_contents($progressFile, json_encode($progress));

// Send immediate response with job ID
echo json_encode([
    'success' => true,
    'job_id' => $jobId,
    'message' => 'Export started in background'
]);

// Close connection but keep script running
if (function_exists('fastcgi_finish_request')) {
    fastcgi_finish_request();
} else {
    header('Content-Length: ' . ob_get_length());
    ob_end_flush();
    flush();
}

// Now process in background
set_time_limit(1800); // 30 minutes
ini_set('memory_limit', '1024M');

try {
    // Update progress
    $progress['status'] = 'processing';
    $progress['message'] = 'Generating reports...';
    file_put_contents($progressFile, json_encode($progress));
    
    // Include required files
    require_once __DIR__ . '/connection.php';
    require_once __DIR__ . '/bulk_export_with_documents.php';
    
    // Generate reports with progress updates
    $results = generateBulkReportsWithDocuments($conn, $learnerIds, $startDate, $endDate, $projectId, function($current, $total) use ($progressFile, &$progress) {
        $progress['processed'] = $current;
        $progress['percent'] = round(($current / $total) * 100);
        $progress['message'] = "Processing learner $current of $total...";
        file_put_contents($progressFile, json_encode($progress));
    });
    
    // Update final progress
    $progress['status'] = 'completed';
    $progress['processed'] = $results['processed'];
    $progress['percent'] = 100;
    $progress['message'] = 'Export completed!';
    $progress['zip_file'] = $results['zip_file'];
    $progress['results'] = $results;
    file_put_contents($progressFile, json_encode($progress));
    
} catch (Exception $e) {
    $progress['status'] = 'error';
    $progress['message'] = 'Error: ' . $e->getMessage();
    file_put_contents($progressFile, json_encode($progress));
}
?>
