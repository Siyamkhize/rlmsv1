# Quick Start Setup - Copy & Paste Instructions

This guide provides the FASTEST way to complete your CI/CD setup. Just follow these steps in order.

---

## ⚡ Quick Setup (15 minutes)

### Step 1: Run the Interactive Setup Script

Open PowerShell in your project folder and run:

```powershell
cd c:\projects\rlmssv1
.\scripts\interactive-setup.ps1
```

**This script will:**
- Open each service in your browser
- Guide you through account creation
- Collect your tokens
- Save them securely
- Generate GitHub secrets instructions
- Open GitHub pages for you

**Just follow the prompts!**

---

## 🔑 If You Prefer Manual Setup

### Part A: Get Your Tokens (5 minutes)

#### 1. SonarCloud Token
```
1. Go to: https://sonarcloud.io/sessions/new
2. Log in with GitHub
3. Click '+' → 'Analyze new project' → Select 'Siyamkhize/rlmsv1' → 'Set Up'
4. Go to: https://sonarcloud.io/account/security
5. Generate token named 'RLMS_GitHub_Actions'
6. Copy the token and save it
```

#### 2. Snyk Token
```
1. Go to: https://app.snyk.io/signup
2. Sign up with GitHub
3. Add project: Select GitHub → 'Siyamkhize/rlmsv1'
4. Go to: https://app.snyk.io/account
5. Click 'click to show' under API Token
6. Copy the token and save it
```

#### 3. Codecov Token
```
1. Go to: https://codecov.io/signup
2. Sign up with GitHub
3. Add repository: 'Siyamkhize/rlmsv1'
4. Copy the upload token shown
5. Save it
```

### Part B: Add Secrets to GitHub (3 minutes)

Go to: https://github.com/Siyamkhize/rlmsv1/settings/secrets/actions

Click "New repository secret" and add each:

| Name | Value |
|------|-------|
| `SONAR_TOKEN` | [Your SonarCloud token] |
| `SONAR_HOST_URL` | `https://sonarcloud.io` |
| `SNYK_TOKEN` | [Your Snyk token] |
| `CODECOV_TOKEN` | [Your Codecov token] |

### Part C: Set Branch Protection (5 minutes)

Go to: https://github.com/Siyamkhize/rlmsv1/settings/branches

#### For `main` branch:
```
1. Click "Add rule"
2. Branch name pattern: main
3. Check:
   ☑ Require a pull request before merging
     - Required approvals: 1
   ☑ Require status checks to pass before merging
     - Add: security-and-quality
     - Add: test  
     - Add: build-android
   ☑ Require branches to be up to date before merging
4. Click "Create"
```

#### For `staging` branch:
```
1. Click "Add rule"
2. Branch name pattern: staging
3. Check:
   ☑ Require a pull request before merging
   ☑ Require status checks to pass before merging
     - Add: security-and-quality
     - Add: test
4. Click "Create"
```

### Part D: Test It Works (2 minutes)

Go to: https://github.com/Siyamkhize/rlmsv1/actions

```
1. Click "CI/CD Pipeline"
2. Click "Run workflow" (top right)
3. Select branch: main
4. Click "Run workflow"
5. Watch it run!
```

---

## 🎯 Verification Checklist

After setup, verify each:

### GitHub Secrets ✓
Go to: https://github.com/Siyamkhize/rlmsv1/settings/secrets/actions

You should see:
- ✓ SONAR_TOKEN
- ✓ SONAR_HOST_URL
- ✓ SNYK_TOKEN
- ✓ CODECOV_TOKEN

### Branch Protection ✓
Go to: https://github.com/Siyamkhize/rlmsv1/settings/branches

You should see rules for:
- ✓ main
- ✓ staging

### External Services ✓
Check these dashboards:
- ✓ SonarCloud: https://sonarcloud.io/dashboard?id=Siyamkhize_rlmsv1
- ✓ Snyk: https://app.snyk.io/
- ✓ Codecov: https://codecov.io/gh/Siyamkhize/rlmsv1

### GitHub Actions ✓
Go to: https://github.com/Siyamkhize/rlmsv1/actions

You should see:
- ✓ At least one workflow run
- ✓ All checks passing (green)

---

## 🚨 Quick Fixes

### "Secret not found" error
→ Double-check secret names are EXACT (case-sensitive)
→ Go back to: https://github.com/Siyamkhize/rlmsv1/settings/secrets/actions

### Workflow won't run
→ Make sure you clicked "Run workflow" button
→ Check you selected correct branch
→ Refresh the page

### Can't add branch protection
→ Make sure you're repository admin
→ Check branch name is exactly: `main` or `staging`

### Service won't connect
→ Re-authorize the GitHub connection in each service
→ Check repository is imported/added correctly

---

## 🎉 You're Done!

When all checkboxes above are ✓, your CI/CD is complete!

**What happens now:**
- Every commit is automatically scanned for security issues
- SQL injection attempts are blocked
- Tests must pass before deployment
- Code quality is tracked
- Coverage is measured

**Next:** Just code normally! The pipeline handles everything automatically.

---

## 📞 Need Help?

If stuck, check the detailed guide: `COMPLETE_SETUP_GUIDE.md`

Or review troubleshooting: Step 9 in `COMPLETE_SETUP_GUIDE.md`
