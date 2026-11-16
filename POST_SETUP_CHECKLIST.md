# Post-Setup Checklist for RLMS CI/CD Pipeline

Use this checklist to complete the CI/CD pipeline configuration after the initial setup.

## ✅ Phase 1: GitHub Repository Configuration (CRITICAL)

### Configure Repository Secrets
Visit: https://github.com/Siyamkhize/rlmsv1/settings/secrets/actions

- [ ] **SONAR_TOKEN**
  - Sign up at https://sonarcloud.io/
  - Go to My Account > Security
  - Generate new token
  - Copy and paste into GitHub secrets

- [ ] **SONAR_HOST_URL**
  - Use: `https://sonarcloud.io`
  - Or your self-hosted SonarQube URL

- [ ] **SNYK_TOKEN**
  - Sign up at https://snyk.io/
  - Go to Account Settings > General > API Token
  - Copy and paste into GitHub secrets

- [ ] **CODECOV_TOKEN**
  - Sign up at https://codecov.io/
  - Add repository
  - Copy upload token
  - Paste into GitHub secrets

### Configure Branch Protection Rules
Visit: https://github.com/Siyamkhize/rlmsv1/settings/branches

- [ ] **Protect `main` branch**
  - [x] Require a pull request before merging
    - [x] Require approvals: 1
  - [x] Require status checks to pass before merging
    - Select: `security-and-quality`
    - Select: `test`
    - Select: `build-android`
  - [x] Require branches to be up to date before merging
  - [x] Do not allow bypassing

- [ ] **Protect `staging` branch**
  - [x] Require a pull request before merging
  - [x] Require status checks to pass
    - Select: `security-and-quality`
    - Select: `test`

- [ ] **Protect `development` branch**
  - [x] Require status checks to pass
    - Select: `test`

### Enable GitHub Actions
- [ ] Go to Actions tab: https://github.com/Siyamkhize/rlmsv1/actions
- [ ] Enable workflows if prompted
- [ ] Verify all 3 workflows are listed:
  - CI/CD Pipeline
  - Quality Gate Check
  - Nightly Security Scan

---

## ✅ Phase 2: External Service Integration

### SonarCloud Setup
- [ ] Go to https://sonarcloud.io/
- [ ] Sign in with GitHub
- [ ] Click "+" > "Analyze new project"
- [ ] Select `Siyamkhize/rlmsv1`
- [ ] Choose "With GitHub Actions"
- [ ] The configuration is already in your repo!
- [ ] Verify project appears in your SonarCloud dashboard

### Snyk Setup
- [ ] Go to https://app.snyk.io/
- [ ] Sign in with GitHub
- [ ] Click "Add project"
- [ ] Select GitHub
- [ ] Authorize Snyk
- [ ] Select `Siyamkhize/rlmsv1`
- [ ] Click "Add selected repositories"
- [ ] Wait for initial scan to complete

### Codecov Setup
- [ ] Go to https://codecov.io/
- [ ] Sign in with GitHub
- [ ] Add new repository
- [ ] Select `Siyamkhize/rlmsv1`
- [ ] Copy the upload token
- [ ] Add to GitHub secrets as `CODECOV_TOKEN`

---

## ✅ Phase 3: Firebase & Deployment Setup (Optional but Recommended)

### Firebase Projects
Only needed if you want automatic app distribution.

#### Create Staging Project
- [ ] Go to https://console.firebase.google.com/
- [ ] Create new project: "rlmsv1-staging"
- [ ] Add Android app
  - Package name: `com.rlms.app.staging` (or your package name)
  - Download `google-services.json`
- [ ] Go to App Distribution
- [ ] Note the App ID
- [ ] Add to GitHub secrets as `FIREBASE_STAGING_APP_ID`

#### Create Production Project
- [ ] Go to https://console.firebase.google.com/
- [ ] Create new project: "rlmsv1-production"
- [ ] Add Android app
  - Package name: `com.rlms.app` (or your package name)
  - Download `google-services.json`
- [ ] Go to App Distribution
- [ ] Note the App ID
- [ ] Add to GitHub secrets as `FIREBASE_PRODUCTION_APP_ID`

#### Service Account Setup
- [ ] In Firebase Console, go to Project Settings
- [ ] Go to Service Accounts tab
- [ ] Click "Generate new private key"
- [ ] Download the JSON file
- [ ] Open in text editor and copy entire content
- [ ] Add to GitHub secrets as `FIREBASE_CREDENTIALS`

---

## ✅ Phase 4: Google Play Console (Production Deployment)

Only needed if you want automatic Play Store deployment.

- [ ] Go to https://play.google.com/console/
- [ ] Create app or select existing
- [ ] Go to Setup > API access
- [ ] Create service account
- [ ] Download JSON key
- [ ] Grant permissions: Release Manager
- [ ] Add JSON content to GitHub secrets as `PLAY_STORE_CREDENTIALS`

---

## ✅ Phase 5: Optional Integrations

### Slack Notifications
- [ ] In Slack, go to https://api.slack.com/apps
- [ ] Create new app
- [ ] Enable Incoming Webhooks
- [ ] Add webhook to workspace
- [ ] Copy webhook URL
- [ ] Add to GitHub secrets as `SLACK_WEBHOOK`

### Email Notifications
- [ ] Add email credentials to GitHub secrets:
  - `EMAIL_USERNAME` - Your email
  - `EMAIL_PASSWORD` - App-specific password
  - `SECURITY_EMAIL` - Where to send alerts

