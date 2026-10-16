<?php
/**
 * Setup Correct Manual Clocking Folder Structure
 * Creates: manual_clocking_evidence/ with subfolders faces/ and signatures/
 */

$basePath = __DIR__;
$mainFolder = "$basePath/manual_clocking_evidence";

echo "====================================\n";
echo "Setting Up Correct Clocking Folders\n";
echo "====================================\n\n";

// 1. Create main folder
echo "1. Creating main folder: manual_clocking_evidence\n";
if (!is_dir($mainFolder)) {
    if (mkdir($mainFolder, 0755, true)) {
        echo "   ✅ Created\n";
    } else {
        echo "   ❌ Failed\n";
        exit(1);
    }
} else {
    echo "   ✅ Already exists\n";
}

// 2. Create subfolders
$subfolders = ['faces', 'signatures'];

foreach ($subfolders as $subfolder) {
    $path = "$mainFolder/$subfolder";
    echo "\n2. Creating subfolder: $subfolder\n";
    
    if (!is_dir($path)) {
        if (mkdir($path, 0755, true)) {
            echo "   ✅ Created: $path\n";
        } else {
            echo "   ❌ Failed: $path\n";
        }
    } else {
        echo "   ✅ Already exists: $path\n";
    }
    
    // Create .htaccess for security
    $htaccessPath = "$path/.htaccess";
    if (!file_exists($htaccessPath)) {
        $htaccessContent = "# Protect clocking evidence files\n";
        $htaccessContent .= "Order Deny,Allow\n";
        $htaccessContent .= "Deny from all\n";
        $htaccessContent .= "# Allow only from server requests\n";
        $htaccessContent .= "Allow from 127.0.0.1\n";
        $htaccessContent .= "Allow from ::1\n";
        
        if (file_put_contents($htaccessPath, $htaccessContent)) {
            echo "   ✅ Created .htaccess protection\n";
        }
    }
}

// 3. Remove old incorrect folders if they exist
echo "\n3. Cleaning up old incorrect folders (if any):\n";
$oldFolders = [
    'manual_clocking_signatures',
    'manual_clocking_faces',
    'learner_clocking_signatures',
    'learner_clocking_faces'
];

foreach ($oldFolders as $oldFolder) {
    $oldPath = "$basePath/$oldFolder";
    if (is_dir($oldPath)) {
        // Check if empty before removing
        $files = scandir($oldPath);
        $files = array_diff($files, ['.', '..', '.htaccess']);
        
        if (count($files) === 0) {
            // Empty, safe to remove
            rmdir($oldPath);
            echo "   ✅ Removed empty folder: $oldFolder\n";
        } else {
            echo "   ⚠️  Kept (has files): $oldFolder (" . count($files) . " files)\n";
        }
    }
}

// 4. Verify final structure
echo "\n4. Final Structure Verification:\n";
echo "   manual_clocking_evidence/\n";
echo "   ├── faces/ " . (is_dir("$mainFolder/faces") ? "✅" : "❌") . "\n";
echo "   └── signatures/ " . (is_dir("$mainFolder/signatures") ? "✅" : "❌") . "\n";

echo "\n====================================\n";
echo "Setup Complete!\n";
echo "====================================\n";
?>
