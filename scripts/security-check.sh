#!/bin/bash
# Security Check Script for RLMS Flutter Application
# This script runs SonarQube and Snyk security scans

set -e

echo "🔒 Starting Security Checks..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if required tools are installed
check_dependencies() {
    echo "📦 Checking dependencies..."
    
    if ! command -v snyk &> /dev/null; then
        echo -e "${RED}❌ Snyk is not installed. Install it with: npm install -g snyk${NC}"
        exit 1
    fi
    
    if ! command -v sonar-scanner &> /dev/null; then
        echo -e "${YELLOW}⚠️  SonarScanner not found. Will use Docker image if available.${NC}"
    fi
    
    echo -e "${GREEN}✅ Dependencies check passed${NC}"
}

# Run Snyk security scan
run_snyk_scan() {
    echo "🔍 Running Snyk security scan..."
    
    # Authenticate Snyk (assumes SNYK_TOKEN is set)
    if [ -z "$SNYK_TOKEN" ]; then
        echo -e "${YELLOW}⚠️  SNYK_TOKEN not set. Attempting to use existing auth...${NC}"
    else
        snyk auth "$SNYK_TOKEN"
    fi
    
    # Test for vulnerabilities in dependencies
    echo "Scanning dependencies..."
    snyk test --severity-threshold=high --json > snyk-report.json || true
    
    # Monitor the project
    snyk monitor --project-name=rlmsv1 || true
    
    # Code analysis
    echo "Scanning code for security issues..."
    snyk code test --json > snyk-code-report.json || true
    
    # Check for Infrastructure as Code issues
    if [ -d "android" ] || [ -d "ios" ]; then
        echo "Scanning infrastructure configurations..."
        snyk iac test --json > snyk-iac-report.json || true
    fi
    
    echo -e "${GREEN}✅ Snyk scan completed${NC}"
}

# Run SonarQube scan
run_sonarqube_scan() {
    echo "📊 Running SonarQube analysis..."
    
    # Check if sonar-project.properties exists
    if [ ! -f "sonar-project.properties" ]; then
        echo -e "${YELLOW}⚠️  sonar-project.properties not found. Creating default...${NC}"
        create_sonar_properties
    fi
    
    # Run SonarQube scanner
    if command -v sonar-scanner &> /dev/null; then
        sonar-scanner \
            -Dsonar.projectKey=rlmsv1 \
            -Dsonar.sources=. \
            -Dsonar.host.url="${SONAR_HOST_URL:-http://localhost:9000}" \
            -Dsonar.login="${SONAR_TOKEN}"
    else
        echo "Using SonarQube Docker image..."
        docker run --rm \
            -e SONAR_HOST_URL="${SONAR_HOST_URL:-http://localhost:9000}" \
            -e SONAR_LOGIN="${SONAR_TOKEN}" \
            -v "$(pwd):/usr/src" \
            sonarsource/sonar-scanner-cli
    fi
    
    echo -e "${GREEN}✅ SonarQube analysis completed${NC}"
}

# Create default SonarQube properties
create_sonar_properties() {
    cat > sonar-project.properties << EOL
sonar.projectKey=rlmsv1
sonar.projectName=RLMS V1
sonar.projectVersion=1.0

# Path to source directories
sonar.sources=lib,test
sonar.exclusions=**/*.g.dart,**/*.freezed.dart,**/generated/**,**/*.config.dart

# Path to test directories
sonar.tests=test
sonar.test.inclusions=**/*_test.dart

# Dart/Flutter specific settings
sonar.language=dart
sonar.dart.analyzer.report.path=.dart_tool/analysis.log

# Coverage report paths
sonar.dart.coverage.reportPaths=coverage/lcov.info

# Code quality rules
sonar.issue.ignore.multicriteria=e1,e2
sonar.issue.ignore.multicriteria.e1.ruleKey=dart:S*
sonar.issue.ignore.multicriteria.e1.resourceKey=**/*.g.dart
sonar.issue.ignore.multicriteria.e2.ruleKey=dart:S*
sonar.issue.ignore.multicriteria.e2.resourceKey=**/*.freezed.dart
EOL
}

# Generate security report
generate_security_report() {
    echo "📝 Generating security report..."
    
    cat > security-report.md << EOL
# Security Scan Report
Generated: $(date)

## Snyk Vulnerabilities
\`\`\`json
$(cat snyk-report.json 2>/dev/null || echo "{}")
\`\`\`

## Snyk Code Analysis
\`\`\`json
$(cat snyk-code-report.json 2>/dev/null || echo "{}")
\`\`\`

## SonarQube Analysis
Check your SonarQube dashboard at: ${SONAR_HOST_URL:-http://localhost:9000}

## Recommendations
1. Review all HIGH and CRITICAL vulnerabilities
2. Update dependencies with known vulnerabilities
3. Address code quality issues identified by SonarQube
4. Implement security best practices for mobile applications
EOL
    
    echo -e "${GREEN}✅ Security report generated: security-report.md${NC}"
}

# Main execution
main() {
    check_dependencies
    run_snyk_scan
    run_sonarqube_scan
    generate_security_report
    
    echo -e "\n${GREEN}🎉 Security checks completed successfully!${NC}"
    echo "Review the reports and address any critical issues before deployment."
}

main "$@"
