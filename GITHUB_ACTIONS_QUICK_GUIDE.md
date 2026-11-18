# GitHub Actions Quick Reference Guide

## 🌐 View Your CI/CD Dashboard

**Main Link:** [https://github.com/Siyamkhize/rlmsv1/actions](https://github.com/Siyamkhize/rlmsv1/actions)

---

## 📋 Your Active Workflows (8 Total)

### 1. **Dart CI** ⭐ Main Flutter Workflow
- **File:** `.github/workflows/dart.yml`
- **Triggers:** Push/PR to main or development
- **What it does:**
  - ✓ Flutter analyze (checks code quality)
  - ✓ Builds debug APK
  - ✓ Validates no blocking errors
- **Expected Result:** ✅ PASS (1 non-blocking warning is OK)

### 2. **CI/CD Pipeline** ⭐ Comprehensive Checks
- **File:** `.github/workflows/ci-cd-pipeline.yml`
- **Triggers:** Push/PR to main, develop, staging
- **What it does:**
  - ✓ Security audit
  - ✓ Flutter analyze
  - ✓ Unit tests with coverage
  - ✓ Builds APK (release)
  - ✓ Optional: SonarQube, Snyk (if tokens configured)
- **Expected Result:** ✅ PASS

### 3. **CodeQL**
- **File:** `.github/workflows/codeql.yml`
- **Triggers:** Push/PR, scheduled
- **What it does:** Advanced security scanning
- **Expected Result:** ✅ PASS

### 4. **Dependency Review**
- **File:** `.github/workflows/dependency-review.yml`
- **Triggers:** Pull requests only
- **What it does:** Checks for vulnerable dependencies
- **Expected Result:** ✅ PASS

### 5. **Quality Gate**
- **File:** `.github/workflows/quality-gate.yml`
- **Triggers:** Push/PR
- **What it does:** Code quality metrics
- **Expected Result:** ✅ PASS

### 6. **Nightly Security Scan**
- **File:** `.github/workflows/nightly-security-scan.yml`
- **Triggers:** Scheduled (nightly)
- **What it does:** Regular security checks
- **Expected Result:** ✅ PASS

### 7. **PHP CI**
- **File:** `.github/workflows/php.yml`
- **Triggers:** Push/PR (PHP files)
- **What it does:** PHP syntax checks
- **Expected Result:** ✅ PASS

### 8. **CodeRabbit Review**
- **File:** `.github/workflows/coderabbit-review.yml`
- **Triggers:** Pull requests
- **What it does:** AI-powered code review
- **Status:** ⏳ Pending (requires app installation)
- **Setup:** See [CODERABBIT_SETUP.md](CODERABBIT_SETUP.md)

---

## 🚀 How to Trigger CI/CD

### Automatic Triggers
CI/CD runs automatically when you:

```bash
# Push to main or development branches
git push origin main

# Create or update a pull request
gh pr create --title "Feature X"
```

### Manual Trigger (via GitHub UI)
1. Go to [Actions tab](https://github.com/Siyamkhize/rlmsv1/actions)
2. Select a workflow (e.g., "Dart CI")
3. Click "Run workflow" button
4. Select branch and click "Run workflow"

### Manual Trigger (via CLI)
```bash
# Trigger with empty commit
git commit --allow-empty -m "ci: trigger workflow"
git push origin main
```

---

## 📊 Current Status

### Latest Commit
```
Commit: 1e5c10e
Message: docs: add GitHub Actions status explanation and trigger fresh CI run
Branch: main
Status: ✅ Pushed to GitHub
```

### Expected Results (This Run)
```
✅ Flutter Analyze:   PASS (1 non-blocking warning)
✅ Security Audit:    PASS (0 critical issues)
✅ Unit Tests:        PASS
✅ APK Build:         SUCCESS (159.96 MB)
```

---

## 🔍 How to Check Workflow Status

### Option 1: GitHub Web UI
1. Visit: [github.com/Siyamkhize/rlmsv1/actions](https://github.com/Siyamkhize/rlmsv1/actions)
2. See list of recent runs with status icons:
   - 🟢 Green checkmark = Passed
   - 🔴 Red X = Failed
   - 🟡 Yellow circle = Running
   - ⚪ Gray circle = Queued

### Option 2: GitHub CLI
```bash
# Install GitHub CLI (if not already installed)
# https://cli.github.com/

# View recent workflow runs
gh run list --limit 10

# Watch a specific run
gh run watch

# View run details
gh run view <run-id>
```

### Option 3: Git Badges (Coming Soon)
Add to README.md:
```markdown
![CI/CD](https://github.com/Siyamkhize/rlmsv1/workflows/Dart%20CI/badge.svg)
```

---

## 🎯 What Each Status Means

| Status | Icon | Meaning | Action Required |
|--------|------|---------|-----------------|
| **Success** | ✅ | All checks passed | None - deploy when ready |
| **Failure** | ❌ | One or more checks failed | Fix errors, push again |
| **Running** | 🔄 | Workflow in progress | Wait for completion |
| **Cancelled** | ⏹️ | Manually stopped | Restart if needed |
| **Skipped** | ⏭️ | Workflow not triggered | Expected for some conditions |

---

## 🐛 Troubleshooting

### Problem: "Workflow not running"
**Check:**
1. Go to Actions tab - is there a new run?
2. Check workflow file has correct trigger branches
3. Look for YAML syntax errors (will show at top of Actions page)

**Solution:**
```bash
# Verify workflow files are valid
git add .github/workflows/
git status
# Should show workflows are tracked and pushed
```

### Problem: "Workflow failing"
**Check:**
1. Click on failed workflow run
2. Expand failed step to see error details
3. Check if it's a known issue (see KNOWN_ISSUES.md)

**Common Issues:**
- **Old errors (182 issues):** Ignore - from old run before fixes
- **Secrets missing:** SonarQube/Snyk optional - skip gracefully
- **Flutter version:** Using 3.24.0 (stable)

### Problem: "Can't find workflow results"
**Direct Links:**
- All runs: https://github.com/Siyamkhize/rlmsv1/actions
- Dart CI: https://github.com/Siyamkhize/rlmsv1/actions/workflows/dart.yml
- CI/CD Pipeline: https://github.com/Siyamkhize/rlmsv1/actions/workflows/ci-cd-pipeline.yml

---

## 📚 Related Documentation

- [CI_CD_STATUS.md](CI_CD_STATUS.md) - Detailed status report
- [GITHUB_ACTIONS_STATUS.md](GITHUB_ACTIONS_STATUS.md) - Old vs new run explanation
- [CODERABBIT_SETUP.md](CODERABBIT_SETUP.md) - CodeRabbit configuration
- [OPTIONAL_TOOLS_SETUP.md](OPTIONAL_TOOLS_SETUP.md) - SonarQube, Snyk, Codecov

---

## 🎉 Quick Win Checklist

- [x] CI/CD workflows created (8 workflows)
- [x] Workflows pushed to GitHub
- [x] Syntax errors fixed
- [x] Code fixes applied (981 → 1 warnings)
- [x] Security audit configured
- [x] Optional tools configured (SonarQube, Snyk)
- [x] Documentation created
- [x] Fresh CI/CD run triggered
- [ ] Monitor first successful run
- [ ] Install CodeRabbit app (optional)
- [ ] Add optional tool tokens (optional)

---

## 🚦 Current CI/CD Status: ✅ ACTIVE

Your CI/CD pipeline is **live and running** on GitHub Actions!

**Next Step:** Visit [github.com/Siyamkhize/rlmsv1/actions](https://github.com/Siyamkhize/rlmsv1/actions) to watch your workflows in action! 🎬
