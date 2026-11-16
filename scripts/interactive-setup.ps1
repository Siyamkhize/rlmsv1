# Interactive CI/CD Setup Script for RLMS
# This script will guide you through the entire setup process

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  RLMS CI/CD Interactive Setup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "This script will help you set up:" -ForegroundColor Yellow
Write-Host "  1. SonarCloud integration"
Write-Host "  2. Snyk security scanning"
Write-Host "  3. Codecov coverage tracking"
Write-Host "  4. GitHub repository secrets"
Write-Host "  5. Branch protection rules"
Write-Host ""
Write-Host "Press any key to continue or Ctrl+C to cancel..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

# Function to open URL in browser
function Open-Browser {
    param([string]$Url)
    Start-Process $Url
}

# Function to prompt for input with validation
function Get-ValidatedInput {
    param(
        [string]$Prompt,
        [string]$ValidationPattern = ".*",
        [string]$ErrorMessage = "Invalid input. Please try again."
    )
    
    do {
        $input = Read-Host $Prompt
        if ($input -match $ValidationPattern) {
            return $input
        }
        Write-Host $ErrorMessage -ForegroundColor Red
    } while ($true)
}

# Step 1: SonarCloud Setup
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "STEP 1: SonarCloud Setup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`nOpening SonarCloud in your browser..." -ForegroundColor Yellow
Start-Sleep -Seconds 2
Open-Browser "https://sonarcloud.io/sessions/new"

Write-Host "`nPlease complete these steps in the browser:" -ForegroundColor Green
Write-Host "  1. Log in with GitHub"
Write-Host "  2. Click the '+' icon and select 'Analyze new project'"
Write-Host "  3. Select 'Siyamkhize/rlmsv1'"
Write-Host "  4. Click 'Set Up' and choose 'With GitHub Actions'"
Write-Host "`nPress any key when done..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

Write-Host "`nNow we need your SonarCloud token..." -ForegroundColor Yellow
Write-Host "Opening token generation page..." -ForegroundColor Yellow
Start-Sleep -Seconds 2
Open-Browser "https://sonarcloud.io/account/security"

Write-Host "`nIn the browser:" -ForegroundColor Green
Write-Host "  1. Enter token name: 'RLMS_GitHub_Actions'"
Write-Host "  2. Click 'Generate'"
Write-Host "  3. Copy the token"
Write-Host ""

$sonarToken = Get-ValidatedInput -Prompt "9425cbd42754ec4f9c0338cbe1f0fedd065c2855" -ValidationPattern ".{20,}"
$sonarUrl = "https://sonarcloud.io"

Write-Host "✓ SonarCloud token saved!" -ForegroundColor Green

# Step 2: Snyk Setup
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "STEP 2: Snyk Setup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`nOpening Snyk in your browser..." -ForegroundColor Yellow
Start-Sleep -Seconds 2
Open-Browser "https://app.snyk.io/signup"

Write-Host "`nPlease complete these steps in the browser:" -ForegroundColor Green
Write-Host "  1. Sign up with GitHub (or log in if you have an account)"
Write-Host "  2. Click 'Add project'"
Write-Host "  3. Select 'GitHub'"
Write-Host "  4. Find and select 'Siyamkhize/rlmsv1'"
Write-Host "  5. Click 'Add selected repositories'"
Write-Host "`nPress any key when done..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

Write-Host "`nOpening Snyk token page..." -ForegroundColor Yellow
Start-Sleep -Seconds 2
Open-Browser "https://app.snyk.io/account"

Write-Host "`nIn the browser:" -ForegroundColor Green
Write-Host "  1. Scroll to 'API Token' section"
Write-Host "  2. Click 'click to show'"
Write-Host "  3. Click the copy icon"
Write-Host ""

