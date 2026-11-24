# CI/CD Monitoring Guide

**Repository:** https://github.com/Siyamkhize/rlmsv1  
**Actions URL:** https://github.com/Siyamkhize/rlmsv1/actions  
**Latest Commit:** `847e11e` - "test: trigger CI/CD workflows with product flavor builds"

---

## 🔄 Triggered Workflows

Your push to `main` branch should trigger the following workflows:

### 1. **Dart CI** (`.github/workflows/dart.yml`)
**Purpose:** Quick Flutter analysis and multi-flavor builds

**Jobs:**
- ✅ **Analyze Code**
  - Setup Flutter 3.24.0
  - Install dependencies
  - Verify formatting
  - Analyze project (errors block, warnings informational)

- ✅ **Build APK (Matrix: local, staging, production)**
  - Setup Flutter 3.24.0 + Java 17
  - Build all 3 flavors in parallel
  - Upload APK artifacts:
    - `apk-local`
    - `apk-staging`
    - `apk-production`

**Expected Duration:** 15-25 minutes (parallel builds)

---

### 2. **Comprehensive CI/CD Pipeline** (`.github/workflows/comprehensive-cicd.yml`)
**Purpose:** Full security, quality, and deployment pipeline

**Pipeline Stages:**

#### Stage 1: Security Scanning 🔒
- **Trivy Vulnerability Scanner**
  - Scans filesystem for CRITICAL/HIGH vulnerabilities
  - Uploads SARIF to GitHub Security (if Code Scanning enabled)
  
- **GitLeaks Secret Scanning**
  - Scans for exposed secrets in code and history
  
- **OWASP Dependency Check**
  - Checks dependencies for known CVEs
  - Threshold: CVSS 7+
  - Continue-on-error (Gradle wrapper upgrade in progress)

**Expected Duration:** 5-10 minutes

#### Stage 2: Code Quality 🎯
- **Flutter Analysis & Tests**
  - Format checking
  - Code analysis (error-blocking)
  - Unit tests with coverage
  - Coverage report generation
  - Codecov upload (optional)

- **PHP Quality Checks**
  - PHP 8.1 syntax validation (excludes backup files)
  - PHP Security Checker
  - PHPStan static analysis (level 5)

**Expected Duration:** 10-15 minutes

#### Stage 3: Multi-Flavor Builds 🏗️
**Matrix Strategy:** Builds 3 flavors in parallel

| Flavor     | Build Args                    | APK Output               |
|------------|-------------------------------|--------------------------|
| local      | `--release --flavor local`    | app-localRelease.apk     |
| staging    | `--release --flavor staging`  | app-stagingRelease.apk   |
| production | `--release --flavor production` | app-productionRelease.apk |

**Each Build:**
- Setup Java 17 + Flutter 3.24.0
- Install dependencies
- Build APK
- Generate build info (commit, branch, date)
- Package artifacts
- Upload to GitHub (30-day retention):
  - `android-apk-local`
  - `android-apk-staging`
  - `android-apk-production`

**Expected Duration:** 20-30 minutes (parallel)

#### Stage 4: Advanced Security 🛡️
- **Semgrep SAST**
  - Rulesets: security-audit, secrets, owasp-top-ten, flutter, php
  - SARIF upload to GitHub Security

- **Snyk Security Scan** (optional, requires SNYK_TOKEN)
  - Tests all projects
  - Monitors for future vulnerabilities

**Expected Duration:** 5-10 minutes

#### Stage 5: Integration Tests 🧪
- Run integration tests (if present)
- Generate test summary

**Expected Duration:** 5-10 minutes

#### Stage 6: Deployment 🚀
**Conditional based on branch:**

- **Development Environment** (if branch = `develop`)
  - Download `android-apk-local`
  - Deploy to Firebase App Distribution (developers group)
  - Requires: `FIREBASE_DEV_APP_ID`, `FIREBASE_CREDENTIALS`

- **Staging Environment** (if branch = `staging`)
  - Download `android-apk-staging`
  - Deploy to Firebase App Distribution (testers, qa groups)
  - Run smoke tests
  - Requires: `FIREBASE_STAGING_APP_ID`, `FIREBASE_CREDENTIALS`

- **Production Environment** (if branch = `main`) ⬅️ **CURRENT**
  - Download `android-apk-production`
  - Sign APK (if configured)
  - Deploy to Google Play (internal testing track)
    - Requires: `PLAY_STORE_CREDENTIALS`
  - Deploy to Firebase App Distribution
    - Requires: `FIREBASE_PRODUCTION_APP_ID`, `FIREBASE_CREDENTIALS`
  - Create GitHub Release with tag
    - Requires: `GITHUB_TOKEN` (auto-provided)

