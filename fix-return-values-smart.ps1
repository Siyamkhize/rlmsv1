# Smart function signature analysis to fix return values in mounted checks
# Analyzes function signatures to determine correct return value

$ErrorActionPreference = "Stop"

Write-Host "Starting smart function signature analysis..." -ForegroundColor Cyan
Write-Host ""

# Get all dart files
$allFiles = Get-ChildItem -Path "lib" -Filter "*.dart" -Recurse

$totalFilesFixed = 0
$totalLinesFixed = 0
$fixesByType = @{
    "bool" = 0
    "void" = 0
    "nullable" = 0
}

foreach ($file in $allFiles) {
    $lines = Get-Content $file.FullName -Encoding UTF8
    $modified = $false
    
    # Track current function context
    $currentFunctionReturnType = $null
    $braceDepth = 0
    $inFunction = $false
    
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        
        # Detect function signature with return type
        if ($line -match '^\s*(Future<([^>]+)>)\s+(\w+)\s*\(') {
            $fullType = $matches[1]
            $innerType = $matches[2]
            $functionName = $matches[3]
            
            # Determine the return type category
            if ($innerType -eq 'void') {
                $currentFunctionReturnType = 'void'
            }
            elseif ($innerType -eq 'bool') {
                $currentFunctionReturnType = 'bool'
            }
            elseif ($innerType -match '\?$') {
                # Nullable type (e.g., String?, File?, Map?)
                $currentFunctionReturnType = 'nullable'
            }
            else {
                # Non-nullable, non-bool type - keep null for safety
                $currentFunctionReturnType = 'nullable'
            }
            
            $inFunction = $true
            $braceDepth = 0
        }
        
        # Track brace depth when in a function
        if ($inFunction) {
            $openBraces = ($line.ToCharArray() | Where-Object { $_ -eq '{' }).Count
            $closeBraces = ($line.ToCharArray() | Where-Object { $_ -eq '}' }).Count
            $braceDepth += $openBraces - $closeBraces
            
            # Check if this line has a mounted check with wrong return value
            if ($line -match '^\s+if \(!context\.mounted\) return (null|false)?;') {
                $currentReturn = $matches[1]
                
                # Determine correct return value based on function type
                $correctReturn = switch ($currentFunctionReturnType) {
                    'void' { '' }
                    'bool' { 'false' }
                    'nullable' { 'null' }
                    default { 'null' }  # Safe default
                }
                
                # Build the correct statement
                $correctStatement = if ($correctReturn -eq '') {
                    'if (!context.mounted) return;'
                } else {
                    "if (!context.mounted) return $correctReturn;"
                }
                
                # Check if fix is needed
                $needsFix = $false
                if ($currentFunctionReturnType -eq 'bool' -and $currentReturn -ne 'false') {
                    $needsFix = $true
                    $fixesByType["bool"]++
                }
                elseif ($currentFunctionReturnType -eq 'void' -and $currentReturn -ne $null) {
                    $needsFix = $true
                    $fixesByType["void"]++
                }
                elseif ($currentFunctionReturnType -eq 'nullable' -and $currentReturn -eq 'false') {
                    $needsFix = $true
                    $fixesByType["nullable"]++
                }
                
                if ($needsFix) {
                    $lines[$i] = $line -replace 'if \(!context\.mounted\) return (null|false)?;', $correctStatement
                    $modified = $true
                    $totalLinesFixed++
                }
            }
            
            # Exit function when braces balance back to 0 or negative
            if ($braceDepth -le 0 -and $openBraces -eq 0 -and $closeBraces -gt 0) {
                $inFunction = $false
                $currentFunctionReturnType = $null
            }
        }
    }
    
    if ($modified) {
        Set-Content -Path $file.FullName -Value $lines -Encoding UTF8
        $relPath = $file.FullName -replace [regex]::Escape("$PWD\"), ''
        Write-Host "[FIXED] $relPath" -ForegroundColor Green
        $totalFilesFixed++
    }
}

Write-Host ""
Write-Host "================================" -ForegroundColor Cyan
Write-Host "Smart Return Value Fix Complete!" -ForegroundColor Green
Write-Host "Files fixed: $totalFilesFixed" -ForegroundColor White
Write-Host "Lines fixed: $totalLinesFixed" -ForegroundColor White
Write-Host ""
Write-Host "Fixes by type:" -ForegroundColor Yellow
Write-Host "  Future<bool> -> return false: $($fixesByType['bool'])" -ForegroundColor White
Write-Host "  Future<void> -> return: $($fixesByType['void'])" -ForegroundColor White
Write-Host "  Future<T?> -> return null: $($fixesByType['nullable'])" -ForegroundColor White
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next: Run flutter analyze to verify" -ForegroundColor Yellow
