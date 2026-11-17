# Fix remaining return_of_invalid_type errors
# Replace "return null;" with "return false;" in methods that return Future<bool>

$filesToFix = @(
    "lib\backup_clock_in_page.dart",
    "lib\sick_note_page.dart",
    "lib\DetailsPage_server.dart",
    "lib\POECollectionPage.dart"
)

foreach ($file in $filesToFix) {
    if (Test-Path $file) {
        Write-Host "Fixing $file..."
        $content = Get-Content $file -Raw
        
        # Replace "if (!context.mounted) return null;" with "if (!context.mounted) return false;"
        # in contexts where the method returns Future<bool>
        $content = $content -replace 'if\s*\(\s*!context\.mounted\s*\)\s*return\s+null\s*;', 'if (!context.mounted) return false;'
        
        # Replace "if (!mounted) return null;" with "if (!mounted) return false;"
        $content = $content -replace 'if\s*\(\s*!mounted\s*\)\s*return\s+null\s*;', 'if (!mounted) return false;'
        
        Set-Content -Path $file -Value $content -NoNewline
        Write-Host "Fixed $file"
    }
}

Write-Host "Done!"
