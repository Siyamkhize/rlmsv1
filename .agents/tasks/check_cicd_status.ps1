# CI/CD Status Checker
# Checks the latest workflow runs for the repository

Write-Host "🔍 CI/CD Status Checker" -ForegroundColor Cyan
Write-Host "========================`n" -ForegroundColor Cyan

$repo = "Siyamkhize/rlmsv1"
$branch = "main"

Write-Host "Repository: $repo" -ForegroundColor Yellow
Write-Host "Branch: $branch" -ForegroundColor Yellow
Write-Host "Latest Commit: 847e11e`n" -ForegroundColor Yellow

Write-Host "📊 Checking workflow status...`n" -ForegroundColor Green

# Check if gh CLI is available
if (Get-Command gh -ErrorAction SilentlyContinue) {
    Write-Host "✅ GitHub CLI found - fetching real-time status`n" -ForegroundColor Green
    
    Write-Host "Latest Workflow Runs:" -ForegroundColor Cyan
    Write-Host "--------------------" -ForegroundColor Cyan
    gh run list --repo $repo --branch $branch --limit 10
    
    Write-Host "`n`nDetailed Status of Latest Run:" -ForegroundColor Cyan
    Write-Host "------------------------------" -ForegroundColor Cyan
    gh run view --repo $repo --log-failed
    
} else {
    Write-Host "⚠️  GitHub CLI (gh) not installed" -ForegroundColor Yellow
    Write-Host "`nInstall with: winget install GitHub.cli" -ForegroundColor Gray
    Write-Host "Or visit: https://cli.github.com/`n" -ForegroundColor Gray
    
    Write-Host "📱 Manual Monitoring:" -ForegroundColor Cyan
    Write-Host "--------------------" -ForegroundColor Cyan
    Write-Host "1. All Workflows: https://github.com/$repo/actions" -ForegroundColor White
    Write-Host "2. Dart CI: https://github.com/$repo/actions/workflows/dart.yml" -ForegroundColor White
    Write-Host "3. Comprehensive: https://github.com/$repo/actions/workflows/comprehensive-cicd.yml" -ForegroundColor White
    Write-Host "4. PHP CI: https://github.com/$repo/actions/workflows/php.yml" -ForegroundColor White
    Write-Host "5. CodeQL: https://github.com/$repo/actions/workflows/codeql.yml" -ForegroundColor White
    
    Write-Host "`n🌐 Opening GitHub Actions in browser..." -ForegroundColor Green
    Start-Process "https://github.com/$repo/actions"
}

Write-Host "`n✅ Check complete!" -ForegroundColor Green
Write-Host "`nExpected Results:" -ForegroundColor Cyan
Write-Host "- ✅ Dart CI: Analyze + Build (3 flavors)" -ForegroundColor White
Write-Host "- ✅ Comprehensive CI/CD: Full pipeline" -ForegroundColor White
Write-Host "- ✅ PHP CI: Syntax and quality checks" -ForegroundColor White
Write-Host "- ✅ CodeQL: Security analysis" -ForegroundColor White
Write-Host "- ✅ Performance: Quality gates" -ForegroundColor White
Write-Host "`n📦 Expected Artifacts: 6 APK downloads (3 from Dart CI, 3 from Comprehensive)" -ForegroundColor Cyan
Write-Host "⏱️  Total Duration: ~45-60 minutes for full pipeline" -ForegroundColor Cyan
