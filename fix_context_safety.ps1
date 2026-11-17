# Script to add mounted checks after async operations
param(
    [string]$FilePath
)

$content = Get-Content -Path $FilePath -Raw
$lines = Get-Content -Path $FilePath

# Get all line numbers where we need to add checks
$lineNumbers = flutter analyze --no-fatal-infos 2>&1 | 
    Select-String -Pattern "$([regex]::Escape((Split-Path -Leaf $FilePath))).*use_build_context_synchronously" |
    ForEach-Object { 
        if ($_ -match ':(\d+):') { 
            [int]$matches[1] 
        } 
    } | Sort-Object -Descending -Unique

Write-Host "Found $($lineNumbers.Count) issues to fix in $FilePath"

foreach ($lineNum in $lineNumbers) {
    $line = $lines[$lineNum - 1]
    
    # Check if this line uses context
    if ($line -match '(Navigator\.|showDialog|showModalBottomSheet|ScaffoldMessenger\.of\(context\)|Theme\.of\(context\))') {
        # Look backwards to find the most recent await
        $lookBack = $lineNum - 1
        $foundAwait = $false
        
        while ($lookBack -gt 0 -and ($lineNum - $lookBack) -lt 50) {
            if ($lines[$lookBack - 1] -match '^\s*await ' -or $lines[$lookBack - 1] -match '\bawait\s') {
                $foundAwait = $true
                break
            }
            $lookBack--
        }
        
        if ($foundAwait) {
            # Check if mounted check already exists between await and context usage
            $hasCheck = $false
            for ($i = $lookBack; $i -lt $lineNum; $i++) {
                if ($lines[$i] -match 'if\s*\(.*!.*mounted.*\)') {
                    $hasCheck = $true
                    break
                }
            }
            
            if (-not $hasCheck) {
                Write-Host "Line $lineNum needs mounted check"
            }
        }
    }
}