---

## ✅ Phase 6: Testing the Pipeline

### Test 1: Run Existing Workflows
- [ ] Go to Actions tab
- [ ] Click "CI/CD Pipeline"
- [ ] Click "Run workflow"
- [ ] Select `development` branch
- [ ] Click "Run workflow"
- [ ] Wait for completion
- [ ] Verify all jobs pass

### Test 2: Create Feature Branch and PR
```bash
# In your local repository
git checkout development
git pull
git checkout -b test/pipeline-verification
echo "# Testing CI/CD Pipeline" > test-file.md
git add test-file.md
git commit -m "Test: Verify CI/CD pipeline works"
git push origin test/pipeline-verification
```

- [ ] Go to GitHub and create PR from `test/pipeline-verification` to `development`
- [ ] Verify Quality Gate workflow runs
- [ ] Check that status checks appear on PR
- [ ] Verify PR gets commented with quality report
- [ ] Merge the PR if all checks pass
- [ ] Delete test branch

### Test 3: Deploy to Staging
```bash
git checkout staging
git pull
git merge development
git push origin staging
```

- [ ] Verify CI/CD pipeline triggers
- [ ] Check that security scans run
- [ ] Verify tests execute
- [ ] Check that APK builds
- [ ] If Firebase configured, verify deployment
- [ ] Check for Slack notification (if configured)

### Test 4: Review Reports
- [ ] Check SonarCloud dashboard for code quality
- [ ] Check Snyk dashboard for vulnerabilities
- [ ] Check Codecov for coverage report
- [ ] Download and review workflow artifacts

---

## ✅ Phase 7: Environment Configuration

### Update Flutter App Configuration

#### For Staging
- [ ] Update `android/app/build.gradle` to support staging flavor
- [ ] Add staging-specific configuration
- [ ] Test staging build locally

#### For Production
- [ ] Configure code obfuscation settings
- [ ] Set up app signing
- [ ] Configure ProGuard rules if needed
- [ ] Test production build locally

### Update Environment Files
- [ ] Edit `.env.staging` with actual staging URLs and keys
- [ ] Edit `.env.production` with actual production URLs and keys
- [ ] Never commit actual secrets!

---

## ✅ Phase 8: Documentation Review

- [ ] Read `CI_CD_README.md` thoroughly
- [ ] Read `SETUP_GUIDE.md` for detailed instructions
- [ ] Share documentation with team
- [ ] Add project-specific deployment notes

---

## ✅ Phase 9: Team Onboarding

### Educate Team Members
- [ ] Share workflow documentation
- [ ] Explain branch strategy
- [ ] Demonstrate PR process
- [ ] Show where to find reports
- [ ] Explain quality gate requirements

### Set Expectations
- [ ] All PRs must pass quality gates
- [ ] Code coverage minimum is 70%
- [ ] No HIGH/CRITICAL security issues allowed
- [ ] Staging deployment before production
- [ ] Required PR reviews

---

## ✅ Phase 10: Monitoring Setup

### Regular Checks
- [ ] Set up weekly review of SonarQube reports
- [ ] Schedule weekly review of Snyk vulnerabilities
- [ ] Monitor nightly security scan results
- [ ] Review deployment success rates
- [ ] Track test coverage trends

### Alerts
- [ ] Ensure email alerts work for critical security issues
- [ ] Test Slack notifications
- [ ] Set up alert escalation if needed

---

## 🎯 Success Criteria

Your setup is complete when:

- [x] ✅ Repository pushed to GitHub
- [ ] ✅ All required secrets configured
- [ ] ✅ Branch protection rules active
- [ ] ✅ SonarCloud project connected
- [ ] ✅ Snyk project connected
- [ ] ✅ Codecov project connected
- [ ] ✅ Test workflow runs successfully
- [ ] ✅ Quality gates work on PRs
- [ ] ✅ Staging deployment works
- [ ] ✅ Team understands the workflow
- [ ] ✅ Reports are being generated

---

## 📝 Notes & Issues

Use this section to track any issues or special notes during setup:

```
Date: _________________
Issue: _______________________________________________________________
Resolution: ___________________________________________________________

Date: _________________
Issue: _______________________________________________________________
Resolution: ___________________________________________________________

Date: _________________
Issue: _______________________________________________________________
Resolution: ___________________________________________________________
```

---

## 🆘 Getting Help

If you encounter issues:

1. **Check Workflow Logs**
   - Go to Actions tab > Select workflow run > Review logs

2. **Common Issues**
   - Secrets not set: Add them in repository settings
   - Branch protection: Ensure rules are configured
   - External service: Verify service is connected

3. **Documentation**
   - Review `CI_CD_README.md`
   - Check `SETUP_GUIDE.md`
   - Search GitHub Actions documentation

4. **Test Locally**
   - Run `./scripts/run-tests.sh`
   - Run `./scripts/security-check.sh`
   - Build APK locally

---

## ✨ Final Steps

Once everything is checked:

- [ ] Delete test branches used for verification
- [ ] Archive this checklist (or keep for reference)
- [ ] Celebrate! 🎉 Your CI/CD pipeline is operational!
- [ ] Start using the pipeline for actual development

---

**Last Updated:** _______________
**Completed By:** _______________
**Date Completed:** _______________

**Status:** [ ] In Progress  [ ] Completed  [ ] Need Help
