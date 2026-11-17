# PowerShell script to fix "return_without_value" errors in mounted checks
# This fixes cases where "if (!context.mounted) return;" needs to return a value

$ErrorActionPreference = "Stop"

Write-Host "Analyzing return_without_value errors..." -ForegroundColor Cyan

# Get all return_without_value errors from flutter analyze
$analyzeOutput = flutter analyze --no-fatal-infos 2>&1 | Out-String
$errors = $analyzeOutput -split "`n" | Where-Object { $_ -match "error.*return_without_value" }

Write-Host "Found $($errors.Count) return_without_value errors" -ForegroundColor Yellow
Write-Host ""

$fixedCount = 0
$errorsByFile = @{}

# Group errors by file
foreach ($error in $errors) {
    if ($error -match '- (lib\\[^:]+):(\d+):\d+ - return_without_value') {
        $file = $matches[1]
        $line = [int]$matches[2]
        
        if (-not $errorsByFile.ContainsKey($file)) {
            $errorsByFile[$file] = @()
        }
        $errorsByFile[$file] += $line
    }
}

Write-Host "Processing $($errorsByFile.Count) files..." -ForegroundColor Cyan
Write-Host ""

foreach ($file in $errorsByFile.Keys | Sort-Object) {
    $fullPath = Join-Path $PSScriptRoot $file
    
    if (-not (Test-Path $fullPath)) {
        Write-Host "  [SKIP] File not found: $file" -ForegroundColor Yellow
        continue
    }
    
    Write-Host "Processing: $file" -ForegroundColor Gray
    
    $lines = Get-Content $fullPath -Encoding UTF8
    $modified = $false
    
    # Sort line numbers in descending order to avoid offset issues
    $errorLines = $errorsByFile[$file] | Sort-Object -Descending
    
    foreach ($lineNum in $errorLines) {
        $lineIndex = $lineNum - 1
        
        if ($lineIndex -ge 0 -and $lineIndex -lt $lines.Count) {
            $line = $lines[$lineIndex]
            
            # Check if this is a mounted check without return value
            if ($line -match '^\s+if \(!context\.mounted\) return;\s*$') {
                # Look backwards to find the function signature
                $functionReturnType = $null
                
                for ($i = $lineIndex - 1; $i -ge [Math]::Max(0, $lineIndex - 50); $i--) {
                    if ($lines[$i] -match 'Future<([^>]+)>|^  \w+\??') {
                        if ($lines[$i] -match 'Future<void>') {
                            # Already correct - void returns don't need a value
                            break
                        }
                        elseif ($lines[$i] -match 'Future<[^>]*\?') {
                            # Returns nullable type - use null
                            $lines[$lineIndex] = $line -replace 'return;', 'return null;'
                            $modified = $true
                            $fixedCount++
                            Write-Host "  Line $($lineNum): Fixed to return null" -ForegroundColor Green
                            break
                        }
                        elseif ($lines[$i] -match 'Future<bool>') {
                            # Returns bool - use false
                            $lines[$lineIndex] = $line -replace 'return;', 'return false;'
                            $modified = $true
                            $fixedCount++
                            Write-Host "  Line $($lineNum): Fixed to return false" -ForegroundColor Green
                            break
                        }
                        elseif ($lines[$i] -match 'Future<String>') {
                            # Returns String - use empty string
                            $lines[$lineIndex] = $line -replace 'return;', "return '';"
                            $modified = $true
                            $fixedCount++
                            Write-Host "  Line $($lineNum): Fixed to return empty string" -ForegroundColor Green
                            break
                        }
                        elseif ($lines[$i] -match 'Future<int>') {
                            # Returns int - use 0
                            $lines[$lineIndex] = $line -replace 'return;', 'return 0;'
                            $modified = $true
                            $fixedCount++
                            Write-Host "  Line $($lineNum): Fixed to return 0" -ForegroundColor Green
                            break
                        }
                        else {
                            # For other types, try null (might need manual review)
                            $lines[$lineIndex] = $line -replace 'return;', 'return null;'
                            $modified = $true
                            $fixedCount++
                            Write-Host "  Line $($lineNum): Fixed to return null (may need review)" -ForegroundColor Yellow
                            break
                        }
                    }
                }
            }
        }
    }
    
    if ($modified) {
        Set-Content -Path $fullPath -Value $lines -Encoding UTF8
        Write-Host "  [SAVED] Updated $file" -ForegroundColor Green
    } else {
        Write-Host "  [SKIP] No changes needed" -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host "================================" -ForegroundColor Cyan
Write-Host "Return Value Fix Complete!" -ForegroundColor Green
Write-Host "Total fixes applied: $fixedCount" -ForegroundColor White
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next step: Run flutter analyze again to verify" -ForegroundColor Yellow
