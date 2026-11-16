# Complete CI/CD Setup Guide - Step by Step

Follow these steps EXACTLY to complete your CI/CD pipeline setup. Each step has detailed instructions with commands you can copy/paste.

---

## 📋 Prerequisites

Before starting, make sure you have:
- ✅ GitHub account access to https://github.com/Siyamkhize/rlmsv1
- ✅ Admin permissions on the repository
- ✅ Email address for notifications
- ✅ About 30-45 minutes to complete all steps

---

## STEP 1: Create SonarCloud Account & Get Token

### 1.1 Sign Up for SonarCloud

1. Go to: https://sonarcloud.io/
2. Click **"Log in"** in the top right
3. Choose **"With GitHub"**
4. Authorize SonarCloud to access your GitHub account
5. You'll be redirected to your SonarCloud dashboard

### 1.2 Import Your Repository

1. On SonarCloud dashboard, click the **"+"** icon in top right
2. Select **"Analyze new project"**
3. You'll see a list of your GitHub repositories
4. Find and select **"Siyamkhize/rlmsv1"**
5. Click **"Set Up"**
6. Choose **"With GitHub Actions"**
7. Keep this tab open - we'll need information from here

### 1.3 Get Your SonarCloud Token

1. In SonarCloud, click your profile picture (top right)
2. Go to **"My Account"**
3. Click **"Security"** tab
4. Under **"Generate Tokens"**:
   - Name: `RLMS_GitHub_Actions`
   - Type: **User Token**
   - Expires: **No expiration** (or set to 1 year)
5. Click **"Generate"**
6. **COPY THE TOKEN** - you'll only see it once!
   - Save it in a secure note temporarily (like Notepad)

### 1.4 Get Your SonarCloud Details

You'll need:
- **SONAR_TOKEN**: The token you just copied
- **SONAR_HOST_URL**: `https://sonarcloud.io`
- **Organization Key**: Found in SonarCloud under My Account → Organizations

---

## STEP 2: Create Snyk Account & Get Token

### 2.1 Sign Up for Snyk

1. Go to: https://snyk.io/
2. Click **"Start free"** or **"Sign up"**
3. Choose **"Sign up with GitHub"**
4. Authorize Snyk
5. Complete the onboarding wizard

### 2.2 Import Your Repository

1. In Snyk dashboard, click **"Add project"**
2. Select **"GitHub"**
3. If not connected, click **"Connect to GitHub"** and authorize
4. Find **"Siyamkhize/rlmsv1"** in the list
5. Check the box next to it
6. Click **"Add selected repositories"**
7. Wait for initial scan to complete

### 2.3 Get Your Snyk API Token

1. Click your profile name (bottom left)
2. Go to **"Account settings"**
3. Scroll to **"API Token"** section
4. Click **"click to show"** to reveal your token
5. Click the **copy icon** to copy it
6. **SAVE THIS TOKEN** securely (add to your Notepad)

---

## STEP 3: Create Codecov Account & Get Token

### 3.1 Sign Up for Codecov

1. Go to: https://codecov.io/
2. Click **"Sign Up"**
3. Choose **"Sign up with GitHub"**
4. Authorize Codecov

### 3.2 Add Your Repository

1. You'll see **"Let's get started"**
2. Click **"Add a repository"**
3. Find **"Siyamkhize/rlmsv1"**
4. Click **"Setup repo"**

### 3.3 Get Your Codecov Token

1. After adding repo, you'll see **"Step 2 - Get Codecov Token"**
2. Your upload token will be displayed
3. **COPY THIS TOKEN** and save it
4. You can also find it later under: Repository Settings → General → Repository Upload Token

---

## STEP 4: Add Secrets to GitHub Repository

Now we'll add all the tokens to GitHub so the CI/CD pipeline can use them.

### 4.1 Go to Repository Settings

1. Open: https://github.com/Siyamkhize/rlmsv1
2. Click **"Settings"** tab (top menu)
3. In left sidebar, scroll down to **"Secrets and variables"**
4. Click **"Actions"**

