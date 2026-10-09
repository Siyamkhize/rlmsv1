<?php
/**
 * Setup Clocking Evidence Folders
 * 
 * Creates the directory structure for backup clock-in evidence:
 * - mobile/clocking_evidence/signatures/
 * - mobile/clocking_evidence/face_photos/
 * 
 * Run this once to set up the folders with proper permissions.
 */

header('Content-Type: application/json');

$base_dir = __DIR__ . '/clocking_evidence';
$signatures_dir = $base_dir . '/signatures';
$face_photos_dir = $base_dir . '/face_photos';

$results = [
    'success' => true,
    'folders_created' => [],
    'folders_existed' => [],
    'errors' => []
];

// Create base directory
if (!is_dir($base_dir)) {
    if (mkdir($base_dir, 0755, true)) {
        $results['folders_created'][] = 'clocking_evidence/';
        chmod($base_dir, 0755);
    } else {
        $results['success'] = false;
        $results['errors'][] = 'Failed to create base directory: clocking_evidence/';
    }
} else {
    $results['folders_existed'][] = 'clocking_evidence/';
}

// Create signatures subdirectory
if (!is_dir($signatures_dir)) {
    if (mkdir($signatures_dir, 0755, true)) {
        $results['folders_created'][] = 'clocking_evidence/signatures/';
        chmod($signatures_dir, 0755);
    } else {
        $results['success'] = false;
        $results['errors'][] = 'Failed to create signatures directory';
    }
} else {
    $results['folders_existed'][] = 'clocking_evidence/signatures/';
}

// Create face_photos subdirectory
if (!is_dir($face_photos_dir)) {
    if (mkdir($face_photos_dir, 0755, true)) {
        $results['folders_created'][] = 'clocking_evidence/face_photos/';
        chmod($face_photos_dir, 0755);
    } else {
        $results['success'] = false;
        $results['errors'][] = 'Failed to create face_photos directory';
    }
} else {
    $results['folders_existed'][] = 'clocking_evidence/face_photos/';
}

// Create .htaccess to protect the evidence files
$htaccess_content = <<<HTACCESS
# Protect clocking evidence files
# Only allow access through the app (via PHP scripts)

# Deny direct access to all files
<Files "*">
    Order Deny,Allow
    Deny from all
</Files>

# Allow access to index files
<Files "index.php">
    Allow from all
</Files>
HTACCESS;

$htaccess_file = $base_dir . '/.htaccess';
if (!file_exists($htaccess_file)) {
    if (file_put_contents($htaccess_file, $htaccess_content)) {
        $results['folders_created'][] = 'clocking_evidence/.htaccess (security)';
        chmod($htaccess_file, 0644);
    } else {
        $results['errors'][] = 'Failed to create .htaccess security file';
    }
} else {
    $results['folders_existed'][] = 'clocking_evidence/.htaccess';
}

// Check permissions
$results['permissions'] = [
    'base_dir' => is_writable($base_dir) ? 'writable' : 'NOT WRITABLE',
    'signatures_dir' => is_writable($signatures_dir) ? 'writable' : 'NOT WRITABLE',
    'face_photos_dir' => is_writable($face_photos_dir) ? 'writable' : 'NOT WRITABLE'
];

echo json_encode($results, JSON_PRETTY_PRINT);
