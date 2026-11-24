# CI/CD Status Checker for rlmsv1
# This script helps you monitor the GitHub Actions workflow status

Write-Host "=== CI/CD Status Checker ===" -ForegroundColor Cyan
Write-Host ""

# Get the latest commit
$latestCommit = git log -1 --pretty=format:"%h - %s"
Write-Host "Latest Commit: $latestCommit" -ForegroundColor Green
Write-Host ""

# Show repository URL
$repoUrl = "https://github.com/Siyamkhize/rlmsv1"
Write-Host "Repository: $repoUrl" -ForegroundColor Yellow
Write-Host "Actions Page: $repoUrl/actions" -ForegroundColor Yellow
Write-Host ""

# Expected workflows based on .github/workflows
Write-Host "Expected CI/CD Workflows:" -ForegroundColor Cyan
if (Test-Path ".github\workflows") {
    Get-ChildItem ".github\workflows" -Filter "*.yml" | ForEach-Object {
        Write-Host "  ✓ $($_.BaseName)" -ForegroundColor Green
    }
} else {
    Write-Host "  No workflows found" -ForegroundColor Red
}
Write-Host ""

# Show recent changes that will be tested
Write-Host "Recent Changes (Last 3 commits):" -ForegroundColor Cyan
git log -3 --pretty=format:"%h - %s (%cr)" --abbrev-commit
Write-Host ""
Write-Host ""

# Instructions
Write-Host "To check CI/CD status:" -ForegroundColor Yellow
Write-Host "  1. Open: $repoUrl/actions" -ForegroundColor White
Write-Host "  2. Look for the workflow run for commit: 4969c55" -ForegroundColor White
Write-Host "  3. Check if all workflows show green checkmarks" -ForegroundColor White
Write-Host ""
Write-Host "Opening GitHub Actions page in browser..." -ForegroundColor Cyan
Start-Process "$repoUrl/actions"