### 4.2 Add Each Secret

Click **"New repository secret"** for each of these:

#### Secret 1: SONAR_TOKEN
- **Name:** `SONAR_TOKEN`
- **Secret:** Paste your SonarCloud token
- Click **"Add secret"**

#### Secret 2: SONAR_HOST_URL
- **Name:** `SONAR_HOST_URL`
- **Secret:** `https://sonarcloud.io`
- Click **"Add secret"**

#### Secret 3: SNYK_TOKEN
- **Name:** `SNYK_TOKEN`
- **Secret:** Paste your Snyk token
- Click **"Add secret"**

#### Secret 4: CODECOV_TOKEN
- **Name:** `CODECOV_TOKEN`
- **Secret:** Paste your Codecov token
- Click **"Add secret"**

### 4.3 Optional but Recommended Secrets

#### For Firebase App Distribution (if you want automatic app distribution):
- **FIREBASE_STAGING_APP_ID**
- **FIREBASE_PRODUCTION_APP_ID**
- **FIREBASE_CREDENTIALS** (entire JSON file content)

#### For Notifications (optional):
- **SLACK_WEBHOOK** - If you want Slack notifications
- **EMAIL_USERNAME** - For email notifications
- **EMAIL_PASSWORD** - App-specific password
- **SECURITY_EMAIL** - Where to send security alerts

### 4.4 Verify Secrets Are Added

You should now see all secrets listed (values will be hidden for security).

---

## STEP 5: Set Up Branch Protection Rules

This prevents anyone from pushing directly to main/staging and requires all checks to pass.

### 5.1 Protect Main Branch

1. In GitHub repository, go to **"Settings"** → **"Branches"**
2. Under **"Branch protection rules"**, click **"Add rule"**

3. **Configure for `main` branch:**
   - Branch name pattern: `main`
   - Check these boxes:
     ✅ **Require a pull request before merging**
       - Required approvals: `1`
     ✅ **Require status checks to pass before merging**
       - Search and add these required checks:
         - `security-and-quality`
         - `test`
         - `build-android`
       - ✅ **Require branches to be up to date before merging**
     ✅ **Do not allow bypassing the above settings**
     ✅ **Require linear history** (optional but recommended)

4. Click **"Create"** (or **"Save changes"**)

### 5.2 Protect Staging Branch

1. Click **"Add rule"** again
2. **Configure for `staging` branch:**
   - Branch name pattern: `staging`
   - Check these boxes:
     ✅ **Require a pull request before merging**
       - Required approvals: `1`
     ✅ **Require status checks to pass before merging**
       - Add required checks:
         - `security-and-quality`
         - `test`
     ✅ **Require branches to be up to date before merging**

3. Click **"Create"**

### 5.3 Protect Development Branch (Optional but Recommended)

1. Click **"Add rule"** again
2. **Configure for `development` branch:**
   - Branch name pattern: `development`
   - Check these boxes:
     ✅ **Require status checks to pass before merging**
       - Add: `test`

3. Click **"Create"**

---

## STEP 6: Test Your First Deployment

Now let's test that everything works!

### 6.1 View Current Workflows

1. Go to your repository: https://github.com/Siyamkhize/rlmsv1
2. Click **"Actions"** tab
3. You should see 3 workflows:
   - CI/CD Pipeline
   - Quality Gate Check  
   - Nightly Security Scan

### 6.2 Trigger a Manual Test Run

1. Click **"CI/CD Pipeline"** in the left sidebar
2. Click **"Run workflow"** dropdown (top right)
3. Select branch: `main`
4. Click **"Run workflow"** button
5. Wait for the workflow to start (refresh page)

### 6.3 Monitor the Workflow

1. Click on the running workflow (it will be at the top)
2. You'll see each job:
   - `security-and-quality` (will run first)
   - `test` (runs after security passes)
   - `build-android` (runs after tests pass)
   - Deployment jobs (if on staging/main branch)

