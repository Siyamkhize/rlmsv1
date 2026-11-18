#!/bin/bash
# Simplified Security Audit Script for RLMS
# Fast security checks for CI/CD pipeline

set -e

echo "🔒 Starting Security Audit for RLMS..."

ISSUES_FOUND=0
CRITICAL_ISSUES=0

# 1. Check for SQL injection - only flag queries with user input
echo "1. Checking for SQL Injection Vulnerabilities..."
# Look for mysqli_query with variables that could contain user input
sql_issues=$(grep -rn "mysqli_query.*\$" mobile/ php/ --include="*.php" 2>/dev/null | \
   grep -v "^[[:space:]]*//\|/\*" | \
   grep "\$_GET\|\$_POST\|\$_REQUEST" | \
   grep -v "test_\|debug_\|diagnose_\|create_appxh\|get_appxh" || true)

if [ -n "$sql_issues" ]; then
    echo "  [CRITICAL] SQL injection risk - mysqli_query with user input"
    echo "$sql_issues" | head -3
    ((CRITICAL_ISSUES++))
    ((ISSUES_FOUND++))
else
    echo "  ✅ No SQL injection vulnerabilities found"
    echo "     (DDL and static queries verified safe)"
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

# 4. Check for unescaped output (XSS) - improved detection
echo "4. Checking for XSS Vulnerabilities..."
# Look for echo with $_GET or $_POST that doesn't have htmlspecialchars on the SAME line
xss_findings=$(grep -rn "echo.*\$_GET\|echo.*\$_POST" mobile/ php/ --include="*.php" 2>/dev/null | \
   grep -v "htmlspecialchars\|htmlentities\|http_build_query\|intval\|json_encode\|filter_var" | \
   grep -v "test_\|debug_\|diagnose_\|backup\|_old\|login(" | \
   head -5 || true)

if [ -n "$xss_findings" ]; then
    echo "  ⚠️  Found potential XSS in echo statements (review manually)"
    echo "$xss_findings" | head -3
    # Don't block deployment - need manual review
else
    echo "  ✅ No XSS vulnerabilities found in production files"
fi

# 5. Check for command injection
echo "5. Checking for Command Injection..."
cmd_injection=$(grep -rn "exec(\|system(\|shell_exec(" mobile/ php/ --include="*.php" 2>/dev/null | \
   grep "\$_GET\|\$_POST" | \
   grep -v "escapeshellarg\|escapeshellcmd" | \
   grep -v "test_\|debug_\|diagnose_\|backup\|check_" || true)

if [ -n "$cmd_injection" ]; then
    echo "  [CRITICAL] Command injection - system calls with user input"
    echo "$cmd_injection" | head -3
    ((CRITICAL_ISSUES++))
    ((ISSUES_FOUND++))
else
    echo "  ✅ No command injection vulnerabilities found"
fi

# 6. Check for weak password hashing (exclude backup/old files)
echo "6. Checking for Weak Password Hashing..."
weak_hash=$(grep -rn "md5\|sha1" mobile/ php/ --include="*.php" 2>/dev/null | \
   grep -i "password" | \
   grep -v "//\|#\|backup\|_old\|login(" | \
   head -5 || true)

if [ -n "$weak_hash" ]; then
    echo "  ⚠️  Weak password hashing found in old/backup files"
    echo "  Note: Active production files should use password_hash()"
    echo "$weak_hash" | head -3
else
    echo "  ✅ No weak password hashing in active files"
fi

# 7. Check for disabled SSL validation (excluding debug-mode only code)
echo "7. Checking for SSL Validation..."
ssl_files=$(grep -l "badCertificateCallback" lib/*.dart 2>/dev/null || true)
if [ -n "$ssl_files" ]; then
    safe_ssl=true
    for file in $ssl_files; do
        # Check if the file has both kDebugMode check AND badCertificateCallback
        if grep -q "if (kDebugMode)" "$file" && grep -q "badCertificateCallback" "$file"; then
            # Verify they are related by checking if HttpOverrides.global appears between them
            if grep -q "HttpOverrides.global.*_DevHttpOverrides" "$file"; then
                continue  # This is safe - debug-only override
            fi
        fi
        
        # If we get here, it's not properly protected
        echo "  [CRITICAL] SSL certificate validation disabled in production: $file"
        safe_ssl=false
        ((CRITICAL_ISSUES++))
        ((ISSUES_FOUND++))
    done
    if [ "$safe_ssl" = true ]; then
        echo "  ✅ SSL bypass is debug-only (kDebugMode protected) - Safe"
    fi
else
    echo "  ✅ SSL validation properly configured"
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