$snykToken = Get-ValidatedInput -Prompt "snyk_uat.1fcad39e.eyJlIjoxODAyNjAxNjYzLCJoIjoic255ay5pbyIsImoiOiJBYUhqOG5uaDJTcEE2M1EyZWhtSmdBIiwicyI6ImZVeW5CNElzUmJhejk4UGFmUXZqWkEiLCJ0aWQiOiJBQUFBQUFBQUFBQUFBQUFBQUFBQUFBIn0.BItODQ7nBFTROCh5uf2G27vyQwBNGjn_Um8oIv_JxN-4vkEkZicN6KZ0uu3gvlxdjs-NQqVNsYYDn0ft5ziPCg" -ValidationPattern ".{30,}"

Write-Host "✓ Snyk token saved!" -ForegroundColor Green

# Step 3: Codecov Setup
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "STEP 3: Codecov Setup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`nOpening Codecov in your browser..." -ForegroundColor Yellow
Start-Sleep -Seconds 2
Open-Browser "https://codecov.io/signup"

Write-Host "`nPlease complete these steps in the browser:" -ForegroundColor Green
Write-Host "  1. Sign up with GitHub (or log in)"
Write-Host "  2. Click 'Add a repository'"
Write-Host "  3. Find 'Siyamkhize/rlmsv1'"
Write-Host "  4. Click 'Setup repo'"
Write-Host "  5. Copy the upload token shown"
Write-Host "`nPress any key when done..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

$codecovToken = Get-ValidatedInput -Prompt "Paste your CODECOV_TOKEN here" -ValidationPattern ".{30,}"

Write-Host "✓ Codecov token saved!" -ForegroundColor Green

# Step 4: Save tokens to a secure file
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "STEP 4: Saving Configuration" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$configDir = "$HOME\.rlms-config"
New-Item -ItemType Directory -Force -Path $configDir | Out-Null

$config = @{
    SONAR_TOKEN = $sonarToken
    SONAR_HOST_URL = $sonarUrl
    SNYK_TOKEN = $snykToken
    CODECOV_TOKEN = $codecovToken
    CREATED = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
}

$configFile = "$configDir\secrets.json"
$config | ConvertTo-Json | Out-File -FilePath $configFile -Encoding UTF8

Write-Host "✓ Configuration saved to: $configFile" -ForegroundColor Green

# Step 5: Generate commands for GitHub Secrets
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "STEP 5: GitHub Secrets Setup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`nOpening GitHub repository secrets page..." -ForegroundColor Yellow
Start-Sleep -Seconds 2
Open-Browser "https://github.com/Siyamkhize/rlmsv1/settings/secrets/actions"

Write-Host "`nYou need to add these secrets manually in GitHub:" -ForegroundColor Yellow
Write-Host "======================================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "Secret 1: SONAR_TOKEN" -ForegroundColor Cyan
Write-Host "Value: $sonarToken" -ForegroundColor White
Write-Host ""
Write-Host "Secret 2: SONAR_HOST_URL" -ForegroundColor Cyan
Write-Host "Value: $sonarUrl" -ForegroundColor White
Write-Host ""
Write-Host "Secret 3: SNYK_TOKEN" -ForegroundColor Cyan
Write-Host "Value: $snykToken" -ForegroundColor White
Write-Host ""
Write-Host "Secret 4: CODECOV_TOKEN" -ForegroundColor Cyan
Write-Host "Value: $codecovToken" -ForegroundColor White
Write-Host ""
Write-Host "======================================================" -ForegroundColor Yellow

# Save instructions to a file
$instructionsFile = "$PWD\GITHUB_SECRETS_TO_ADD.txt"
@"
GitHub Secrets to Add
====================
Repository: https://github.com/Siyamkhize/rlmsv1/settings/secrets/actions

Add these secrets by clicking "New repository secret":

1. SONAR_TOKEN
   Value: $sonarToken

2. SONAR_HOST_URL
   Value: $sonarUrl

3. SNYK_TOKEN
   Value: $snykToken

4. CODECOV_TOKEN
   Value: $codecovToken

How to add:
1. Click "New repository secret"
2. Enter the Name (e.g., SONAR_TOKEN)
3. Paste the Value
4. Click "Add secret"
5. Repeat for each secret above

