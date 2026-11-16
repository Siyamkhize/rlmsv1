#!/bin/bash
# Security Audit Script for RLMS - SQL Injection and Security Vulnerabilities
# This script checks for common security issues before deployment

set -e

echo "🔒 Starting Security Audit for RLMS..."

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ISSUES_FOUND=0
CRITICAL_ISSUES=0
HIGH_ISSUES=0
MEDIUM_ISSUES=0

# Create audit report directory
REPORT_DIR="security-audit-reports"
mkdir -p "$REPORT_DIR"
REPORT_FILE="$REPORT_DIR/security-audit-$(date +%Y%m%d-%H%M%S).txt"

echo "Security Audit Report - $(date)" > "$REPORT_FILE"
echo "========================================" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Function to log issue
log_issue() {
    local severity=$1
    local file=$2
    local line=$3
    local issue=$4
    
    echo -e "${RED}[$severity]${NC} $file:$line - $issue"
    echo "[$severity] $file:$line - $issue" >> "$REPORT_FILE"
    
    case $severity in
        CRITICAL)
            ((CRITICAL_ISSUES++))
            ((ISSUES_FOUND++))
            ;;
        HIGH)
            ((HIGH_ISSUES++))
            ((ISSUES_FOUND++))
            ;;
        MEDIUM)
            ((MEDIUM_ISSUES++))
            ((ISSUES_FOUND++))
            ;;
    esac
}

echo -e "\n${BLUE}1. Checking for SQL Injection Vulnerabilities...${NC}"
echo "" >> "$REPORT_FILE"
echo "1. SQL INJECTION CHECKS" >> "$REPORT_FILE"
echo "======================" >> "$REPORT_FILE"

# Check PHP files for unsafe SQL queries
echo "Scanning PHP files..."
if [ -d "mobile" ] || [ -d "php" ]; then
    # Check for dangerous patterns that indicate SQL injection
    # Only flag mysql_query/mysqli_query with variables (old unsafe style)
    while IFS= read -r file; do
        line_num=1
        while IFS= read -r line; do
            # Flag mysql_query/mysqli_query with direct variables (old style)
            if echo "$line" | grep -iE "mysql_query\(.*\\\$|mysqli_query\(.*\\\$" > /dev/null; then
                # But allow if it's part of a prepared statement workflow
                if ! grep -qE "prepare|bind_param" "$file"; then
                    log_issue "CRITICAL" "$file" "$line_num" "SQL injection - mysql_query/mysqli_query without prepared statements"
                fi
            fi
            
            # Flag direct user input in SQL (very dangerous)
            if echo "$line" | grep -iE "(SELECT|INSERT|UPDATE|DELETE).*\\\$_(GET|POST|REQUEST)" > /dev/null; then
                if ! echo "$line" | grep -qE "prepare|bind_param|intval|mysqli_real_escape_string"; then
                    log_issue "CRITICAL" "$file" "$line_num" "SQL injection - User input directly in query without sanitization"
                fi
            fi
            
            ((line_num++))
        done < "$file"
    done < <(find mobile php -name "*.php" 2>/dev/null || true)
fi

echo -e "\n${BLUE}2. Checking for Hardcoded Secrets...${NC}"
echo "" >> "$REPORT_FILE"
echo "2. HARDCODED SECRETS" >> "$REPORT_FILE"
echo "====================" >> "$REPORT_FILE"

# Check for hardcoded passwords
if grep -rn "password.*=.*['\"]" mobile/ php/ lib/ --include="*.php" --include="*.dart" 2>/dev/null | grep -v "password_hash\|hashed_password\|//\|#" | grep -v "Enter password\|password field\|Password:\|'password'"; then
    log_issue "CRITICAL" "Multiple files" "N/A" "Hardcoded passwords found"
fi

# Check for API keys
if grep -rn "api.*key.*=.*['\"][a-zA-Z0-9]{20,}" mobile/ php/ lib/ --include="*.php" --include="*.dart" 2>/dev/null | grep -v "//\|#"; then
    log_issue "HIGH" "Multiple files" "N/A" "Hardcoded API keys found"
fi

