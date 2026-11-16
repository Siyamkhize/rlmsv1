#!/bin/bash
# Setup script for CI/CD pipeline

set -e

echo "🚀 Setting up CI/CD Pipeline for RLMS"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Make scripts executable
echo -e "${BLUE}📝 Making scripts executable...${NC}"
chmod +x scripts/*.sh
echo -e "${GREEN}✅ Scripts are now executable${NC}"

# Initialize git if not already initialized
if [ ! -d ".git" ]; then
    echo -e "${BLUE}🔧 Initializing git repository...${NC}"
    git init
    echo -e "${GREEN}✅ Git repository initialized${NC}"
else
    echo -e "${GREEN}✅ Git repository already exists${NC}"
fi

# Add remote if not exists
if ! git remote | grep -q origin; then
    echo -e "${BLUE}🔗 Adding remote repository...${NC}"
    git remote add origin https://github.com/Siyamkhize/rlmsv1.git
    echo -e "${GREEN}✅ Remote repository added${NC}"
else
    echo -e "${YELLOW}⚠️  Remote 'origin' already exists${NC}"
fi

# Create necessary branches
echo -e "${BLUE}🌿 Setting up branches...${NC}"

# Get current branch
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "main")

# Create and push main branch
if ! git show-ref --verify --quiet refs/heads/main; then
    git checkout -b main 2>/dev/null || git checkout main
    echo -e "${GREEN}✅ Main branch created${NC}"
fi

# Create and push staging branch
if ! git show-ref --verify --quiet refs/heads/staging; then
    git checkout -b staging 2>/dev/null || true
    echo -e "${GREEN}✅ Staging branch created${NC}"
fi

# Create and push develop branch
if ! git show-ref --verify --quiet refs/heads/develop; then
    git checkout -b develop 2>/dev/null || true
    echo -e "${GREEN}✅ Develop branch created${NC}"
fi

# Return to original or main branch
git checkout "$CURRENT_BRANCH" 2>/dev/null || git checkout main

# Create .gitignore if it doesn't exist
if [ ! -f ".gitignore" ]; then
    echo -e "${BLUE}📝 Creating .gitignore...${NC}"
    cat > .gitignore << 'EOF'
# Miscellaneous
*.class
*.log
*.pyc
*.swp
.DS_Store
.atom/
.buildlog/
.history
.svn/
migrate_working_dir/

# IntelliJ related
*.iml
*.ipr
*.iws
.idea/

# Flutter/Dart/Pub related
**/doc/api/
**/ios/Flutter/.last_build_id
.dart_tool/
.flutter-plugins
.flutter-plugins-dependencies
.packages
.pub-cache/
.pub/
/build/

# Symbolication related
app.*.symbols

# Obfuscation related
app.*.map.json

# Android Studio
.gradle/
local.properties

# Environment files
.env
.env.*
!.env.example
!.env.staging
!.env.production

# Test reports
test-reports/
coverage/
*.log

# Security reports
snyk-report.json
snyk-code-report.json
snyk-iac-report.json
security-report.md
*.sarif

# Build artifacts
*.apk
*.aab
*.ipa
debug-info/

# Temporary files
*.tmp
*.temp
EOF
    echo -e "${GREEN}✅ .gitignore created${NC}"
fi

# Check if required tools are installed
echo -e "\n${BLUE}🔍 Checking required tools...${NC}"

check_tool() {
    if command -v $1 &> /dev/null; then
        echo -e "${GREEN}✅ $1 is installed${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠️  $1 is not installed${NC}"
        return 1
    fi
}

check_tool flutter
check_tool git
check_tool snyk || echo "   Install with: npm install -g snyk"

# Create initial commit
echo -e "\n${BLUE}📦 Creating initial commit...${NC}"
git add .
if git diff --cached --quiet; then
    echo -e "${YELLOW}⚠️  No changes to commit${NC}"
else
    git commit -m "Initial CI/CD setup with security scanning and quality checks" || true
    echo -e "${GREEN}✅ Initial commit created${NC}"
fi

# Display setup summary
echo -e "\n${BLUE}========================================${NC}"
echo -e "${GREEN}✅ CI/CD Pipeline Setup Complete!${NC}"
echo -e "${BLUE}========================================${NC}"

echo -e "\n${YELLOW}Next Steps:${NC}"
echo "1. Configure GitHub repository secrets:"
echo "   - SONAR_TOKEN"
echo "   - SONAR_HOST_URL"
echo "   - SNYK_TOKEN"
echo "   - FIREBASE_STAGING_APP_ID"
echo "   - FIREBASE_PRODUCTION_APP_ID"
echo "   - FIREBASE_CREDENTIALS"
echo "   - CODECOV_TOKEN"
echo "   - SLACK_WEBHOOK (optional)"
echo ""
echo "2. Push to GitHub:"
echo "   git push -u origin main"
echo "   git push -u origin staging"
echo "   git push -u origin develop"
echo ""
echo "3. Set up branch protection rules in GitHub:"
echo "   - Require PR reviews"
echo "   - Require status checks to pass"
echo "   - Require branches to be up to date"
echo ""
echo "4. Test the pipeline:"
echo "   - Create a feature branch"
echo "   - Make changes and push"
echo "   - Create a PR to develop"
echo "   - Watch the quality gates run"
echo ""
echo "5. Read the documentation:"
echo "   - CI_CD_README.md"
echo ""
echo -e "${GREEN}Happy coding! 🎉${NC}"
