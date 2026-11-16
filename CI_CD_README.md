# CI/CD Pipeline Documentation

## Overview

This document describes the comprehensive CI/CD pipeline for the RLMS (Rural Learner Management System) Flutter application, including security scanning, quality checks, testing, and automated deployment to staging and production environments.

## Pipeline Architecture

### 1. Security & Quality Checks
- **SonarQube Analysis**: Code quality, bugs, vulnerabilities, and code smells
- **Snyk Security Scanning**: 
  - Dependency vulnerabilities
  - Code security issues
  - Infrastructure as Code security
- **Static Analysis**: Flutter analyze for Dart-specific issues
- **Security Linting**: Custom security checks for hardcoded secrets

### 2. Testing
- **Unit Tests**: Automated unit test execution
- **Widget Tests**: UI component testing
- **Integration Tests**: End-to-end testing
- **Coverage Reports**: Minimum 70% code coverage threshold

### 3. Build Process
- **Android APK**: Release builds for both staging and production
- **Code Obfuscation**: Production builds are obfuscated
- **Build Artifacts**: Stored for deployment

### 4. Deployment
- **Staging Environment**: Automatic deployment on `staging` branch
- **Production Environment**: Automatic deployment on `main` branch
- **Environment Separation**: Different configurations for each environment

## Workflows

### Main CI/CD Pipeline (`ci-cd-pipeline.yml`)

Triggered on:
- Push to `main`, `develop`, `staging` branches
- Pull requests to these branches
- Manual workflow dispatch

**Jobs:**
1. **security-and-quality**: SonarQube and Snyk scans
2. **test**: Run all tests with coverage
3. **build-android**: Build APK for the target environment
4. **deploy-staging**: Deploy to staging (staging branch only)
5. **deploy-production**: Deploy to production (main branch only)
6. **verify-deployment**: Post-deployment smoke tests

### Quality Gate Check (`quality-gate.yml`)

Triggered on pull requests to ensure code quality before merging.

**Checks:**
- Static analysis (no errors)
- All tests passing
- Code coverage ≥ 70%
- SonarQube quality gate passed
- No security issues

### Nightly Security Scan (`nightly-security-scan.yml`)

Runs daily at 2 AM UTC to detect new vulnerabilities.

**Scans:**
- Snyk code analysis
- Snyk dependency scan
- OWASP dependency check
- Automated notifications on critical issues

## Required Secrets

Configure these secrets in your GitHub repository settings:

### SonarQube
- `SONAR_TOKEN`: SonarQube authentication token
- `SONAR_HOST_URL`: SonarQube server URL

### Snyk
- `SNYK_TOKEN`: Snyk API authentication token

### Firebase
- `FIREBASE_STAGING_APP_ID`: Firebase App Distribution staging app ID
- `FIREBASE_PRODUCTION_APP_ID`: Firebase App Distribution production app ID
- `FIREBASE_CREDENTIALS`: Firebase service account credentials (JSON)

### Google Play Store
- `PLAY_STORE_CREDENTIALS`: Google Play service account credentials (JSON)

### Notifications
- `SLACK_WEBHOOK`: Slack webhook URL for notifications
- `EMAIL_USERNAME`: Email account for notifications
- `EMAIL_PASSWORD`: Email password
- `SECURITY_EMAIL`: Email address for security alerts

### Code Coverage
- `CODECOV_TOKEN`: Codecov integration token

## Branch Strategy

```
main (production)
  ↑
staging
  ↑
develop
  ↑
feature/* branches
```

### Branch Rules

1. **main**: Production-ready code
   - Requires PR approval
   - All quality gates must pass
   - Automatic deployment to production

2. **staging**: Pre-production testing
   - Requires PR approval
   - All tests must pass
   - Automatic deployment to staging

3. **develop**: Active development
   - Feature branches merge here
   - Continuous integration

