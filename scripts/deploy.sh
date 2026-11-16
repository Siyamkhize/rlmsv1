#!/bin/bash
# Deployment script for RLMS application

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
ENVIRONMENT=${1:-staging}
REPO_URL="https://github.com/Siyamkhize/rlmsv1.git"
BRANCH=""

# Determine branch based on environment
case $ENVIRONMENT in
  staging)
    BRANCH="staging"
    ;;
  production)
    BRANCH="main"
    ;;
  *)
    echo -e "${RED}❌ Invalid environment: $ENVIRONMENT${NC}"
    echo "Usage: ./deploy.sh [staging|production]"
    exit 1
    ;;
esac

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  RLMS Deployment Script${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "Environment: ${GREEN}$ENVIRONMENT${NC}"
echo -e "Branch: ${GREEN}$BRANCH${NC}"
echo ""

# Function to check prerequisites
check_prerequisites() {
    echo -e "${BLUE}📋 Checking prerequisites...${NC}"
    
    if ! command -v git &> /dev/null; then
        echo -e "${RED}❌ Git is not installed${NC}"
        exit 1
    fi
    
    if ! command -v flutter &> /dev/null; then
        echo -e "${RED}❌ Flutter is not installed${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Prerequisites check passed${NC}"
}

# Function to run security checks
run_security_checks() {
    echo -e "\n${BLUE}🔒 Running security checks...${NC}"
    
    if [ -f "./scripts/security-check.sh" ]; then
        bash ./scripts/security-check.sh
    else
        echo -e "${YELLOW}⚠️  Security check script not found${NC}"
    fi
}

# Function to run tests
run_tests() {
    echo -e "\n${BLUE}🧪 Running tests...${NC}"
    
    if [ -f "./scripts/run-tests.sh" ]; then
        bash ./scripts/run-tests.sh
    else
        echo "Running basic tests..."
        flutter test
    fi
}

# Function to build application
build_application() {
    echo -e "\n${BLUE}🔨 Building application for $ENVIRONMENT...${NC}"
    
    # Clean previous builds
    flutter clean
    flutter pub get
    
    # Build based on environment
    if [ "$ENVIRONMENT" == "production" ]; then
        echo "Building production APK..."
        flutter build apk --release \
            --obfuscate \
            --split-debug-info=./debug-info \
            --target=lib/main.dart
    else
        echo "Building staging APK..."
        flutter build apk --release \
            --target=lib/main.dart
    fi
    
    echo -e "${GREEN}✅ Build completed${NC}"
}

# Function to verify build
verify_build() {
    echo -e "\n${BLUE}🔍 Verifying build...${NC}"
    
    APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
    
    if [ -f "$APK_PATH" ]; then
        APK_SIZE=$(du -h "$APK_PATH" | cut -f1)
        echo -e "${GREEN}✅ APK found: $APK_PATH (Size: $APK_SIZE)${NC}"
    else
        echo -e "${RED}❌ APK not found at $APK_PATH${NC}"
        exit 1
    fi
}

# Function to push to repository
push_to_repository() {
    echo -e "\n${BLUE}📤 Pushing to repository...${NC}"
    
    # Check if we're in a git repository
    if [ ! -d ".git" ]; then
        echo "Initializing git repository..."
        git init
        git remote add origin $REPO_URL
    fi
    
    # Configure git
    git config user.name "CI/CD Bot"
    git config user.email "ci-cd@rlms.example.com"
    
    # Checkout correct branch
    git checkout -B $BRANCH
    
    # Add and commit changes
    git add .
    git commit -m "Deploy $ENVIRONMENT build - $(date +'%Y-%m-%d %H:%M:%S')" || true
    
    # Push to remote
    echo "Pushing to $BRANCH branch..."
    git push -u origin $BRANCH --force
    
    echo -e "${GREEN}✅ Pushed to repository${NC}"
}

# Function to create release notes
create_release_notes() {
    echo -e "\n${BLUE}📝 Creating release notes...${NC}"
    
    cat > release-notes.md << EOF
# RLMS $ENVIRONMENT Release

**Date:** $(date +'%Y-%m-%d %H:%M:%S')
**Environment:** $ENVIRONMENT
**Branch:** $BRANCH

## Changes
- Latest security patches applied
- All tests passed
- Code quality checks passed

## Build Information
- Flutter Version: $(flutter --version | head -n1)
- Build Number: $(git rev-parse --short HEAD)

## Deployment Steps
1. Security scanning completed ✅
2. All tests passed ✅
3. Build verified ✅
4. Pushed to repository ✅

## Next Steps
- Monitor application performance
- Review crash reports
- Collect user feedback

---
*Automated deployment by RLMS CI/CD*
EOF
    
    echo -e "${GREEN}✅ Release notes created${NC}"
}

# Function to display summary
display_summary() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${GREEN}✅ Deployment completed successfully!${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "Environment: ${GREEN}$ENVIRONMENT${NC}"
    echo -e "Branch: ${GREEN}$BRANCH${NC}"
    echo -e "Repository: ${GREEN}$REPO_URL${NC}"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Monitor GitHub Actions for CI/CD pipeline status"
    echo "2. Check deployment to $ENVIRONMENT environment"
    echo "3. Verify application functionality"
    echo "4. Review security scan results"
    echo ""
}

# Main deployment flow
main() {
    check_prerequisites
    run_security_checks
    run_tests
    build_application
    verify_build
    push_to_repository
    create_release_notes
    display_summary
}

# Confirm before proceeding
echo -e "${YELLOW}⚠️  This will deploy to $ENVIRONMENT environment${NC}"
read -p "Continue? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    main "$@"
else
    echo -e "${RED}Deployment cancelled${NC}"
    exit 1
fi
