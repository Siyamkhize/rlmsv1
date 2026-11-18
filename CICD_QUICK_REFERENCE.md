# CI/CD Quick Reference Card

## 🚀 Quick Links

- **Actions Dashboard:** https://github.com/Siyamkhize/rlmsv1/actions
- **Security Tab:** https://github.com/Siyamkhize/rlmsv1/security
- **Full Guide:** [COMPREHENSIVE_CICD_GUIDE.md](COMPREHENSIVE_CICD_GUIDE.md)

---

## 📋 Workflow Summary

| Workflow | Trigger | Duration | Purpose |
|----------|---------|----------|---------|
| **Comprehensive CI/CD** | Push/PR to main/staging/develop | ~40 min | Full deployment pipeline |
| **Advanced Security** | Daily 2 AM UTC + Push/PR | ~30 min | 9 security tools scan |
| **Performance & Quality** | Every 6 hours + Push/PR | ~20 min | Quality metrics |
| Dart CI | Push/PR | ~15 min | Flutter analyze + build |
| PHP CI | Push/PR to PHP files | ~5 min | PHP syntax checks |
| CodeQL | Push/PR + Weekly | ~20 min | Security scanning |
| Dependency Review | Pull requests | ~5 min | Dependency vulnerabilities |
| Quality Gate | Push/PR | ~10 min | Code quality metrics |

---

## 🌍 Environment Mapping

| Branch | Environment | URL | Auto-Deploy | Approval |
|--------|-------------|-----|-------------|----------|
| `develop` | Development | dev.rlms.example.com | ✅ Yes | ❌ No |
| `staging` | Staging | staging.rlms.example.com | ✅ Yes | ❌ No |
| `main` | Production | rlms.example.com | ✅ Yes | ✅ **Required** |

---

## 🔒 Security Tools

| Tool | Purpose | Frequency | Critical Threshold |
|------|---------|-----------|-------------------|
| Trivy | Vulnerability scanning | Every push | HIGH/CRITICAL |
| GitLeaks | Secret detection | Every push | Any exposure |
| OWASP | Dependency CVEs | Every push | CVSS ≥ 7 |
| Semgrep | SAST | Every push | security-audit |
| Snyk | Dependency security | Every push | HIGH/CRITICAL |
| ClamAV | Malware | Daily | Any detection |
| TruffleHog | Historical secrets | Daily | Any exposure |
| OWASP ZAP | API testing | Daily | HIGH/CRITICAL |
| Checkov | IaC security | Every push | HIGH/CRITICAL |

---

## 🎯 Quick Commands

### Local Pre-Push Checks
```bash
# Run before pushing to catch issues early
flutter analyze --no-fatal-infos
flutter test
flutter build apk --debug
```

### Trigger Deployments
```bash
# Deploy to Development
git push origin develop

# Deploy to Staging
git checkout staging
git merge develop
git push origin staging

# Deploy to Production
git checkout main
git merge staging
git push origin main
```

### Manual Workflow Trigger
```bash
# Via GitHub CLI
gh workflow run comprehensive-cicd.yml

# Via GitHub UI
# Actions → Select workflow → Run workflow
```

### View Workflow Status
```bash
# List recent runs
gh run list --limit 10

# Watch specific run
gh run watch

# View run details
gh run view <run-id>
```

---

## 📊 Status Checks

### Before Merging PR

✅ **Must be GREEN:**
- Flutter Analyze (0 blocking errors)
- Security Scan (0 critical/high)
- Unit Tests (all passing)
- Build (APK created successfully)

⚠️ **Can be YELLOW (warnings OK):**
- Code Quality (informational)
- Performance Tests (degradation logged)
- Accessibility (issues logged)

---

## 🚨 Common Issues & Quick Fixes

### Issue: Security scan failing
```bash
# Update dependencies
flutter pub upgrade

# Check for secrets
git grep -i "password\|api_key\|secret"

# Run local security check
git secrets --scan
```

### Issue: Build failing
```bash
# Clean and rebuild
flutter clean
flutter pub get
flutter build apk --debug
```

### Issue: Tests failing
```bash
# Run tests locally
flutter test

# Run specific test
flutter test test/widget_test.dart

# With verbose output
flutter test --verbose
```

### Issue: Deployment not triggering
1. Check branch name (exact: develop/staging/main)
2. Verify all CI checks passed
3. Check GitHub environment protection rules
4. Ensure required secrets configured

---

## 🔧 Required Secrets

### Firebase (Deployments)
- `FIREBASE_DEV_APP_ID`
- `FIREBASE_STAGING_APP_ID`
- `FIREBASE_PRODUCTION_APP_ID`
- `FIREBASE_CREDENTIALS`

### Google Play (Production)
- `PLAY_STORE_CREDENTIALS`

### Optional (Enhanced Features)
- `SONAR_TOKEN` - SonarCloud
- `SNYK_TOKEN` - Snyk scanning
- `CODECOV_TOKEN` - Coverage reports
- `SLACK_WEBHOOK` - Notifications

**Add at:** Settings → Secrets and variables → Actions

---

## 📈 Quality Metrics

### Target Thresholds

| Metric | Target | Critical |
|--------|--------|----------|
| Build Time | < 10 min | > 20 min |
| Test Duration | < 5 min | > 10 min |
| APK Size | < 150 MB | > 200 MB |
| Test Coverage | > 70% | < 50% |
| Security Issues | 0 critical | Any critical |
| Code Smells | < 50 | > 200 |

---

## 🎭 Branch Protection Rules

### Recommended Settings

**develop:**
- Require 1 approval
- Require status checks: All CI
- No force push

**staging:**
- Require 1 approval
- Require status checks: All CI + Security
- No force push

**main:**
- Require 2 approvals
- Require status checks: ALL
- Require signed commits
- No force push, no deletions

---

## 📞 Getting Help

1. **Check workflow logs:** Actions → Click run → View logs
2. **Download artifacts:** Actions → Run → Artifacts section
3. **Security findings:** Security → Code scanning alerts
4. **Full documentation:** [COMPREHENSIVE_CICD_GUIDE.md](COMPREHENSIVE_CICD_GUIDE.md)
5. **Create issue:** Use bug/feature templates

---

## ✅ Health Check

Your CI/CD is healthy when:

- ✅ All workflows show green checkmarks
- ✅ Security tab has 0 critical issues
- ✅ Latest commit on all branches passes
- ✅ Deployments happen automatically
- ✅ Artifacts available after runs
- ✅ Coverage reports generated
- ✅ APK size within threshold

**Check now:** https://github.com/Siyamkhize/rlmsv1/actions

---

## 🎉 Quick Win Checklist

- [x] CI/CD workflows created
- [x] Security scanning configured
- [x] Multi-environment setup
- [x] Quality monitoring enabled
- [x] Documentation complete
- [ ] Add Firebase secrets
- [ ] Add Google Play credentials
- [ ] Configure branch protection
- [ ] Set up Slack notifications
- [ ] Add optional tool tokens

---

*Last Updated: 2026-11-16*
*Version: 1.0 (Production-Grade)*