# Check for database credentials in code
if grep -rn "DB_PASSWORD\|db_password\|database.*password" mobile/ php/ lib/ --include="*.php" --include="*.dart" 2>/dev/null | grep "=" | grep -v "\$_ENV\|\$config\|getenv" | grep -v "//\|#"; then
    log_issue "CRITICAL" "Multiple files" "N/A" "Database passwords in code"
fi

echo -e "\n${BLUE}3. Checking for Insecure HTTP Connections...${NC}"
echo "" >> "$REPORT_FILE"
echo "3. INSECURE CONNECTIONS" >> "$REPORT_FILE"
echo "=======================" >> "$REPORT_FILE"

# Check for HTTP (not HTTPS) in production code
if grep -rn "http://" lib/ mobile/ php/ --include="*.dart" --include="*.php" 2>/dev/null | grep -v "localhost\|127.0.0.1\|//\|#\|comment"; then
    log_issue "HIGH" "Multiple files" "N/A" "Insecure HTTP connections found (should use HTTPS)"
fi

echo -e "\n${BLUE}4. Checking for XSS Vulnerabilities...${NC}"
echo "" >> "$REPORT_FILE"
echo "4. XSS VULNERABILITIES" >> "$REPORT_FILE"
echo "======================" >> "$REPORT_FILE"

# Check for unescaped output in PHP
if grep -rn "echo.*\\\$_\(GET\|POST\|REQUEST\)" mobile/ php/ --include="*.php" 2>/dev/null | grep -v "htmlspecialchars\|htmlentities"; then
    log_issue "HIGH" "Multiple files" "N/A" "Potential XSS - Unescaped user input in output"
fi

echo -e "\n${BLUE}5. Checking for Path Traversal...${NC}"
echo "" >> "$REPORT_FILE"
echo "5. PATH TRAVERSAL" >> "$REPORT_FILE"
echo "==================" >> "$REPORT_FILE"

# Check for unsafe file operations
if grep -rn "fopen\|file_get_contents\|include\|require" mobile/ php/ --include="*.php" 2>/dev/null | grep "\$_\(GET\|POST\|REQUEST\)" | grep -v "realpath\|basename"; then
    log_issue "CRITICAL" "Multiple files" "N/A" "Path traversal vulnerability - User input in file operations"
fi

echo -e "\n${BLUE}6. Checking for Command Injection...${NC}"
echo "" >> "$REPORT_FILE"
echo "6. COMMAND INJECTION" >> "$REPORT_FILE"
echo "====================" >> "$REPORT_FILE"

# Check for unsafe system calls
if grep -rn "exec\|system\|shell_exec\|passthru\|proc_open" mobile/ php/ --include="*.php" 2>/dev/null | grep "\$_\(GET\|POST\|REQUEST\)" | grep -v "escapeshellarg\|escapeshellcmd"; then
    log_issue "CRITICAL" "Multiple files" "N/A" "Command injection - Unescaped user input in system calls"
fi

echo -e "\n${BLUE}7. Checking for Authentication Issues...${NC}"
echo "" >> "$REPORT_FILE"
echo "7. AUTHENTICATION" >> "$REPORT_FILE"
echo "=================" >> "$REPORT_FILE"

# Check for weak password hashing
if grep -rn "md5\|sha1" mobile/ php/ --include="*.php" 2>/dev/null | grep -i "password" | grep -v "//\|#"; then
    log_issue "HIGH" "Multiple files" "N/A" "Weak password hashing (MD5/SHA1) - Use password_hash()"
fi

# Check for session management issues
if grep -rn "session_start" mobile/ php/ --include="*.php" 2>/dev/null; then
    if ! grep -rn "session_regenerate_id" mobile/ php/ --include="*.php" 2>/dev/null > /dev/null; then
        log_issue "MEDIUM" "Multiple files" "N/A" "Missing session_regenerate_id() - Session fixation risk"
    fi
fi

echo -e "\n${BLUE}8. Checking for CSRF Protection...${NC}"
echo "" >> "$REPORT_FILE"
echo "8. CSRF PROTECTION" >> "$REPORT_FILE"
echo "==================" >> "$REPORT_FILE"

# Check if forms have CSRF tokens
php_forms=$(grep -rn "<form" mobile/ php/ --include="*.php" 2>/dev/null | wc -l || echo "0")
csrf_tokens=$(grep -rn "csrf.*token\|_token" mobile/ php/ --include="*.php" 2>/dev/null | wc -l || echo "0")