4. **feature/***: Individual features
   - Branch from develop
   - PR to develop after completion

## Environment Configuration

### Staging Environment
- File: `.env.staging`
- Branch: `staging`
- Debug mode enabled
- Relaxed security (for testing)
- Firebase staging project

### Production Environment
- File: `.env.production`
- Branch: `main`
- Debug mode disabled
- Strict security
- Code obfuscation enabled
- Firebase production project

## Local Development

### Prerequisites
```bash
# Install Flutter
flutter doctor

# Install Snyk
npm install -g snyk

# Install SonarQube Scanner (optional)
# Or use Docker: docker pull sonarsource/sonar-scanner-cli
```

### Running Security Checks Locally
```bash
# Make scripts executable
chmod +x scripts/*.sh

# Run security checks
./scripts/security-check.sh

# Run tests
./scripts/run-tests.sh
```

### Building Locally
```bash
# Staging build
flutter build apk --release --target=lib/main.dart

# Production build
flutter build apk --release --obfuscate --split-debug-info=./debug-info
```

## Deployment Process

### Automatic Deployment

1. **To Staging:**
   ```bash
   git checkout staging
   git merge develop
   git push origin staging
   ```
   - GitHub Actions automatically builds and deploys

2. **To Production:**
   ```bash
   git checkout main
   git merge staging
   git push origin main
   ```
   - GitHub Actions automatically builds and deploys

### Manual Deployment

```bash
# Deploy to staging
./scripts/deploy.sh staging

# Deploy to production
./scripts/deploy.sh production
```

## Quality Gates

### Must Pass Before Merge
- ✅ No static analysis errors
- ✅ All tests passing
- ✅ Code coverage ≥ 70%
- ✅ SonarQube quality gate passed
- ✅ No HIGH or CRITICAL security vulnerabilities

### Warnings (Non-blocking)
- ⚠️ Code coverage between 70-80%
- ⚠️ Medium severity security issues
- ⚠️ Code smells or technical debt

## Monitoring & Notifications

### Slack Notifications
- Deployment success/failure
- Critical security vulnerabilities
- Build failures

### Email Notifications
- Nightly security scan results
- Critical issues requiring immediate attention

### GitHub Security Tab
- Snyk SARIF reports
- Dependency alerts
- Code scanning results

## Troubleshooting

### Pipeline Failing on Security Checks
1. Review Snyk report in workflow artifacts
2. Update vulnerable dependencies: `flutter pub upgrade`
3. Address code security issues identified

### Tests Failing
1. Run tests locally: `flutter test`
2. Check test output in workflow logs
3. Fix failing tests and re-push

### Coverage Below Threshold
1. Generate coverage report: `flutter test --coverage`
2. Review uncovered code in `coverage/html/index.html`
3. Add tests for uncovered code

### Deployment Failures
1. Check workflow logs for specific errors
2. Verify all secrets are configured correctly
3. Ensure environment configuration files are valid

## Security Best Practices

1. **Never commit secrets**: Use environment variables and GitHub secrets
2. **Regular dependency updates**: Run `flutter pub upgrade` weekly
3. **Monitor security scans**: Review nightly scan results
4. **Code obfuscation**: Always enabled for production builds
5. **SSL pinning**: Enabled in production environment

## Performance Optimization

1. **Code splitting**: Reduce APK size
2. **Lazy loading**: Load features on demand
3. **Image optimization**: Compress images in assets
4. **Caching**: Implement proper caching strategies

## Compliance

- **OWASP Mobile Top 10**: Addressed through security scans
- **Data Privacy**: Environment-specific configurations
- **Audit Trail**: All deployments logged and versioned

## Support

For issues or questions:
- Create an issue in the GitHub repository
- Contact the DevOps team
- Review workflow logs in GitHub Actions

## Changelog

### Version 1.0.0 (2024)
- Initial CI/CD pipeline setup
- SonarQube and Snyk integration
- Automated staging and production deployment
- Quality gate implementation
- Nightly security scans

---

**Last Updated:** November 2026
**Maintained By:** RLMS DevOps Team
