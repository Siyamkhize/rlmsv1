<?php
/**
 * Setup Manual Clocking Folders
 * Creates all required folders for storing clock-in evidence
 */

$basePath = __DIR__;

$folders = [
    'manual_clocking_signatures',
    'manual_clocking_faces',
    'learner_clocking_signatures',
    'learner_clocking_faces'
];

echo "====================================\n";
echo "Setting Up Clocking Folders\n";
echo "====================================\n\n";

foreach ($folders as $folder) {
    $fullPath = "$basePath/$folder";
    
    echo "Creating: $folder\n";
    
    if (is_dir($fullPath)) {
        echo "  ✅ Already exists\n";
    } else {
        if (mkdir($fullPath, 0755, true)) {
            echo "  ✅ Created successfully\n";
        } else {
            echo "  ❌ Failed to create\n";
        }
    }
    
    // Create .htaccess to protect folder
    $htaccessPath = "$fullPath/.htaccess";
    if (!file_exists($htaccessPath)) {
        $htaccessContent = "# Protect clocking evidence files\n";
        $htaccessContent .= "Order Deny,Allow\n";
        $htaccessContent .= "Deny from all\n";
        $htaccessContent .= "# Allow only from server requests\n";
        $htaccessContent .= "Allow from 127.0.0.1\n";
        $htaccessContent .= "Allow from ::1\n";
        
        if (file_put_contents($htaccessPath, $htaccessContent)) {
            echo "  ✅ Created .htaccess protection\n";
        }
    }
    
    echo "\n";
}

echo "====================================\n";
echo "Setup Complete!\n";
echo "====================================\n";
?>