**Status:** Deployment steps have `continue-on-error: true`, so they won't block the pipeline if secrets are not configured.

**Expected Duration:** 2-5 minutes (if secrets configured)

#### Stage 7: Post-Deployment ✅
- Health checks
- Generate deployment report
- Upload report artifact
- Add summary to job output

**Expected Duration:** 1-2 minutes

#### Stage 8: Monitoring Setup 📊
- Configure application monitoring dashboards
- Setup alert rules
- Only runs for `main` or `staging` branches

**Expected Duration:** 1-2 minutes

**Total Pipeline Duration:** 45-60 minutes

---

### 3. **PHP CI** (`.github/workflows/php.yml`)
**Purpose:** PHP-specific quality and security checks

**Jobs:**
- PHP syntax validation (excludes backup files)
- Composer validation
- Security checks

**Expected Duration:** 5-10 minutes

---

### 4. **CodeQL Analysis** (`.github/workflows/codeql.yml`)
**Purpose:** GitHub's code scanning for security vulnerabilities

**Languages Analyzed:**
- JavaScript/TypeScript
- Python
- Other detected languages

**Expected Duration:** 10-20 minutes

---

### 5. **Performance & Quality** (`.github/workflows/performance-quality.yml`)
**Purpose:** Performance metrics and quality gates

**Checks:**
- Bundle size analysis
- Performance benchmarks
- Quality metrics

**Expected Duration:** 5-10 minutes

---

## 📊 How to Monitor

### Real-Time Monitoring

1. **GitHub Actions Web UI**
   ```
   https://github.com/Siyamkhize/rlmsv1/actions
   ```
   - View all running workflows
   - Click each workflow to see job details
   - View logs for each step

2. **Workflow Run for This Test**
   ```
   https://github.com/Siyamkhize/rlmsv1/actions/runs/<run-id>
   ```
   (Run ID assigned when workflows start)

3. **Specific Workflow Views**
   - Dart CI: https://github.com/Siyamkhize/rlmsv1/actions/workflows/dart.yml
   - Comprehensive: https://github.com/Siyamkhize/rlmsv1/actions/workflows/comprehensive-cicd.yml
   - PHP: https://github.com/Siyamkhize/rlmsv1/actions/workflows/php.yml
   - CodeQL: https://github.com/Siyamkhize/rlmsv1/actions/workflows/codeql.yml

### Status Badges

You can add these to your README.md:

```markdown
![Dart CI](https://github.com/Siyamkhize/rlmsv1/workflows/Dart%20CI/badge.svg)
![Comprehensive CI/CD](https://github.com/Siyamkhize/rlmsv1/workflows/Comprehensive%20CI%2FCD%20Pipeline/badge.svg)
![PHP CI](https://github.com/Siyamkhize/rlmsv1/workflows/PHP%20CI/badge.svg)
```

---

## ✅ Success Criteria

### Must Pass (Blocking)
- ✅ Dart CI - Analyze Code (zero errors)
- ✅ Dart CI - Build APK (all 3 flavors)
- ✅ Comprehensive - Flutter Analysis (zero errors)
- ✅ Comprehensive - Build Android (all 3 flavors)
- ✅ PHP - Syntax Check (zero parse errors)

### Warning Only (Non-Blocking)
- ⚠️ Security Scans (findings documented, not blocking)
- ⚠️ OWASP Dependency Check (continue-on-error while upgrading)
- ⚠️ Flutter Analysis Warnings (informational only)
- ⚠️ Deployment Steps (secrets may not be configured)

---

## 🎯 Expected Results

### Success Scenario
```
✅ Dart CI - Analyze Code (passed)
✅ Dart CI - Build APK (local) (passed) + artifact uploaded
✅ Dart CI - Build APK (staging) (passed) + artifact uploaded
✅ Dart CI - Build APK (production) (passed) + artifact uploaded

✅ Comprehensive - Security Scan (passed with warnings)
✅ Comprehensive - Flutter Analysis (passed)
✅ Comprehensive - PHP Quality (passed)
✅ Comprehensive - Build Android (local) (passed) + artifact uploaded
✅ Comprehensive - Build Android (staging) (passed) + artifact uploaded
✅ Comprehensive - Build Android (production) (passed) + artifact uploaded
✅ Comprehensive - Advanced Security (passed with warnings)
✅ Comprehensive - Integration Tests (passed)
⏭️ Comprehensive - Deploy Production (skipped - secrets not configured)
✅ Comprehensive - Post-Deployment Checks (passed)
✅ Comprehensive - Monitoring Setup (passed)

✅ PHP CI (passed)
✅ CodeQL Analysis (passed)
✅ Performance Quality (passed)
```

