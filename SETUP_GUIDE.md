# RLMS CI/CD Setup Guide

## 🎉 Repository Successfully Set Up!

Your RLMS project has been pushed to: **https://github.com/Siyamkhize/rlmsv1.git**

## ✅ What Has Been Configured

### 1. CI/CD Pipelines
- ✅ Main CI/CD pipeline with security scanning
- ✅ Quality gate checks for pull requests
- ✅ Nightly security scans
- ✅ Automated testing with coverage reporting
- ✅ Staging and production deployment workflows

### 2. Security Tools Integration
- ✅ SonarQube for code quality analysis
- ✅ Snyk for vulnerability scanning
- ✅ OWASP dependency checking
- ✅ Security linting scripts

### 3. Branch Structure
- ✅ `main` - Production branch
- ✅ `staging` - Pre-production testing branch
- ✅ `development` - Active development branch

### 4. Scripts Created
- ✅ `scripts/security-check.sh` - Run security scans
- ✅ `scripts/run-tests.sh` - Execute all tests
- ✅ `scripts/deploy.sh` - Deploy to environments
- ✅ `scripts/setup-ci-cd.sh` - Initial setup script

### 5. Configuration Files
- ✅ `.github/workflows/` - GitHub Actions workflows
- ✅ `sonar-project.properties` - SonarQube configuration
- ✅ `.snyk` - Snyk configuration
- ✅ `.env.staging` - Staging environment config
- ✅ `.env.production` - Production environment config

## 🔧 Next Steps - Repository Configuration

### Step 1: Configure GitHub Repository Secrets

Go to your repository settings: **Settings > Secrets and variables > Actions**

Add the following secrets:

#### SonarQube Configuration
```
SONAR_TOKEN=<your-sonarqube-token>
SONAR_HOST_URL=<your-sonarqube-server-url>
```

**How to get SonarQube token:**
1. Sign up at https://sonarcloud.io/ (free for public repos)
2. Go to My Account > Security > Generate Token
3. Copy the token

#### Snyk Configuration
```
SNYK_TOKEN=<your-snyk-api-token>
```

**How to get Snyk token:**
1. Sign up at https://snyk.io/ (free tier available)
2. Go to Account Settings > API Token
3. Copy the token

#### Firebase Configuration (for App Distribution)
```
FIREBASE_STAGING_APP_ID=<staging-app-id>
FIREBASE_PRODUCTION_APP_ID=<production-app-id>
FIREBASE_CREDENTIALS=<firebase-service-account-json>
```

**How to set up Firebase:**
1. Go to https://console.firebase.google.com/
2. Create projects for staging and production
3. Add Android app to each project
4. Download service account JSON from Project Settings > Service Accounts

#### Codecov Configuration (for coverage reports)
```
CODECOV_TOKEN=<your-codecov-token>
```

**How to get Codecov token:**
1. Sign up at https://codecov.io/
2. Add your repository
3. Copy the upload token

#### Notification Configuration (Optional)
```
SLACK_WEBHOOK=<your-slack-webhook-url>
EMAIL_USERNAME=<email-for-notifications>
EMAIL_PASSWORD=<email-password>
SECURITY_EMAIL=<email-for-security-alerts>
```

#### Google Play Store (for production deployment)
```
PLAY_STORE_CREDENTIALS=<google-play-service-account-json>
```

### Step 2: Set Up Branch Protection Rules

Go to: **Settings > Branches > Add rule**

**For `main` branch:**
- ✅ Require a pull request before merging
- ✅ Require approvals (1)
- ✅ Require status checks to pass before merging
  - Select: `security-and-quality`
  - Select: `test`
  - Select: `build-android`
- ✅ Require branches to be up to date before merging
- ✅ Do not allow bypassing the above settings

**For `staging` branch:**
- ✅ Require a pull request before merging
- ✅ Require status checks to pass before merging
  - Select: `security-and-quality`
  - Select: `test`

**For `development` branch:**
- ✅ Require status checks to pass before merging
  - Select: `test`

### Step 3: Enable GitHub Actions

1. Go to **Actions** tab in your repository
2. Enable workflows if prompted
3. All workflows should now be visible

### Step 4: Configure SonarQube Project

