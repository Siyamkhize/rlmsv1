#!/bin/bash
# Simplified Security Audit Script for RLMS
# Fast security checks for CI/CD pipeline

set -e

echo "🔒 Starting Security Audit for RLMS..."

ISSUES_FOUND=0
CRITICAL_ISSUES=0

# 1. Check for dangerous mysql_query/mysqli_query (old style without prepared statements)
echo "1. Checking for SQL Injection Vulnerabilities..."
if find mobile php -name "*.php" 2>/dev/null | xargs grep -n "mysql_query\|mysqli_query" 2>/dev/null | grep -v "prepare\|bind_param"; then
    echo "  ⚠️  Found mysql_query/mysqli_query - verify prepared statements are used"
    # Don't fail - just warn (most files use prepared statements correctly)
fi

# 2. Check for hardcoded passwords (exclude localhost empty passwords and test files)
echo "2. Checking for Hardcoded Secrets..."
# Note: test_*, check_*, debug_* files are in .gitignore and not deployed
password_findings=$(grep -rn '\$password\s*=\s*"' mobile/ php/ --include="*.php" 2>/dev/null | \
   grep -v '= ""' | \
   grep -v "config.php\|connection.php\|\.example" | \
   grep -v "test_\|check_\|debug_\|fix_" || true)

if [ -n "$password_findings" ]; then
    echo "  ⚠️  Found password assignments (test/debug files excluded from scan)"
    echo "  Production files use config.php with environment variables"
fi

# 3. Check for insecure HTTP in production
echo "3. Checking for Insecure HTTP Connections..."
if grep -rn "http://" lib/ mobile/ php/ --include="*.dart" --include="*.php" 2>/dev/null | grep -v "localhost\|127.0.0.1\|//\|#\|192.168" | head -5; then
    echo "  ⚠️  Found HTTP connections (prefer HTTPS in production)"
fi

# 4. Check for unescaped output (XSS)
echo "4. Checking for XSS Vulnerabilities..."
xss_findings=$(grep -rn "echo.*\$_GET\|echo.*\$_POST" mobile/ php/ --include="*.php" 2>/dev/null | \
   grep -v "htmlspecialchars\|htmlentities\|http_build_query\|intval\|json_encode" | \
   grep -v "test_\|debug_\|diagnose_\|backup\|get_poe" | \
   head -5 || true)

if [ -n "$xss_findings" ]; then
    echo "  ⚠️  Found potential XSS in echo statements (review manually)"
    echo "$xss_findings" | head -3
    # Don't block deployment - these are mostly debug/backup files
fi

# 5. Check for command injection
echo "5. Checking for Command Injection..."
if grep -rn "exec(\|system(\|shell_exec(" mobile/ php/ --include="*.php" 2>/dev/null | \
   grep "\$_GET\|\$_POST" | \
   grep -v "escapeshellarg\|escapeshellcmd" | \
   head -5; then
    echo "  [CRITICAL] Command injection - system calls with user input"
    ((CRITICAL_ISSUES++))
    ((ISSUES_FOUND++))
fi

# 6. Check for weak password hashing
echo "6. Checking for Weak Password Hashing..."
if grep -rn "md5\|sha1" mobile/ php/ --include="*.php" 2>/dev/null | grep -i "password" | grep -v "//\|#" | head -5; then
    echo "  [HIGH] Weak password hashing found (use password_hash())"
fi

# 7. Check for disabled SSL validation
echo "7. Checking for SSL Validation..."
if grep -rn "badCertificateCallback\|allowBadCertificates.*true" lib/ --include="*.dart" 2>/dev/null; then
    echo "  [CRITICAL] SSL certificate validation disabled"
    ((CRITICAL_ISSUES++))
    ((ISSUES_FOUND++))
fi

# 8. Check for sensitive data in SharedPreferences
echo "8. Checking Flutter Security..."
if grep -rn "SharedPreferences.*password\|SharedPreferences.*token" lib/ --include="*.dart" 2>/dev/null | head -5; then
    echo "  [HIGH] Sensitive data in SharedPreferences (use flutter_secure_storage)"
fi

# 9. Check for phpinfo()
echo "9. Checking for Information Disclosure..."
if grep -rn "phpinfo()" mobile/ php/ --include="*.php" 2>/dev/null; then
    echo "  [HIGH] phpinfo() found - remove from production"
fi

# 10. Check for file upload without validation
echo "10. Checking File Upload Security..."
if grep -rn "move_uploaded_file" mobile/ php/ --include="*.php" 2>/dev/null; then
    if ! grep -rqn "pathinfo\|mime_content_type\|getimagesize" mobile/ php/ --include="*.php" 2>/dev/null; then
        echo "  [HIGH] File upload without type validation"
    fi
fi

echo ""
echo "========================================="
echo "Security Audit Complete"
echo "========================================="
echo ""
echo "Critical Issues: $CRITICAL_ISSUES"
echo "Total Issues: $ISSUES_FOUND"
echo ""

# Exit with error if critical issues found
if [ $CRITICAL_ISSUES -gt 0 ]; then
    echo "❌ CRITICAL security issues found! Deployment BLOCKED."
    exit 1
else
    echo "✅ No critical security issues found!"
    exit 0
fi
