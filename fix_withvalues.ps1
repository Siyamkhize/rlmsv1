# Fix withValues() to withOpacity() for older Flutter versions
# This script replaces all withValues() calls with withOpacity()

Write-Host "Fixing withValues() compatibility issues..." -ForegroundColor Cyan

$files = Get-ChildItem -Path "lib" -Filter "*.dart" -Recurse
$totalFixed = 0

foreach ($file in $files) {
    $content = Get-Content $file.FullName -Raw
    $originalContent = $content
    
    # Replace withValues(alpha: X) with withOpacity(X)
    # Pattern: .withValues(alpha: 0.X)
    $content = $content -replace '\.withValues\(alpha:\s*([0-9.]+)\)', '.withOpacity($1)'
    
    if ($content -ne $originalContent) {
        Set-Content -Path $file.FullName -Value $content -NoNewline
        $changes = ([regex]::Matches($originalContent, 'withValues')).Count
        Write-Host "  Fixed $changes occurrences in $($file.Name)" -ForegroundColor Green
        $totalFixed += $changes
    }
}

Write-Host ""
Write-Host "Total fixed: $totalFixed occurrences" -ForegroundColor Green
Write-Host "Done!" -ForegroundColor Cyan
