#!/bin/bash
# Comprehensive Test Runner for RLMS Flutter Application

set -e

echo "🧪 Starting Test Suite..."

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test results
UNIT_TEST_RESULT=0
WIDGET_TEST_RESULT=0
INTEGRATION_TEST_RESULT=0
LINT_RESULT=0

# Create test reports directory
mkdir -p test-reports

# Run Flutter analyze
run_static_analysis() {
    echo -e "\n${BLUE}📋 Running static analysis...${NC}"
    
    flutter analyze > test-reports/analysis.log 2>&1 && LINT_RESULT=0 || LINT_RESULT=$?
    
    if [ $LINT_RESULT -eq 0 ]; then
        echo -e "${GREEN}✅ Static analysis passed${NC}"
    else
        echo -e "${RED}❌ Static analysis failed${NC}"
        cat test-reports/analysis.log
    fi
}

# Run unit tests
run_unit_tests() {
    echo -e "\n${BLUE}🧪 Running unit tests...${NC}"
    
    flutter test \
        --coverage \
        --reporter=expanded \
        --machine > test-reports/unit-tests.json 2>&1 && UNIT_TEST_RESULT=0 || UNIT_TEST_RESULT=$?
    
    if [ $UNIT_TEST_RESULT -eq 0 ]; then
        echo -e "${GREEN}✅ Unit tests passed${NC}"
    else
        echo -e "${RED}❌ Unit tests failed${NC}"
    fi
}

# Generate coverage report
generate_coverage() {
    echo -e "\n${BLUE}📊 Generating coverage report...${NC}"
    
    if [ -f "coverage/lcov.info" ]; then
        # Install lcov if not available
        if ! command -v lcov &> /dev/null; then
            echo -e "${YELLOW}⚠️  lcov not installed. Skipping HTML coverage report.${NC}"
        else
            genhtml coverage/lcov.info \
                --output-directory=coverage/html \
                --title="RLMS Test Coverage" \
                --show-details
            
            echo -e "${GREEN}✅ Coverage report generated in coverage/html${NC}"
        fi
        
        # Calculate coverage percentage
        if command -v lcov &> /dev/null; then
            COVERAGE=$(lcov --summary coverage/lcov.info 2>&1 | grep "lines" | awk '{print $2}')
            echo -e "${BLUE}📊 Total Coverage: ${COVERAGE}${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  No coverage data found${NC}"
    fi
}

# Run widget tests
run_widget_tests() {
    echo -e "\n${BLUE}🎨 Running widget tests...${NC}"
    
    flutter test test/widget_test.dart \
        --coverage \
        --reporter=expanded && WIDGET_TEST_RESULT=0 || WIDGET_TEST_RESULT=$?
    
    if [ $WIDGET_TEST_RESULT -eq 0 ]; then
        echo -e "${GREEN}✅ Widget tests passed${NC}"
    else
        echo -e "${RED}❌ Widget tests failed${NC}"
    fi
}

# Check for common security issues in code
run_security_lint() {
    echo -e "\n${BLUE}🔒 Running security linting...${NC}"
    
    # Check for hardcoded secrets
    echo "Checking for hardcoded secrets..."
    if grep -r "password\s*=\s*['\"]" lib/ --include="*.dart" 2>/dev/null; then
        echo -e "${RED}❌ Found hardcoded passwords${NC}"
    fi
    
    if grep -r "api_key\s*=\s*['\"]" lib/ --include="*.dart" 2>/dev/null; then
        echo -e "${RED}❌ Found hardcoded API keys${NC}"
    fi
    
    # Check for insecure HTTP usage
    echo "Checking for insecure HTTP connections..."
    if grep -r "http://" lib/ --include="*.dart" | grep -v "localhost" | grep -v "127.0.0.1" 2>/dev/null; then
        echo -e "${YELLOW}⚠️  Found insecure HTTP connections${NC}"
    fi
    
    echo -e "${GREEN}✅ Security linting completed${NC}"
}

# Generate test report
generate_test_report() {
    echo -e "\n${BLUE}📝 Generating test report...${NC}"
    
    cat > test-reports/test-summary.md << EOL
# Test Summary Report
Generated: $(date)

## Test Results

### Static Analysis
- Status: $([ $LINT_RESULT -eq 0 ] && echo "✅ PASSED" || echo "❌ FAILED")

### Unit Tests
- Status: $([ $UNIT_TEST_RESULT -eq 0 ] && echo "✅ PASSED" || echo "❌ FAILED")

### Widget Tests
- Status: $([ $WIDGET_TEST_RESULT -eq 0 ] && echo "✅ PASSED" || echo "❌ FAILED")

## Coverage Report
$([ -f "coverage/lcov.info" ] && echo "Coverage report available in coverage/html/index.html" || echo "No coverage data generated")

## Analysis Log
\`\`\`
$(cat test-reports/analysis.log 2>/dev/null || echo "No analysis log available")
\`\`\`

## Next Steps
1. Review failed tests and fix issues
2. Improve code coverage to meet minimum threshold (80%)
3. Address all static analysis warnings
4. Run security checks before deployment
EOL
    
    echo -e "${GREEN}✅ Test report generated: test-reports/test-summary.md${NC}"
}

# Check test coverage threshold
check_coverage_threshold() {
    echo -e "\n${BLUE}📊 Checking coverage threshold...${NC}"
    
    MIN_COVERAGE=70
    
    if [ -f "coverage/lcov.info" ] && command -v lcov &> /dev/null; then
        COVERAGE=$(lcov --summary coverage/lcov.info 2>&1 | grep "lines" | awk '{print $2}' | sed 's/%//')
        
        if (( $(echo "$COVERAGE >= $MIN_COVERAGE" | bc -l) )); then
            echo -e "${GREEN}✅ Coverage ${COVERAGE}% meets threshold of ${MIN_COVERAGE}%${NC}"
            return 0
        else
            echo -e "${RED}❌ Coverage ${COVERAGE}% below threshold of ${MIN_COVERAGE}%${NC}"
            return 1
        fi
    else
        echo -e "${YELLOW}⚠️  Cannot check coverage threshold${NC}"
        return 0
    fi
}

# Main execution
main() {
    echo "Starting comprehensive test suite for RLMS..."
    
    # Get dependencies
    echo "Getting Flutter dependencies..."
    flutter pub get
    
    # Run all tests
    run_static_analysis
    run_unit_tests
    run_widget_tests
    generate_coverage
    run_security_lint
    generate_test_report
    
    # Determine overall result
    OVERALL_RESULT=0
    
    if [ $LINT_RESULT -ne 0 ] || [ $UNIT_TEST_RESULT -ne 0 ] || [ $WIDGET_TEST_RESULT -ne 0 ]; then
        OVERALL_RESULT=1
    fi
    
    # Check coverage threshold (warning only, doesn't fail build)
    check_coverage_threshold || echo -e "${YELLOW}⚠️  Coverage below threshold (non-blocking)${NC}"
    
    echo -e "\n${BLUE}==================================${NC}"
    if [ $OVERALL_RESULT -eq 0 ]; then
        echo -e "${GREEN}🎉 All tests passed!${NC}"
    else
        echo -e "${RED}❌ Some tests failed${NC}"
    fi
    echo -e "${BLUE}==================================${NC}"
    
    exit $OVERALL_RESULT
}

main "$@"
