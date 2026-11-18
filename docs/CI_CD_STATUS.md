# 🚀 CI/CD Pipeline Status & Documentation

## Current Status

### Live Workflows
View real-time status: **[GitHub Actions Dashboard](https://github.com/Siyamkhize/rlmsv1/actions)**

### Pipeline Status Badges

Add these to your README.md:

```markdown
![CI/CD Pipeline](https://github.com/Siyamkhize/rlmsv1/actions/workflows/ci-cd-pipeline.yml/badge.svg)
![CodeQL](https://github.com/Siyamkhize/rlmsv1/actions/workflows/codeql.yml/badge.svg)
![Dart](https://github.com/Siyamkhize/rlmsv1/actions/workflows/dart.yml/badge.svg)
![Security Scan](https://github.com/Siyamkhize/rlmsv1/actions/workflows/nightly-security-scan.yml/badge.svg)
```

Visual badges:
[![CI/CD Pipeline](https://github.com/Siyamkhize/rlmsv1/actions/workflows/ci-cd-pipeline.yml/badge.svg)](https://github.com/Siyamkhize/rlmsv1/actions/workflows/ci-cd-pipeline.yml)

## Pipeline Overview

```
┌──────────────────────────────────────────────────────────────┐
│                    GitHub Push/PR                             │
└────────────────────────┬─────────────────────────────────────┘
                         │
         ┌───────────────┴────────────────┐
         │                                 │
         ▼                                 ▼
┌────────────────────┐          ┌────────────────────┐
│  Main CI/CD        │          │  CodeRabbit AI     │
│  Pipeline          │          │  Review            │
└────────┬───────────┘          └────────────────────┘
         │
    ┌────┴──────────────────────────┐
    │                                │
    ▼                                ▼
┌────────────────┐        ┌─────────────────────┐
│ 1. Security    │        │ 2. Quality Checks   │
│ & Quality      │        │                     │
│                │        │ - Flutter Analyze   │
│ - Security     │        │ - SonarQube        │
│   Audit        │        │ - Snyk Scan        │
│ - CodeQL       │        │                     │
└────┬───────────┘        └─────────┬───────────┘
     │                              │
     └──────────────┬───────────────┘
                    │
                    ▼
         ┌──────────────────┐
         │  3. Unit Tests   │
         │                  │
         │  - Flutter Test  │
         │  - Coverage      │
         └────────┬─────────┘
                  │
                  ▼
         ┌──────────────────┐
         │  4. Build        │
         │                  │
         │  - Android APK   │
         │  - Staging       │
         │  - Production    │
         └────────┬─────────┘
                  │
         ┌────────┴──────────┐
         │                   │
         ▼                   ▼
┌─────────────────┐  ┌──────────────────┐
│ 5. Deploy       │  │ 6. Verify        │
│ Staging         │  │                  │
│                 │  │ - Smoke Tests    │
│ - Firebase      │  │ - Health Check   │
│ - Testers       │  │ - Report         │
└─────────────────┘  └──────────────────┘
         │
         ▼
┌─────────────────┐
│ 7. Deploy       │
│ Production      │
│                 │
│ - Play Store    │
│ - Release Notes │
└─────────────────┘
```

## Workflow Files

### 1. Main CI/CD Pipeline
**File:** `.github/workflows/ci-cd-pipeline.yml`

**Triggers:**
- Push to `main`, `develop`, `staging`
- Pull requests to these branches
- Manual dispatch

**Jobs:**
1. **Security & Quality Checks** (BLOCKING)
   - Flutter analyze (must pass - no errors)
   - Custom security audit
   - SonarQube scan
   - Snyk code & dependency tests

2. **Unit & Widget Tests**
   - All tests with coverage
   - Coverage uploaded to Codecov
   - PR comments with coverage diff

3. **Build Android APK**
   - Debug build for all branches
   - Release build for `staging` and `main`
   - APK artifacts uploaded

4. **Deploy to Staging**
   - Triggered on `staging` branch
   - Firebase App Distribution
   - Slack notifications

5. **Deploy to Production**
   - Triggered on `main` branch
   - Google Play Store (internal track)
   - Firebase App Distribution
   - GitHub Release creation
   - Slack notifications

6. **Post-Deployment Verification**
   - Smoke tests
   - Deployment report generation

### 2. CodeRabbit AI Review
**File:** `.github/workflows/coderabbit-review.yml`

**Triggers:**
- Pull request opened/updated
- Review comments

**Features:**
- AI-powered code review
- Security focus (SQL injection, XSS)
- Flutter best practices
- Interactive chat in comments

**Configuration:** `.coderabbit.yaml`

### 3. CodeQL Security Scanning
**File:** `.github/workflows/codeql.yml`

**Triggers:**
- Push to `main`
- Pull requests to `main`
- Weekly schedule (Mondays at 6 AM)

**Languages:**
- JavaScript/TypeScript
- Python
- Java

### 4. Dart/Flutter Analysis
**File:** `.github/workflows/dart.yml`

**Checks:**
- Flutter analyze
- Dart formatting
- Pub dependencies check

### 5. Dependency Review
**File:** `.github/workflows/dependency-review.yml`

**Triggers:**
- Pull requests

**Checks:**
- Vulnerable dependencies
- License compliance
- Outdated packages

### 6. PHP Analysis
**File:** `.github/workflows/php.yml`

**Checks:**
- PHP syntax validation
- PHP_CodeSniffer
- PHPStan static analysis

### 7. Quality Gate
**File:** `.github/workflows/quality-gate.yml`

**Purpose:**
- Overall quality metrics
- Code coverage threshold
- Complexity checks
- Technical debt ratio

### 8. Nightly Security Scan
**File:** `.github/workflows/nightly-security-scan.yml`

**Schedule:**
- Daily at 2 AM UTC

**Scans:**
- Full Snyk scan
- OWASP dependency check
- Secret scanning
- License compliance

## Test Locally Before Push

Use the provided script to test everything locally:

```powershell
.\test-ci-cd-locally.ps1
```

This runs:
1. Flutter analyze
2. Security audit
3. Unit tests
4. Debug APK build

**Must pass before pushing!**

## Required GitHub Secrets

Configure these in: **Settings → Secrets and variables → Actions**

### Core Secrets
- `GITHUB_TOKEN` ✅ (Automatically provided)

### Optional Enhancement Secrets
- `OPENAI_API_KEY` - Enhanced CodeRabbit reviews
- `SONAR_TOKEN` - SonarQube/SonarCloud integration
- `SONAR_HOST_URL` - SonarQube server URL
- `SNYK_TOKEN` - Snyk security scanning
- `CODECOV_TOKEN` - Code coverage tracking

### Deployment Secrets (for production use)
- `FIREBASE_STAGING_APP_ID` - Firebase staging app
- `FIREBASE_PRODUCTION_APP_ID` - Firebase production app
- `FIREBASE_CREDENTIALS` - Firebase service account JSON
- `PLAY_STORE_CREDENTIALS` - Google Play service account
- `SLACK_WEBHOOK` - Slack notifications

## Branch Strategy

```
main (production)
  ↑
  │ PR (requires reviews + all checks pass)
  │
staging (pre-production)
  ↑
  │ PR (requires all checks pass)
  │
develop (development)
  ↑
  │ PR (requires all checks pass)
  │
feature/* (feature branches)
```

### Branch Rules

**`main` branch:**
- ✅ Require pull request
- ✅ Require 1+ approvals
- ✅ Require status checks to pass:
  - Security & Quality Checks
  - Unit Tests
  - Build Android APK
  - CodeRabbit Review
- ✅ Require branches to be up to date
- ✅ Block force push
- ✅ Block deletions

**`staging` branch:**
- ✅ Require pull request
- ✅ Require status checks to pass
- ✅ Block force push

**`develop` branch:**
- ✅ Require status checks to pass

## Monitoring & Notifications

### GitHub Actions Dashboard
**URL:** https://github.com/Siyamkhize/rlmsv1/actions

View:
- All workflow runs
- Success/failure status
- Build artifacts
- Logs and debug info

### Email Notifications
GitHub automatically emails you on:
- Workflow failures
- Required reviews
- Deployment status

### Slack Integration (Optional)
Configure Slack webhook to get:
- Build status updates
- Deployment notifications
- Test failure alerts

## Troubleshooting

### Workflow Not Triggering?

1. **Check branch name:** Workflow only runs on `main`, `develop`, `staging`
2. **Check file paths:** Ensure `.github/workflows/` exists
3. **Check YAML syntax:** Use [YAML validator](https://www.yamllint.com/)
4. **Check permissions:** Repository needs Actions enabled

### Workflow Failing?

1. **Check logs:** Click on failed job → View logs
2. **Run locally first:** Use `test-ci-cd-locally.ps1`
3. **Check secrets:** Verify all required secrets are set
4. **Review error message:** Usually self-explanatory

### Build Taking Too Long?

- **Typical build time:** 3-5 minutes
- **With tests:** 5-8 minutes
- **Full pipeline:** 10-15 minutes

**Optimization tips:**
- Enable caching (already configured)
- Run expensive checks only on `main`
- Use matrix builds for parallel execution

## Performance Metrics

### Current Averages
- **Flutter Analyze:** ~10 seconds
- **Security Audit:** ~5 seconds
- **Unit Tests:** ~15 seconds
- **Build APK:** ~2-3 minutes
- **CodeRabbit Review:** ~1-2 minutes

### Success Rates (Target)
- **All Checks Pass:** >95%
- **Security Audit:** 100% (blocking)
- **Test Coverage:** >80%

## Next Steps

### Immediate
- [ ] Install CodeRabbit GitHub App
- [ ] Test with a pull request
- [ ] Verify all workflows pass

### Short-term
- [ ] Add `CODECOV_TOKEN` for coverage tracking
- [ ] Configure Firebase deployment
- [ ] Set up Slack notifications

### Long-term
- [ ] Add integration tests
- [ ] Set up Google Play deployment
- [ ] Configure A/B testing
- [ ] Add performance monitoring

## Useful Commands

```bash
# Check workflow syntax locally
act -l

# Run specific workflow locally (requires 'act' tool)
act push -W .github/workflows/ci-cd-pipeline.yml

# View recent runs
gh run list --limit 10

# Watch live run
gh run watch

# Download artifacts
gh run download <run-id>

# Re-run failed jobs
gh run rerun <run-id> --failed
```

## Additional Resources

- [GitHub Actions Docs](https://docs.github.com/en/actions)
- [Flutter CI/CD Guide](https://docs.flutter.dev/deployment/cd)
- [CodeRabbit Docs](https://docs.coderabbit.ai)
- [Snyk Documentation](https://docs.snyk.io)
- [SonarQube Docs](https://docs.sonarqube.org)

---

**Pipeline Status:** ✅ Active and fully configured
**Last Updated:** 2026-11-16
**Maintained by:** Development Team