1. Log in to SonarCloud (https://sonarcloud.io/)
2. Click "+ Analyze new project"
3. Select your repository: `Siyamkhize/rlmsv1`
4. Follow the setup wizard
5. Choose "GitHub Actions" as CI tool
6. The configuration is already in place!

### Step 5: Configure Snyk Project

1. Log in to Snyk (https://app.snyk.io/)
2. Click "Add project"
3. Select GitHub and authorize
4. Select your repository: `Siyamkhize/rlmsv1`
5. Import and scan

## 🚀 How to Use the CI/CD Pipeline

### Making Changes

1. **Create a feature branch from development:**
   ```bash
   git checkout development
   git pull
   git checkout -b feature/my-new-feature
   ```

2. **Make your changes and commit:**
   ```bash
   git add .
   git commit -m "Add new feature"
   git push origin feature/my-new-feature
   ```

3. **Create a Pull Request to `development`:**
   - Go to GitHub repository
   - Click "Pull requests" > "New pull request"
   - Select base: `development`, compare: `feature/my-new-feature`
   - The Quality Gate workflow will run automatically
   - Wait for all checks to pass
   - Request review and merge

### Deploying to Staging

1. **Merge `development` into `staging`:**
   ```bash
   git checkout staging
   git pull
   git merge development
   git push origin staging
   ```

2. The CI/CD pipeline will automatically:
   - Run security scans
   - Run all tests
   - Build staging APK
   - Deploy to Firebase App Distribution (staging group)
   - Notify on Slack (if configured)

### Deploying to Production

1. **Merge `staging` into `main`:**
   ```bash
   git checkout main
   git pull
   git merge staging
   git push origin main
   ```

2. The CI/CD pipeline will automatically:
   - Run comprehensive security scans
   - Run all tests
   - Build production APK (obfuscated)
   - Deploy to Google Play Store (internal track)
   - Deploy to Firebase App Distribution (production testers)
   - Create a GitHub release
   - Notify on Slack (if configured)

## 📊 Monitoring and Reports

### Where to Find Reports

1. **GitHub Actions:**
   - Go to "Actions" tab
   - Click on any workflow run
   - View logs and artifacts

2. **SonarQube:**
   - Visit your SonarCloud dashboard
   - View code quality metrics, bugs, vulnerabilities

3. **Snyk:**
   - Visit your Snyk dashboard
   - View dependency vulnerabilities and security issues

4. **Codecov:**
   - Visit codecov.io/gh/Siyamkhize/rlmsv1
   - View test coverage trends

### Artifacts Available

After each workflow run, download:
- Security reports (Snyk JSON)
- Test reports
- Coverage reports
- APK files

## 🔍 Quality Gates

### What Gets Checked

#### For All Pull Requests:
- ✅ Static analysis (no errors)
- ✅ All tests pass
- ✅ Code coverage ≥ 70%
- ✅ SonarQube quality gate passes
- ✅ No HIGH or CRITICAL security vulnerabilities
- ✅ No hardcoded secrets

#### For Deployments:
- ✅ All above checks
- ✅ Successful APK build
- ✅ No blocking security issues

### If Quality Gates Fail

1. **Check the workflow logs** to see which check failed
2. **Fix the issues** in your feature branch
3. **Push the fixes** - the checks will run again automatically
4. **Merge once all checks pass**

## 🛠️ Local Development

### Running Tests Locally

```bash
# Make scripts executable (first time only)
chmod +x scripts/*.sh

# Run all tests
./scripts/run-tests.sh

# Run security checks
./scripts/security-check.sh
```

### Building Locally

```bash
# Staging build
flutter build apk --release

# Production build (with obfuscation)
flutter build apk --release --obfuscate --split-debug-info=./debug-info
```

### Deploying Locally

```bash
# Deploy to staging
./scripts/deploy.sh staging

# Deploy to production
./scripts/deploy.sh production
```

## 📱 Environment Configuration

### Staging Environment
- Debug tools enabled
- Detailed logging
- Beta features enabled
- Uses staging database and APIs

### Production Environment
- Debug tools disabled
- Error-level logging only
- Stable features only
- Uses production database and APIs
- Code obfuscation enabled
- SSL pinning enforced

## 🔒 Security Best Practices

1. **Never commit secrets** - Use environment variables
2. **Review dependency updates** - Check Snyk reports weekly
3. **Monitor nightly scans** - Check email for security alerts
4. **Update dependencies regularly** - Run `flutter pub upgrade` weekly
5. **Review pull requests** - Don't bypass quality gates
6. **Test in staging first** - Always deploy to staging before production

## 📚 Additional Documentation

- [CI/CD Pipeline Details](CI_CD_README.md)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [SonarQube Documentation](https://docs.sonarcloud.io/)
- [Snyk Documentation](https://docs.snyk.io/)

## 🆘 Troubleshooting

### Pipeline Failing on First Run

**Problem:** Workflows fail because secrets are not configured

**Solution:** Configure all required secrets in GitHub repository settings

### SonarQube Quality Gate Failing

**Problem:** Code doesn't meet quality standards

**Solution:** 
1. Review SonarQube report
2. Fix identified issues
3. Push changes

### Snyk Finds Vulnerabilities

**Problem:** Dependencies have security vulnerabilities

**Solution:**
1. Run `flutter pub upgrade`
2. Check if vulnerabilities are fixed
3. If not, wait for library updates or find alternatives

### Coverage Below Threshold

**Problem:** Test coverage is below 70%

**Solution:**
1. Run `flutter test --coverage`
2. Open `coverage/html/index.html`
3. Write tests for uncovered code

## ✨ Success Criteria

Your CI/CD pipeline is fully operational when:
- ✅ All workflows run without errors
- ✅ Pull requests show quality gate checks
- ✅ Security scans complete successfully
- ✅ Deployments to staging work automatically
- ✅ Deployments to production work automatically
- ✅ Notifications are received on Slack/email

## 🎯 Next Actions

1. ☐ Configure all repository secrets
2. ☐ Set up branch protection rules
3. ☐ Connect SonarCloud project
4. ☐ Connect Snyk project
5. ☐ Set up Firebase projects (staging & production)
6. ☐ Configure Google Play Console (for production)
7. ☐ Test the pipeline with a sample PR
8. ☐ Deploy to staging
9. ☐ Deploy to production

---

**Need Help?**
- Review the workflow logs in GitHub Actions
- Check the [CI/CD README](CI_CD_README.md) for detailed information
- Review GitHub Actions documentation

**Congratulations! Your CI/CD pipeline is ready! 🎉**