### Artifacts Generated
After successful run, download artifacts from:
```
https://github.com/Siyamkhize/rlmsv1/actions/runs/<run-id>
```

**Available Downloads:**
1. `apk-local` - Local flavor APK (from Dart CI)
2. `apk-staging` - Staging flavor APK (from Dart CI)
3. `apk-production` - Production flavor APK (from Dart CI)
4. `android-apk-local` - Local APK + build info (from Comprehensive)
5. `android-apk-staging` - Staging APK + build info (from Comprehensive)
6. `android-apk-production` - Production APK + build info (from Comprehensive)
7. `flutter-test-results` - Test coverage reports
8. `dependency-check-report` - OWASP security report
9. `deployment-report` - Deployment summary

**Retention:** 30 days

---

## 🔍 Troubleshooting

### Common Issues

**1. Build Timeout (Ubuntu Runners)**
- **Symptom:** Build exceeds 6 hours (GitHub limit)
- **Solution:** Already optimized with Gradle caching and parallel builds
- **Monitor:** Build durations should be 20-30 minutes per flavor

**2. Java Version Mismatch**
- **Symptom:** "Java home supplied is invalid" or Java 11 vs 17 errors
- **Status:** ✅ Fixed - workflows use Java 17 via `setup-java@v4`

**3. PHP Parse Errors**
- **Symptom:** Syntax errors in PHP files
- **Status:** ✅ Fixed - excludes backup files (*_backup*.php, *_old.php)

**4. Code Scanning Not Enabled**
- **Symptom:** SARIF upload fails with "Code scanning not enabled"
- **Status:** Non-blocking - continues with `continue-on-error: true`
- **Fix:** Enable in repo settings → Security → Code scanning

**5. Deployment Failures**
- **Symptom:** Firebase/Google Play deployment fails
- **Status:** Expected - secrets not configured yet
- **Impact:** None - continues with `continue-on-error: true`

### If Builds Fail

1. **Check workflow logs:**
   - Click the failed workflow
   - Click the failed job
   - Expand failed step
   - Review error messages

2. **Common fixes:**
   - Re-run failed jobs (transient network issues)
   - Check for syntax errors in modified files
   - Verify dependencies are up to date
   - Check disk space on runners

3. **Get help:**
   - Check this monitoring guide
   - Review workflow YAML files
   - Check GitHub Actions documentation

---

## 📈 Performance Benchmarks

### Expected Build Times (GitHub Runners)

| Workflow               | Expected Duration | Acceptable Range |
|------------------------|-------------------|------------------|
| Dart CI                | 20 minutes        | 15-30 minutes    |
| Comprehensive CI/CD    | 50 minutes        | 40-60 minutes    |
| PHP CI                 | 7 minutes         | 5-10 minutes     |
| CodeQL Analysis        | 15 minutes        | 10-20 minutes    |
| Performance Quality    | 7 minutes         | 5-10 minutes     |

### Optimization Notes
- Matrix builds run in parallel (3 flavors simultaneously)
- Gradle caching enabled (`cache: 'gradle'`)
- Flutter caching enabled (`cache: true`)
- Dependencies cached between runs
- Multi-core builds (up to 12 threads)

---

## 🎓 Next Steps After CI/CD Pass

1. **Download and Test APKs**
   - Download all 3 flavor artifacts
   - Install on Android devices
   - Verify functionality

2. **Review Security Reports**
   - Check dependency-check-report artifact
   - Review GitHub Security alerts
   - Address any CRITICAL/HIGH findings

3. **Configure Deployment** (Optional)
   - Add Firebase credentials to secrets
   - Add Google Play credentials
   - Create `develop` and `staging` branches for environment-specific deploys

4. **Monitor First Production Deploy**
   - When secrets are configured, watch deployment steps
   - Verify APK reaches Firebase/Play Store
   - Check automated release creation

---

## 📝 Test Checklist

After workflows complete, verify:

- [ ] All workflows show green checkmarks
- [ ] 6 APK artifacts available for download (3 from each workflow)
- [ ] No critical build errors
- [ ] Security scan reports available
- [ ] Test coverage reports generated
- [ ] All 3 flavors built successfully in parallel
- [ ] Build times within expected ranges
- [ ] GitHub Actions page shows successful run

---

**CI/CD Test Initiated:** November 23, 2026  
**Commit:** 847e11e  
**Branch:** main  
**Trigger:** Push to main branch

**Monitor at:** https://github.com/Siyamkhize/rlmsv1/actions

🚀 **Workflows are now running!**