3. Click on each job to see detailed logs
4. Watch for:
   - ✅ Green checkmarks = Success
   - ❌ Red X = Failed (click to see why)

### 6.4 Review Results

**If everything passes:**
- ✅ All security scans passed
- ✅ All tests passed
- ✅ Build succeeded
- ✅ Your code is ready for deployment!

**If something fails:**
- Click on the failed step
- Read the error message
- Fix the issue locally
- Commit and push again

---

## STEP 7: Test Pull Request Quality Gates

Let's test that PRs are properly protected.

### 7.1 Create a Test Branch

Open PowerShell in your project:

```powershell
cd c:\projects\rlmssv1
git checkout development
git pull origin development
git checkout -b test/verify-ci-cd
```

### 7.2 Make a Small Change

```powershell
# Create a test file
echo "# CI/CD Test" > TEST_FILE.md
git add TEST_FILE.md
git commit -m "test: Verify CI/CD pipeline works"
git push origin test/verify-ci-cd
```

### 7.3 Create Pull Request

1. Go to your GitHub repository
2. You'll see a banner: **"test/verify-ci-cd had recent pushes"**
3. Click **"Compare & pull request"**
4. Base: `development`
5. Compare: `test/verify-ci-cd`
6. Title: "Test: Verify CI/CD Pipeline"
7. Click **"Create pull request"**

### 7.4 Watch Quality Gates Run

1. On the PR page, scroll down to **"All checks have passed"** section
2. You should see:
   - Quality Gate Check (running/passed)
   - Other status checks
3. Wait for all checks to complete
4. You should see a green checkmark ✅ for each

### 7.5 Verify PR Protection

Try to merge:
- If checks pass, you can merge
- If checks fail, merge button is disabled
- Approval is required (if you set it up)

### 7.6 Clean Up Test

After verifying it works:
```powershell
git checkout development
git branch -D test/verify-ci-cd
git push origin --delete test/verify-ci-cd
```

---

## STEP 8: Configure Notifications (Optional)

### 8.1 Slack Notifications