Created: $(Get-Date)
"@ | Out-File -FilePath $instructionsFile -Encoding UTF8

Write-Host "✓ Instructions saved to: $instructionsFile" -ForegroundColor Green
Write-Host "`nPress any key after you've added all secrets in GitHub..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

# Step 6: Branch Protection Setup
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "STEP 6: Branch Protection Rules" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`nOpening GitHub branch protection page..." -ForegroundColor Yellow
Start-Sleep -Seconds 2
Open-Browser "https://github.com/Siyamkhize/rlmsv1/settings/branches"

Write-Host "`nPlease set up branch protection rules:" -ForegroundColor Yellow
Write-Host ""
Write-Host "For MAIN branch:" -ForegroundColor Cyan
Write-Host "  1. Click 'Add rule'"
Write-Host "  2. Branch name pattern: main"
Write-Host "  3. Check: 'Require a pull request before merging'"
Write-Host "  4. Required approvals: 1"
Write-Host "  5. Check: 'Require status checks to pass before merging'"
Write-Host "  6. Add required checks: security-and-quality, test, build-android"
Write-Host "  7. Check: 'Require branches to be up to date before merging'"
Write-Host "  8. Click 'Create'"
Write-Host ""
Write-Host "For STAGING branch:" -ForegroundColor Cyan
Write-Host "  1. Click 'Add rule'"
Write-Host "  2. Branch name pattern: staging"
Write-Host "  3. Check: 'Require a pull request before merging'"
Write-Host "  4. Check: 'Require status checks to pass before merging'"
Write-Host "  5. Add required checks: security-and-quality, test"
Write-Host "  6. Click 'Create'"
Write-Host ""
Write-Host "Press any key when done..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

# Step 7: Test the setup
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "STEP 7: Testing the Setup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`nOpening GitHub Actions page..." -ForegroundColor Yellow
Start-Sleep -Seconds 2
Open-Browser "https://github.com/Siyamkhize/rlmsv1/actions"

Write-Host "`nLet's trigger a test workflow:" -ForegroundColor Yellow
Write-Host "  1. Click 'CI/CD Pipeline' in the left sidebar"
Write-Host "  2. Click 'Run workflow' button (top right)"
Write-Host "  3. Select branch: main"
Write-Host "  4. Click 'Run workflow'"
Write-Host "  5. Wait for the workflow to start"
Write-Host "  6. Click on the workflow run to see progress"
Write-Host ""
Write-Host "Press any key when workflow starts running..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

# Final Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "SETUP COMPLETE!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "✓ SonarCloud configured" -ForegroundColor Green
Write-Host "✓ Snyk configured" -ForegroundColor Green
Write-Host "✓ Codecov configured" -ForegroundColor Green
Write-Host "✓ GitHub secrets documented" -ForegroundColor Green
Write-Host "✓ Branch protection rules documented" -ForegroundColor Green
Write-Host ""
Write-Host "Configuration files saved:" -ForegroundColor Yellow
Write-Host "  - $configFile"
Write-Host "  - $instructionsFile"
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "  1. Verify workflow run completes successfully"
Write-Host "  2. Check SonarCloud dashboard for code quality"
Write-Host "  3. Check Snyk dashboard for vulnerabilities"
Write-Host "  4. Check Codecov for coverage reports"
Write-Host ""
Write-Host "Dashboards:" -ForegroundColor Cyan
Write-Host "  SonarCloud: https://sonarcloud.io/dashboard?id=Siyamkhize_rlmsv1"
Write-Host "  Snyk: https://app.snyk.io/"
Write-Host "  Codecov: https://codecov.io/gh/Siyamkhize/rlmsv1"
Write-Host "  GitHub Actions: https://github.com/Siyamkhize/rlmsv1/actions"
Write-Host ""
Write-Host "Need help? Check COMPLETE_SETUP_GUIDE.md for troubleshooting" -ForegroundColor Yellow
Write-Host ""
Write-Host "Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
