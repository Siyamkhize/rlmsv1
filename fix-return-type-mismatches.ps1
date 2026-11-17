# Fix return type mismatches in context.mounted checks
# Targets 91 instances where 'return null;' is used in non-nullable functions

$files = @(
    "lib\backup_clock_in_page.dart",        # 41 instances
    "lib\DetailsPage.dart",                  # 15 instances
    "lib\DetailsPage_server.dart",           # 12 instances
    "lib\POECollectionPage.dart",            # 12 instances
    "lib\LearnerListPage.dart",              # 7 instances
    "lib\sick_note_page.dart",               # 5 instances
    "lib\LearnerDetailsPage - Copy.dart",    # 2 instances
    "lib\FacilitatorProfile.dart"            # 1 instance
)

$fixCount = 0
$totalFiles = 0

foreach ($file in $files) {
    $path = Join-Path $PSScriptRoot $file
    
    if (-not (Test-Path $path)) {
        Write-Host "Skipping $file (not found)" -ForegroundColor Yellow
        continue
    }
    
    Write-Host "`nProcessing: $file" -ForegroundColor Cyan
    
    $content = Get-Content $path -Raw -Encoding UTF8
    $originalContent = $content
    
    # Track current function context
    $lines = $content -split "`r?`n"
    $newLines = @()
    $currentFunction = $null
    $currentReturnType = $null
    $inFunction = $false
    $braceDepth = 0
    $fileFixCount = 0
    
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        
        # Detect function declarations with return types (including Future<File?> for nullable)
        if ($line -match '^\s*(Future<bool>|bool|Future<void>|Future<int>|Future<String>|Future<File\?>|int|String)\s+(\w+)\s*\(') {
            $currentReturnType = $matches[1]
            $currentFunction = $matches[2]
            $inFunction = $true
            $braceDepth = 0
        }
        
        # Track brace depth to know when we exit the function
        $openBraces = ([regex]::Matches($line, '\{')).Count
        $closeBraces = ([regex]::Matches($line, '\}')).Count
        
        if ($inFunction) {
            $braceDepth += $openBraces - $closeBraces
            
            # If we're in a function and find 'if (!context.mounted) return null;'
            # This pattern now handles cases where the check is on the same line as other code
            if ($line -match 'if\s*\(\s*!context\.mounted\s*\)\s*return\s+null\s*;') {
                
                # Determine correct return value based on function return type
                $correctReturn = switch -Regex ($currentReturnType) {
                    '^Future<bool>$' { 'return false;' }
                    '^bool$' { 'return false;' }
                    '^Future<void>$' { 'return;' }
                    '^Future<int>$' { 'return 0;' }
                    '^int$' { 'return 0;' }
                    '^Future<String>$' { 'return "";' }
                    '^String$' { 'return "";' }
                    '^Future<File\?>$' { 'return null;' }  # Keep for nullable types
                    default { 'return null;' }  # Keep for nullable/unknown types
                }
                
                # Only fix if we have a non-null return value
                if ($correctReturn -ne 'return null;') {
                    $newLine = $line -replace 'if\s*\(\s*!context\.mounted\s*\)\s*return\s+null\s*;', "if (!context.mounted) $correctReturn"
                    if ($newLine -ne $line) {
                        Write-Host "  Line $($i+1): $currentFunction ($currentReturnType)" -ForegroundColor Green
                        Write-Host "    Before: $($line.Trim())" -ForegroundColor DarkGray
                        Write-Host "    After:  $($newLine.Trim())" -ForegroundColor Green
                        $line = $newLine
                        $fileFixCount++
                        $fixCount++
                    }
                }
            }
            
            # Exit function when braces balance
            if ($braceDepth -le 0 -and $openBraces -eq 0) {
                $inFunction = $false
                $currentFunction = $null
                $currentReturnType = $null
            }
        }
        
        $newLines += $line
    }
    
    # Write back if changes were made
    if ($fileFixCount -gt 0) {
        $newContent = $newLines -join "`n"
        Set-Content -Path $path -Value $newContent -Encoding UTF8 -NoNewline
        Write-Host "  Fixed $fileFixCount instances in $file" -ForegroundColor Green
        $totalFiles++
    } else {
        Write-Host "  No changes needed in $file" -ForegroundColor Gray
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Total fixes applied: $fixCount across $totalFiles files" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
