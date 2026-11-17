<?php
/**
 * DEBUG VERSION - Save Manual Clocking Images
 * This version outputs detailed error information
 * Upload this to your live server to diagnose the HTTP 500 error
 */

// Force display errors for debugging
error_reporting(E_ALL);
ini_set('display_errors', 1);
ini_set('log_errors', 1);
ini_set('error_log', __DIR__ . '/../../logs/php_errors.log');

header('Content-Type: text/plain');

echo "=== MANUAL CLOCKING IMAGES DEBUG ===\n";
echo "Time: " . date('Y-m-d H:i:s') . "\n\n";

// Step 1: Check PHP version
echo "[1] PHP Version: " . PHP_VERSION . "\n";

// Step 2: Check required files
echo "\n[2] Checking required files:\n";
$files = [
    'connection.php',
    'require_auth.php',
    'security_functions.php',
    'idempotency_helpers.php',
    'evidence_helpers.php'
];

foreach ($files as $file) {
    $path = __DIR__ . '/' . $file;
    if (file_exists($path)) {
        echo "  ✅ $file exists (" . filesize($path) . " bytes)\n";
    } else {
        echo "  ❌ $file MISSING at: $path\n";
    }
}

// Step 3: Try to include connection.php
echo "\n[3] Testing database connection:\n";
try {
    require_once __DIR__ . '/connection.php';
    echo "  ✅ connection.php included\n";
    
    if (isset($conn)) {
        echo "  ✅ \$conn variable exists\n";
        echo "  Connection type: " . get_class($conn) . "\n";
    } else {
        echo "  ❌ \$conn variable not found\n";
    }
} catch (Exception $e) {
    echo "  ❌ Error including connection.php: " . $e->getMessage() . "\n";
}

// Step 4: Try to include other required files
echo "\n[4] Testing other includes:\n";
$includes = [
    'require_auth.php',
    'security_functions.php'
];

foreach ($includes as $file) {
    try {
        require_once __DIR__ . '/' . $file;
        echo "  ✅ $file included\n";
    } catch (Exception $e) {
        echo "  ❌ Error including $file: " . $e->getMessage() . "\n";
    }
}

// Step 5: Check folders
echo "\n[5] Checking image folders:\n";
$facesDir = __DIR__ . '/manual_clocking_evidence/faces';
$signaturesDir = __DIR__ . '/manual_clocking_evidence/signatures';

echo "  Faces dir: $facesDir\n";
echo "    Exists: " . (file_exists($facesDir) ? "YES" : "NO") . "\n";
echo "    Writable: " . (is_writable($facesDir) ? "YES" : "NO") . "\n";

echo "  Signatures dir: $signaturesDir\n";
echo "    Exists: " . (file_exists($signaturesDir) ? "YES" : "NO") . "\n";
echo "    Writable: " . (is_writable($signaturesDir) ? "YES" : "NO") . "\n";

// Step 6: Test GD library
echo "\n[6] Testing GD library:\n";
if (extension_loaded('gd')) {
    echo "  ✅ GD extension loaded\n";
    $gdInfo = gd_info();
    echo "  GD Version: " . $gdInfo['GD Version'] . "\n";
    echo "  JPEG Support: " . ($gdInfo['JPEG Support'] ? "YES" : "NO") . "\n";
    echo "  PNG Support: " . ($gdInfo['PNG Support'] ? "YES" : "NO") . "\n";
} else {
    echo "  ❌ GD extension NOT loaded\n";
}

// Step 7: Test processing a sample request
echo "\n[7] Testing request processing:\n";
echo "  Request method: " . ($_SERVER['REQUEST_METHOD'] ?? 'UNKNOWN') . "\n";
echo "  Content-Type: " . ($_SERVER['CONTENT_TYPE'] ?? 'UNKNOWN') . "\n";
echo "  Content-Length: " . ($_SERVER['CONTENT_LENGTH'] ?? '0') . "\n";

$rawInput = file_get_contents('php://input');
echo "  Input size: " . strlen($rawInput) . " bytes\n";

if (strlen($rawInput) > 0) {
    $input = json_decode($rawInput, true);
    if ($input) {
        echo "  ✅ JSON decoded successfully\n";
        echo "  Keys in JSON: " . implode(', ', array_keys($input)) . "\n";
        
        if (isset($input['learner_id'])) echo "  learner_id: " . $input['learner_id'] . "\n";
        if (isset($input['clock_date'])) echo "  clock_date: " . $input['clock_date'] . "\n";
        if (isset($input['type'])) echo "  type: " . $input['type'] . "\n";
        if (isset($input['face_image'])) echo "  face_image length: " . strlen($input['face_image']) . "\n";
        if (isset($input['signature_image'])) echo "  signature_image length: " . strlen($input['signature_image']) . "\n";
    } else {
        echo "  ❌ Failed to decode JSON\n";
        echo "  JSON error: " . json_last_error_msg() . "\n";
    }
}

echo "\n=== DEBUG COMPLETE ===\n";
echo "\nUpload this output to support for diagnosis.\n";
?>
