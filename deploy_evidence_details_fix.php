<?php
/**
 * Deploy Manual Clocking Evidence Details Fix
 * 
 * Fixes:
 * 1. Changed query from learner_clocking table to manual_clocking table (correct source for times)
 * 2. Improved image and signature layout with better visual structure
 * 3. Separated Clock In and Clock Out evidence into distinct sections
 */

// Source file in project
$sourceFile = __DIR__ . '/mobile/manual_clocking_evidence_details.php';

// Destination on server (adjust this path to your actual server location)
$destinationFile = 'C:/xampp/htdocs/rlmss/mobile/manual_clocking_evidence_details.php';

// Check if source file exists
if (!file_exists($sourceFile)) {
    die("❌ ERROR: Source file not found: $sourceFile\n");
}

// Create backup of existing file
if (file_exists($destinationFile)) {
    $backupFile = $destinationFile . '.backup.' . date('Y-m-d_His');
    if (copy($destinationFile, $backupFile)) {
        echo "✅ Backup created: $backupFile\n";
    } else {
        die("❌ ERROR: Failed to create backup\n");
    }
}

// Copy the fixed file
if (copy($sourceFile, $destinationFile)) {
    echo "✅ Successfully deployed manual_clocking_evidence_details.php\n";
    echo "\n📋 Changes deployed:\n";
    echo "   1. Fixed clocking times - now using manual_clocking table (was: learner_clocking)\n";
    echo "   2. Improved image layout with separate Clock In and Clock Out sections\n";
    echo "   3. Enhanced visual structure with better spacing and organization\n";
    echo "   4. Added hover effects and improved filename display\n";
    echo "\n✅ Deployment complete!\n";
    echo "\n📍 Test the page with an evidence record that has clocking times in manual_clocking table\n";
} else {
    die("❌ ERROR: Failed to copy file to destination\n");
}
?>
