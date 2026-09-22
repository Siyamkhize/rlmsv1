<?php
/**
 * Setup Clocking Evidence Folders
 * 
 * Creates the directory structure for storing clocking evidence images
 * Run this script once to create the necessary folders
 * 
 * Usage: Navigate to https://yoursite.com/mobile/setup_clocking_evidence_folders.php
 */

header('Content-Type: application/json');

$results = [];
$errors = [];

// Define directories to create (inside mobile/ directory)
$base_path = __DIR__ . '/'; // Current directory (mobile/)
$directories = [
    'clocking_evidence' => $base_path . 'clocking_evidence/',
    'signatures' => $base_path . 'clocking_evidence/signatures/',
    'face_photos' => $base_path . 'clocking_evidence/face_photos/'
];

// Create each directory
foreach ($directories as $name => $path) {
    if (is_dir($path)) {
        $results[$name] = [
            'status' => 'exists',
            'path' => realpath($path),
            'writable' => is_writable($path)
        ];
    } else {
        if (mkdir($path, 0755, true)) {
            chmod($path, 0755); // Ensure correct permissions
            $results[$name] = [
                'status' => 'created',
                'path' => realpath($path),
                'writable' => is_writable($path)
            ];
        } else {
            $errors[$name] = "Failed to create directory: $path";
            $results[$name] = [
                'status' => 'error',
                'path' => $path,
                'writable' => false
            ];
        }
    }
}

// Create a test file to verify write permissions
$test_file = $base_path . 'clocking_evidence/test.txt';
$can_write = false;
if (file_put_contents($test_file, 'Test write ' . date('Y-m-d H:i:s'))) {
    $can_write = true;
    unlink($test_file); // Clean up test file
}

// Output results
$response = [
    'success' => empty($errors),
    'timestamp' => date('Y-m-d H:i:s'),
    'directories' => $results,
    'write_test' => $can_write,
    'errors' => $errors
];

if ($response['success']) {
    $response['message'] = 'All directories created successfully and are writable!';
} else {
    $response['message'] = 'Some directories could not be created. Check errors for details.';
}

// Pretty print the JSON
echo json_encode($response, JSON_PRETTY_PRINT);

// Also create an index.html in each directory to prevent directory listing
$index_content = '<!DOCTYPE html>
<html>
<head>
    <title>403 Forbidden</title>
</head>
<body>
    <h1>Access Denied</h1>
    <p>You do not have permission to access this directory.</p>
</body>
</html>';

foreach ($directories as $name => $path) {
    if (is_dir($path)) {
        $index_file = $path . 'index.html';
        if (!file_exists($index_file)) {
            file_put_contents($index_file, $index_content);
        }
    }
}

echo "\n\n<!-- Security index files created to prevent directory browsing -->";
?>
