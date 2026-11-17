<?php
/**
 * Setup Manual Clocking Evidence Folders
 * 
 * Creates folder structure for storing manual clocking evidence:
 * - manual_clocking_evidence/signatures/
 * - manual_clocking_evidence/faces/
 */

$baseDir = dirname(__DIR__);
$evidenceDir = $baseDir . '/manual_clocking_evidence';
$signaturesDir = $evidenceDir . '/signatures';
$facesDir = $evidenceDir . '/faces';

$folders = [
    $evidenceDir => 'Base evidence directory',
    $signaturesDir => 'Signatures storage',
    $facesDir => 'Face photos storage',
];

echo "Setting up manual clocking evidence folders...\n\n";

foreach ($folders as $folder => $description) {
    if (!file_exists($folder)) {
        if (mkdir($folder, 0755, true)) {
            echo "✓ Created: $folder ($description)\n";
        } else {
            echo "✗ Failed to create: $folder\n";
            exit(1);
        }
    } else {
        echo "✓ Already exists: $folder\n";
    }
    
    // Create .htaccess to allow access
    $htaccessPath = $folder . '/.htaccess';
    if (!file_exists($htaccessPath)) {
        $htaccessContent = "Options -Indexes\n";
        $htaccessContent .= "# Allow image access\n";
        $htaccessContent .= "<FilesMatch \"\\.(jpg|jpeg|png|gif)$\">\n";
        $htaccessContent .= "    Order Allow,Deny\n";
        $htaccessContent .= "    Allow from all\n";
        $htaccessContent .= "</FilesMatch>\n";
        
        file_put_contents($htaccessPath, $htaccessContent);
        echo "  ✓ Created .htaccess in $folder\n";
    }
}

echo "\n✓ Folder setup complete!\n";
echo "\nFolder structure:\n";
echo "  manual_clocking_evidence/\n";
echo "  ├── signatures/  (signature images)\n";
echo "  └── faces/       (face photos with watermarks)\n";
?>