if [ "$php_forms" -gt 0 ] && [ "$csrf_tokens" -eq 0 ]; then
    log_issue "HIGH" "Multiple files" "N/A" "Forms without CSRF protection"
fi

echo -e "\n${BLUE}9. Checking for File Upload Vulnerabilities...${NC}"
echo "" >> "$REPORT_FILE"
echo "9. FILE UPLOAD SECURITY" >> "$REPORT_FILE"
echo "=======================" >> "$REPORT_FILE"

# Check for unsafe file uploads
if grep -rn "move_uploaded_file\|\\$_FILES" mobile/ php/ --include="*.php" 2>/dev/null; then
    if ! grep -rn "pathinfo\|mime_content_type\|getimagesize" mobile/ php/ --include="*.php" 2>/dev/null > /dev/null; then
        log_issue "HIGH" "Multiple files" "N/A" "File upload without type validation"
    fi
fi

echo -e "\n${BLUE}10. Checking for Information Disclosure...${NC}"
echo "" >> "$REPORT_FILE"
echo "10. INFORMATION DISCLOSURE" >> "$REPORT_FILE"
echo "==========================" >> "$REPORT_FILE"

# Check for error display in production
if grep -rn "ini_set.*display_errors.*On\|error_reporting.*E_ALL" mobile/ php/ --include="*.php" 2>/dev/null | grep -v "//\|#"; then
    log_issue "MEDIUM" "Multiple files" "N/A" "Error display enabled - Information disclosure risk"
fi

# Check for phpinfo()
if grep -rn "phpinfo()" mobile/ php/ --include="*.php" 2>/dev/null; then
    log_issue "HIGH" "Multiple files" "N/A" "phpinfo() found - Remove from production"
fi

echo -e "\n${BLUE}11. Checking Dart/Flutter Security...${NC}"
echo "" >> "$REPORT_FILE"
echo "11. FLUTTER/DART SECURITY" >> "$REPORT_FILE"
echo "==========================" >> "$REPORT_FILE"

# Check for insecure data storage
if grep -rn "SharedPreferences.*password\|SharedPreferences.*token" lib/ --include="*.dart" 2>/dev/null; then
    log_issue "HIGH" "Multiple files" "N/A" "Sensitive data in SharedPreferences - Use flutter_secure_storage"
fi

# Check for disabled SSL certificate validation
if grep -rn "badCertificateCallback\|allowBadCertificates.*true" lib/ --include="*.dart" 2>/dev/null; then
    log_issue "CRITICAL" "Multiple files" "N/A" "SSL certificate validation disabled"
fi

# Summary
echo "" >> "$REPORT_FILE"
echo "SUMMARY" >> "$REPORT_FILE"
echo "=======" >> "$REPORT_FILE"
echo "Critical Issues: $CRITICAL_ISSUES" >> "$REPORT_FILE"
echo "High Issues: $HIGH_ISSUES" >> "$REPORT_FILE"
echo "Medium Issues: $MEDIUM_ISSUES" >> "$REPORT_FILE"
echo "Total Issues: $ISSUES_FOUND" >> "$REPORT_FILE"

echo ""
echo "========================================="
echo -e "${BLUE}Security Audit Complete${NC}"
echo "========================================="
echo ""
echo -e "Critical Issues: ${RED}$CRITICAL_ISSUES${NC}"
echo -e "High Issues: ${YELLOW}$HIGH_ISSUES${NC}"
echo -e "Medium Issues: ${YELLOW}$MEDIUM_ISSUES${NC}"
echo -e "Total Issues: $ISSUES_FOUND"
echo ""
echo "Full report saved to: $REPORT_FILE"
echo ""

# Exit with error if critical or high issues found
if [ $CRITICAL_ISSUES -gt 0 ]; then
    echo -e "${RED}❌ CRITICAL security issues found! Deployment BLOCKED.${NC}"
    exit 1
elif [ $HIGH_ISSUES -gt 5 ]; then
    echo -e "${RED}❌ Too many HIGH security issues! Deployment BLOCKED.${NC}"
    exit 1
elif [ $ISSUES_FOUND -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Security issues found. Review before deployment.${NC}"
    exit 0
else
    echo -e "${GREEN}✅ No critical security issues found!${NC}"
    exit 0
fi
