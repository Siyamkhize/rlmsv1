# CI/CD Status Checker
# Checks GitHub Actions workflow status via API

Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║         CI/CD Status Checker for RLMSS Project              ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Get latest commit
$latestCommit = git rev-parse --short HEAD
$branch = git branch --show-current

Write-Host "📊 Current Status:" -ForegroundColor Yellow
Write-Host "   Branch: $branch"
Write-Host "   Commit: $latestCommit"
Write-Host ""

# Try to fetch GitHub Actions status via API
Write-Host "🔍 Fetching workflow status from GitHub..." -ForegroundColor Yellow
Write-Host ""

try {
    $owner = "Siyamkhize"
    $repo = "rlmsv1"
    $apiUrl = "https://api.github.com/repos/$owner/$repo/actions/runs?per_page=20&branch=$branch"
    
    Write-Host "   API URL: $apiUrl" -ForegroundColor Gray
    Write-Host ""
    
    # Fetch runs
    $response = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers @{
        "Accept" = "application/vnd.github.v3+json"
        "User-Agent" = "PowerShell-CICD-Checker"
    }
    
    if ($response.workflow_runs.Count -eq 0) {
        Write-Host "⚠️  No workflow runs found for branch: $branch" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "This might mean:"
        Write-Host "  - Workflows have not started yet (wait 1-2 minutes)"
        Write-Host "  - Branch name mismatch"
        Write-Host "  - GitHub Actions not enabled"
        Write-Host ""
    } else {
        Write-Host "✅ Found $($response.workflow_runs.Count) recent workflow runs" -ForegroundColor Green
        Write-Host ""
        Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
        Write-Host "WORKFLOW STATUS REPORT" -ForegroundColor White
        Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
        Write-Host ""
        
        # Group by commit
        $runsByCommit = $response.workflow_runs | Group-Object -Property head_sha | Select-Object -First 3
        
        foreach ($commitGroup in $runsByCommit) {
            $shortSha = $commitGroup.Name.Substring(0, 7)
            $runs = $commitGroup.Group
            
            Write-Host "Commit: $shortSha" -ForegroundColor Cyan
            Write-Host "─────────────────────────────────────────────────────────" -ForegroundColor Gray
            
            foreach ($run in $runs) {
                $icon = switch ($run.conclusion) {
                    "success" { "✅" }
                    "failure" { "❌" }
                    "cancelled" { "⏹️" }
                    "skipped" { "⏭️" }
                    default {
                        if ($run.status -eq "in_progress") { "🔄" }
                        elseif ($run.status -eq "queued") { "⏳" }
                        else { "⚪" }
                    }
                }
                
                $color = switch ($run.conclusion) {
                    "success" { "Green" }
                    "failure" { "Red" }
                    "cancelled" { "Yellow" }
                    default { "White" }
                }
                
                $status = if ($run.conclusion) { $run.conclusion.ToUpper() } else { $run.status.ToUpper() }
                $duration = if ($run.conclusion) {
                    $start = [datetime]$run.created_at
                    $end = [datetime]$run.updated_at
                    $diff = $end - $start
                    "$($diff.Minutes)m $($diff.Seconds)s"
                } else {
                    "Running..."
                }
                
                Write-Host "  $icon " -NoNewline -ForegroundColor $color
                Write-Host "$($run.name.PadRight(35))" -NoNewline -ForegroundColor White
                Write-Host " $status" -NoNewline -ForegroundColor $color
                Write-Host " ($duration)" -ForegroundColor Gray
            }
            
            Write-Host ""
        }
        
        Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
        Write-Host ""
        
        # Summary
        $latestRuns = $response.workflow_runs | Where-Object { $_.head_sha -eq (git rev-parse HEAD) }
        if ($latestRuns) {
            Write-Host "📊 SUMMARY FOR CURRENT COMMIT ($latestCommit):" -ForegroundColor Yellow
            Write-Host ""
            
            $total = $latestRuns.Count
            $passed = ($latestRuns | Where-Object { $_.conclusion -eq "success" }).Count
            $failed = ($latestRuns | Where-Object { $_.conclusion -eq "failure" }).Count
            $running = ($latestRuns | Where-Object { $_.status -eq "in_progress" }).Count
            $queued = ($latestRuns | Where-Object { $_.status -eq "queued" }).Count
            
            Write-Host "   Total Workflows:  $total"
            Write-Host "   ✅ Passed:         $passed" -ForegroundColor Green
            if ($failed -gt 0) {
                Write-Host "   ❌ Failed:         $failed" -ForegroundColor Red
            }
            if ($running -gt 0) {
                Write-Host "   🔄 Running:        $running" -ForegroundColor Yellow
            }
            if ($queued -gt 0) {
                Write-Host "   ⏳ Queued:         $queued" -ForegroundColor Yellow
            }
            Write-Host ""
            
            if ($running -gt 0 -or $queued -gt 0) {
                Write-Host "⏱️  Workflows still in progress. Run this script again in a few minutes." -ForegroundColor Yellow
            } elseif ($failed -gt 0) {
                Write-Host "⚠️  Some workflows failed. Check logs for details." -ForegroundColor Red
            } else {
                Write-Host "🎉 All workflows completed successfully!" -ForegroundColor Green
            }
        }
    }
    
} catch {
    Write-Host "❌ Error fetching workflow status:" -ForegroundColor Red
    Write-Host "   $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "This might be due to:" -ForegroundColor Yellow
    Write-Host "  - Rate limiting (GitHub API has limits)" -ForegroundColor Yellow
    Write-Host "  - Network connectivity issues" -ForegroundColor Yellow
    Write-Host "  - Repository access restrictions" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "🌐 VIEW FULL DETAILS:" -ForegroundColor Yellow
Write-Host "   https://github.com/Siyamkhize/rlmsv1/actions" -ForegroundColor White
Write-Host ""
Write-Host "🔄 TO REFRESH: Run this script again" -ForegroundColor Yellow
Write-Host "   .\check-cicd-status.ps1" -ForegroundColor White
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# Ask to open browser
$openBrowser = Read-Host "Open GitHub Actions in browser? (Y/n)"
if ($openBrowser -ne "n" -and $openBrowser -ne "N") {
    Start-Process "https://github.com/Siyamkhize/rlmsv1/actions"
    Write-Host "✅ Browser opened!" -ForegroundColor Green
}
