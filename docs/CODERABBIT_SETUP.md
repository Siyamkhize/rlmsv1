# 🐰 CodeRabbit AI Code Review Setup

CodeRabbit is now configured for automatic AI-powered code reviews on every pull request!

## What is CodeRabbit?

CodeRabbit is an AI code reviewer that:
- Reviews every pull request automatically
- Identifies bugs, security issues, and code smells
- Suggests improvements and best practices
- Provides line-by-line feedback
- Learns from your codebase patterns

## Setup Instructions

### 1. Install CodeRabbit GitHub App

1. Go to [CodeRabbit GitHub App](https://github.com/apps/coderabbitai)
2. Click **"Install"** or **"Configure"**
3. Select **"Only select repositories"**
4. Choose: `Siyamkhize/rlmsv1`
5. Click **"Install & Authorize"**

### 2. Configure Repository Access

CodeRabbit needs these permissions:
- ✅ **Read** access to code
- ✅ **Write** access to pull requests (to post reviews)
- ✅ **Read** access to workflows

These are automatically granted when you install the app.

### 3. Verify Configuration

After installation:
1. Create a test pull request
2. CodeRabbit should automatically comment within 1-2 minutes
3. Look for the 🐰 CodeRabbit comment with review feedback

### 4. Optional: Enhanced Reviews with OpenAI

For more detailed reviews, add an OpenAI API key:

1. Get API key from [OpenAI Platform](https://platform.openai.com/api-keys)
2. In GitHub repo, go to **Settings → Secrets and variables → Actions**
3. Click **"New repository secret"**
4. Name: `OPENAI_API_KEY`
5. Value: Your OpenAI API key
6. Click **"Add secret"**

**Note:** This is optional. CodeRabbit works without it using their default models.

## Configuration Files

### `.coderabbit.yaml`
Main configuration file with:
- Review settings and focus areas
- File patterns to review
- Security priorities
- Custom instructions for the AI

### `.github/workflows/coderabbit-review.yml`
GitHub Actions workflow that:
- Triggers on every PR
- Runs CodeRabbit review
- Posts summary comments

## How to Use

### Creating a Pull Request

1. Create a branch: `git checkout -b feature/my-feature`
2. Make your changes and commit
3. Push: `git push origin feature/my-feature`
4. Open PR on GitHub
5. CodeRabbit reviews automatically within 1-2 minutes

### Interacting with CodeRabbit

You can chat with CodeRabbit in PR comments:

```
@coderabbitai Can you explain this security concern?
@coderabbitai Is this the best approach for handling async operations?
@coderabbitai Please review the changes in database_helper.dart
```

### Requesting Re-review

After addressing feedback:
```
@coderabbitai Please review the updated code
```

## Review Focus Areas

CodeRabbit is configured to prioritize:

### 🔒 Security (HIGH Priority)
- SQL injection vulnerabilities
- XSS vulnerabilities
- Authentication/authorization issues
- File upload security
- SSL/TLS configuration
- Sensitive data storage

### ⚡ Performance (MEDIUM Priority)
- Database query optimization
- N+1 query problems
- Memory leaks
- Inefficient algorithms

### 📐 Code Quality (MEDIUM Priority)
- Code duplication
- Complex functions
- Naming conventions
- Error handling

### 📚 Best Practices (LOW Priority)
- Flutter/Dart conventions
- PHP best practices
- Documentation
- Testing coverage

## What Files Get Reviewed?

**Included:**
- `lib/**/*.dart` - All Flutter/Dart code
- `mobile/**/*.php` - PHP backend files
- `php/**/*.php` - Additional PHP files
- `test/**/*.dart` - Test files
- Configuration files (`.yaml`, `.yml`, `.json`)

**Excluded:**
- Generated files (`*.g.dart`, `*.freezed.dart`)
- Build artifacts (`build/**`, `.dart_tool/**`)
- Backup files (`*_backup.php`, `*_old.php`)
- Test/debug files (`test_*.php`)
- Dependencies (`node_modules/**`, `vendor/**`)

## Customizing Reviews

Edit `.coderabbit.yaml` to customize:

```yaml
reviews:
  profile: chill  # Options: chill, assertive
  auto_review:
    enabled: true
  
checks:
  security:
    severity: high  # Focus on security
  performance:
    severity: medium
```

## Troubleshooting

### CodeRabbit not commenting on PR?

1. **Check app installation:** Go to [GitHub Apps](https://github.com/apps/coderabbitai/installations) and verify it's installed
2. **Check permissions:** Ensure CodeRabbit has PR write access
3. **Check PR branch:** Must target `main`, `develop`, or `staging`
4. **Wait:** Initial reviews can take 2-3 minutes

### Want to disable for a specific PR?

Add `[skip ci]` or `[skip coderabbit]` to the PR title.

### Want to ignore specific files?

Update `.coderabbit.yaml`:
```yaml
path_ignore:
  - "path/to/ignore/**"
```

## CI/CD Integration

CodeRabbit is integrated with your CI/CD pipeline:

```
┌─────────────────┐
│   Push/PR       │
└────────┬────────┘
         │
    ┌────▼─────────────────┐
    │  GitHub Actions      │
    │  Triggers:           │
    │  1. CodeRabbit       │ ◄── AI Review
    │  2. Security Audit   │
    │  3. Flutter Analyze  │
    │  4. Unit Tests       │
    │  5. Build APK        │
    └──────────────────────┘
```

All checks must pass before merge!

## Best Practices

1. **Review CodeRabbit feedback carefully** - It's AI, not perfect
2. **Engage in discussions** - Ask CodeRabbit to explain suggestions
3. **Address security issues first** - High priority items block merges
4. **Use it as a learning tool** - CodeRabbit explains why something is an issue
5. **Don't auto-approve everything** - Always use your judgment

## Cost & Limits

- **Free tier:** Limited reviews per month
- **Pro tier:** Unlimited reviews, faster processing
- Currently using: **Free tier** (sufficient for small teams)

Upgrade at: [CodeRabbit Pricing](https://coderabbit.ai/pricing)

## Support & Documentation

- **CodeRabbit Docs:** [docs.coderabbit.ai](https://docs.coderabbit.ai)
- **GitHub Issues:** [github.com/coderabbitai/ai-pr-reviewer/issues](https://github.com/coderabbitai/ai-pr-reviewer/issues)
- **Email Support:** support@coderabbit.ai

## Example Review

Here's what a CodeRabbit review looks like:

```markdown
## 🐰 CodeRabbit Review

### Summary
Reviewed 5 files with 127 lines changed.
Found 3 issues: 1 security, 2 code quality.

### 🔒 Security Issues

lib/database_helper.dart:145
- **SQL Injection Risk:** Using string concatenation in query
- **Suggestion:** Use parameterized queries instead
  await db.rawQuery('SELECT * FROM users WHERE id = ?', [userId]);

### 📐 Code Quality

lib/sync_service.dart:89
- **Duplicate Code:** This logic is repeated in 3 places
- **Suggestion:** Extract to a separate method

### ✅ Looks Good
- Proper error handling in all async methods
- Good use of null safety
- Tests cover edge cases

---
**Overall:** 👍 Good changes! Address the SQL injection issue before merging.
```

## Quick Start Checklist

- [ ] Install CodeRabbit GitHub App on repository
- [ ] Verify `.coderabbit.yaml` configuration
- [ ] (Optional) Add `OPENAI_API_KEY` secret for enhanced reviews
- [ ] Create a test PR to verify setup
- [ ] Check that CodeRabbit comments appear
- [ ] Review and customize `.coderabbit.yaml` for your needs

---

**Setup Status:** ✅ Configuration files created and committed
**Next Step:** Install the CodeRabbit GitHub App from the link above!