1. Go to your Slack workspace
2. Click workspace name → **Settings & administration** → **Manage apps**
3. Search for **"Incoming Webhooks"**
4. Click **"Add to Slack"**
5. Choose channel (e.g., #deployments)
6. Click **"Add Incoming WebHooks integration"**
7. Copy the **Webhook URL**
8. Add to GitHub Secrets as `SLACK_WEBHOOK`

### 8.2 Email Notifications

You can use GitHub's built-in notifications:
1. Go to: https://github.com/settings/notifications
2. Enable **"Actions"** under **Email notification preferences**
3. You'll get emails when workflows fail

---

## STEP 9: Verify Everything is Working

### 9.1 Check SonarCloud Dashboard

1. Go to: https://sonarcloud.io/dashboard?id=Siyamkhize_rlmsv1
2. You should see:
   - Code quality metrics
   - Security hotspots
   - Coverage data (after tests run)

### 9.2 Check Snyk Dashboard

1. Go to: https://app.snyk.io/org/YOUR_ORG/projects
2. Find your **rlmsv1** project
3. You should see:
   - Dependency vulnerabilities (if any)
   - Code security issues (if any)
   - Fix recommendations

### 9.3 Check Codecov Dashboard

1. Go to: https://codecov.io/gh/Siyamkhize/rlmsv1
2. You should see:
   - Coverage percentage
   - Coverage by file
   - Coverage trends graph

### 9.4 Check GitHub Actions

1. Go to: https://github.com/Siyamkhize/rlmsv1/actions
2. You should see:
   - Recent workflow runs
   - All passing (green checkmarks)
   - No failed runs

---

## ✅ Verification Checklist

Check off each item to confirm setup is complete:

### GitHub Repository
- [ ] Repository exists: https://github.com/Siyamkhize/rlmsv1
- [ ] All code pushed successfully
- [ ] Three branches exist: main, staging, development

### GitHub Secrets (Settings → Secrets → Actions)
- [ ] SONAR_TOKEN added
- [ ] SONAR_HOST_URL added
- [ ] SNYK_TOKEN added
- [ ] CODECOV_TOKEN added

### Branch Protection (Settings → Branches)
- [ ] `main` branch protected (requires PR + checks)
- [ ] `staging` branch protected (requires PR + checks)
- [ ] `development` branch protected (requires checks)

### External Services
- [ ] SonarCloud account created
- [ ] SonarCloud project connected: rlmsv1
- [ ] Snyk account created
- [ ] Snyk project imported: rlmsv1
- [ ] Codecov account created
- [ ] Codecov repository added: rlmsv1

### GitHub Actions
- [ ] Workflows visible in Actions tab
- [ ] CI/CD Pipeline workflow exists
- [ ] Quality Gate workflow exists
- [ ] Nightly Security Scan workflow exists
- [ ] At least one successful workflow run

### Testing
- [ ] Manually triggered workflow run successfully
- [ ] Created test PR and quality gates ran
- [ ] PR checks passed/blocked as expected
- [ ] Can see results in external dashboards

### Documentation
- [ ] Read SECURITY_GUIDELINES.md
- [ ] Read CI_CD_README.md
- [ ] Team members informed about new process

---

## 🚨 Troubleshooting Common Issues

### Issue 1: Workflow Fails with "Secret not found"

**Solution:**
1. Go to Settings → Secrets → Actions
2. Verify secret name matches EXACTLY (case-sensitive)
3. Add the missing secret
4. Re-run the workflow

### Issue 2: SonarQube Scan Fails

**Solution:**
1. Check SONAR_TOKEN is valid
2. Check SONAR_HOST_URL is `https://sonarcloud.io`
3. Verify project exists in SonarCloud
4. Check logs for specific error message

### Issue 3: Snyk Scan Fails

**Solution:**
1. Verify SNYK_TOKEN is valid
2. Check if token has expired
3. Ensure repository is imported in Snyk
4. Review Snyk logs in workflow

### Issue 4: Branch Protection Not Working

**Solution:**
1. Verify you're an admin on the repository
2. Check branch name matches exactly
3. Ensure status checks are required
4. Try creating a new PR to test

### Issue 5: Can't Push to Main Branch

**Solution:**
- This is correct behavior! Branch protection working
- Create a feature branch instead
- Push to feature branch
- Create PR from feature → main

---

## 📞 Getting Help

If you're stuck:

1. **Check Workflow Logs**
   - Go to Actions tab
   - Click failed workflow
   - Click failed step
   - Read error message

2. **Review Documentation**
   - CI_CD_README.md
   - SECURITY_GUIDELINES.md
   - POST_SETUP_CHECKLIST.md

3. **Check External Service Status**
   - SonarCloud status: https://status.sonarcloud.io/
   - Snyk status: https://status.snyk.io/
   - GitHub status: https://www.githubstatus.com/

4. **Common Error Messages**
   - "Authentication failed" = Check your tokens
   - "Resource not found" = Check project exists in service
   - "Permission denied" = Check admin access
   - "Rate limit exceeded" = Wait and try again

---

## 🎉 Success!

If all checkboxes are marked, congratulations! Your CI/CD pipeline is fully operational with:

✅ Automated security scanning  
✅ SQL injection protection  
✅ Dependency vulnerability checking  
✅ Code quality analysis  
✅ Automated testing  
✅ Branch protection  
✅ Deployment automation  

**Your code is now enterprise-grade secure!**

---

## 📅 Ongoing Maintenance

### Weekly Tasks
- Review Snyk vulnerability reports
- Check code coverage trends
- Update dependencies with security patches

### Monthly Tasks
- Review SonarQube quality metrics
- Update security guidelines if needed
- Review and rotate tokens/secrets

### When Issues Arise
- Check nightly security scan emails
- Investigate failed deployments immediately
- Update dependencies when vulnerabilities found

---

**Next:** Start developing with confidence knowing every commit is automatically scanned for security issues!
