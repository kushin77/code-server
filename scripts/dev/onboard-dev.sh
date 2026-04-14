#!/bin/bash
###############################################################################
# Developer Onboarding Automation Script
# Issue #179: One-command setup for complete dev environment
#
# Usage: bash onboard-dev.sh [OPTIONS]
# 
# This script provisions a complete development environment for new developers
# in under 1 hour, including:
# - Repository clones
# - Tool installation (Docker, kubectl, Dagger, ArgoCD)
# - Kubernetes configuration
# - Git remote setup
# - Pre-commit hooks
# - code-server launch
#
# Requirements: Linux/macOS, bash 4+, internet connection, sudo access
#
###############################################################################

set -e

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Configuration
DEV_HOME="${DEV_HOME:-.}"
REPOS_PATH="${DEV_HOME}/repos"
TOOLS_PATH="${DEV_HOME}/.dev-tools"
GITHUB_ORG="${GITHUB_ORG:-kushin77}"
KUBECONFIG="${HOME}/.kube/config"
VERBOSE="${VERBOSE:-false}"

# Timing
SCRIPT_START=$(date +%s)

###############################################################################
# UTILITY FUNCTIONS
###############################################################################

log() {
    echo -e "${BLUE}[onboard]${NC} $1"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1"
    exit 1
}

heading() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

elapsed_time() {
    local end=$(date +%s)
    local duration=$((end - SCRIPT_START))
    echo "Duration: $(($duration / 60))m $(($duration % 60))s"
}

check_command() {
    if command -v "$1" &> /dev/null; then
        return 0
    else
        return 1
    fi
}

###############################################################################
# Pre-Flight Checks
###############################################################################

phase_preflight() {
    heading "Pre-Flight Checks"
    
    log "Checking system requirements..."
    
    # Check OS
    if [[ "$OSTYPE" =~ ^linux ]]; then
        OS="linux"
        success "Linux detected"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
        success "macOS detected"
    else
        error "Unsupported OS: $OSTYPE"
    fi
    
    # Check bash version
    if [[ ${BASH_VERSINFO[0]} -lt 4 ]]; then
        error "Bash 4.0+ required (current: $BASH_VERSION)"
    fi
    success "Bash version OK ($BASH_VERSION)"
    
    # Check git
    if ! check_command git; then
        error "git not found - install with: apt-get install -y git"
    fi
    success "git found ($(git --version | cut -d' ' -f3))"
    
    # Check internet connectivity
    if ! ping -c1 8.8.8.8 &>/dev/null; then
        warning "Internet connectivity check failed (some downloads may fail)"
    else
        success "Internet connectivity OK"
    fi
    
    # Create directories
    mkdir -p "$REPOS_PATH" "$TOOLS_PATH"
    success "Directories created"
}

###############################################################################
# Repository Setup
###############################################################################

phase_repositories() {
    heading "Repository Setup"
    
    # Main code-server repo
    log "Cloning code-server repository..."
    if [ ! -d "$REPOS_PATH/code-server" ]; then
        cd "$REPOS_PATH"
        git clone "https://github.com/${GITHUB_ORG}/code-server.git"
        cd "code-server"
        success "code-server cloned"
    else
        log "code-server already cloned, pulling latest..."
        cd "$REPOS_PATH/code-server"
        git pull origin main
        success "code-server updated"
    fi
    
    # Configure git remotes
    log "Configuring git remotes..."
    git remote set-url origin "https://github.com/${GITHUB_ORG}/code-server.git"
    git remote add upstream "https://github.com/${GITHUB_ORG}/code-server.git" 2>/dev/null || true
    success "Git remotes configured"
    
    # Set git config
    log "Configuring git..."
    git config --global credential.helper store
    success "Git configuration complete"
}

###############################################################################
# Tool Installation
###############################################################################

phase_tools() {
    heading "Tool Installation"
    
    # Install Docker
    log "Checking Docker..."
    if ! check_command docker; then
        log "Installing Docker..."
        if [ "$OS" = "linux" ]; then
            curl -fsSL https://get.docker.com -o get-docker.sh
            sudo bash get-docker.sh
            rm get-docker.sh
            sudo usermod -aG docker $USER
            success "Docker installed"
        else
            warning "Please install Docker Desktop: https://www.docker.com/products/docker-desktop"
        fi
    else
        success "Docker already installed ($(docker --version | cut -d' ' -f3))"
    fi
    
    # Install kubectl
    log "Checking kubectl..."
    if ! check_command kubectl; then
        log "Installing kubectl..."
        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/$OS/amd64/kubectl"
        sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
        rm kubectl
        success "kubectl installed"
    else
        success "kubectl already installed ($(kubectl version --client --short 2>/dev/null | cut -d':' -f2))"
    fi
    
    # Install dagger
    log "Checking Dagger..."
    if ! check_command dagger; then
        log "Installing Dagger..."
        curl -L https://dl.dagger.io/dagger/install.sh | bash
        success "Dagger installed"
    else
        success "Dagger already installed"
    fi
    
    # Install ArgoCD CLI
    log "Checking ArgoCD CLI..."
    if ! check_command argocd; then
        log "Installing ArgoCD CLI..."
        curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
        sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
        rm argocd-linux-amd64
        success "ArgoCD CLI installed"
    else
        success "ArgoCD CLI already installed"
    fi
    
    # Install Node.js/npm (for code-server extensions)
    log "Checking Node.js..."
    if ! check_command node; then
        log "Installing Node.js..."
        curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
        sudo apt-get install -y nodejs
        success "Node.js installed"
    else
        success "Node.js already installed ($(node --version))"
    fi
    
    # Install Python (for various tools)
    log "Checking Python..."
    if ! check_command python3; then
        log "Installing Python..."
        sudo apt-get install -y python3 python3-pip
        success "Python installed"
    else
        success "Python already installed ($(python3 --version))"
    fi
}

###############################################################################
# Kubernetes Configuration
###############################################################################

phase_kubernetes() {
    heading "Kubernetes Configuration"
    
    # Check if kubeconfig exists
    if [ -f "$KUBECONFIG" ]; then
        log "kubeconfig already exists at $KUBECONFIG"
        log "Current context: $(kubectl config current-context 2>/dev/null || echo 'none')"
        return
    fi
    
    # Try to get kubeconfig from cluster
    log "Attempting to retrieve kubeconfig from cluster..."
    
    if [ -n "$KUBECONFIG_URL" ]; then
        log "Downloading kubeconfig from $KUBECONFIG_URL..."
        mkdir -p "$(dirname "$KUBECONFIG")"
        curl -sSL "$KUBECONFIG_URL" -o "$KUBECONFIG"
        chmod 600 "$KUBECONFIG"
        success "kubeconfig configured"
    else
        warning "KUBECONFIG_URL not set - skipping kubeconfig setup"
        warning "To configure later: export KUBECONFIG_URL=... && source onboard-dev.sh"
    fi
}

###############################################################################
# Pre-Commit Hooks Setup
###############################################################################

phase_precommit() {
    heading "Pre-Commit Hooks Setup"
    
    cd "$REPOS_PATH/code-server"
    
    log "Installing pre-commit hooks..."
    if ! check_command pre-commit; then
        log "Installing pre-commit framework..."
        pip3 install pre-commit
    fi
    
    # Install hooks
    pre-commit install
    success "Pre-commit hooks installed"
}

###############################################################################
# Code-Server Setup
###############################################################################

phase_codeserver() {
    heading "Code-Server Setup"
    
    cd "$REPOS_PATH/code-server"
    
    log "Installing dependencies..."
    if [ -f "package.json" ]; then
        npm install
        success "npm dependencies installed"
    fi
    
    log "Building..."
    if [ -f "Makefile" ]; then
        make build 2>/dev/null || warning "Makefile build failed, continuing..."
    fi
    
    success "code-server ready"
}

###############################################################################
# Configuration
###############################################################################

phase_configuration() {
    heading "Configuration"
    
    # Create .env.development
    log "Creating development environment file..."
    cat > "$REPOS_PATH/code-server/.env.development" << 'EOF'
# Development Environment Configuration

# Server
CODE_SERVER_HOST=127.0.0.1
CODE_SERVER_PORT=8080

# Debug
DEBUG=*
LOG_LEVEL=debug

# Features
FEATURE_FLAGS=dev,test,debug

# Cloudflare (for testing)
CLOUDFLARE_TUNNEL_URL=localhost:8000

# Database (local development)
DATABASE_URL=postgres://localhost/codeserver_dev
REDIS_URL=redis://localhost:6379/0

# Security (dev only)
JWT_SECRET=dev-secret-only-for-testing
EOF
    success ".env.development created"
    
    # Create git hooks
    log "Setting up git hooks..."
    mkdir -p "$REPOS_PATH/code-server/.git/hooks"
    
    cat > "$REPOS_PATH/code-server/.git/hooks/pre-push" << 'EOF'
#!/bin/bash
echo "Running pre-push checks..."
make validate || exit 1
EOF
    chmod +x "$REPOS_PATH/code-server/.git/hooks/pre-push"
    success "Git hooks configured"
}

###############################################################################
# Validation
###############################################################################

phase_validation() {
    heading "Validation"
    
    local failed=0
    
    # Check each tool
    echo "Tool validation:"
    check_command docker && success "Docker" || (warning "Docker" && ((failed++)))
    check_command kubectl && success "kubectl" || (warning "kubectl" && ((failed++)))
    check_command dagger && success "Dagger" || (warning "Dagger" && ((failed++)))
    check_command argocd && success "ArgoCD CLI" || (warning "ArgoCD CLI" && ((failed++)))
    check_command node && success "Node.js" || (warning "Node.js" && ((failed++)))
    check_command python3 && success "Python" || (warning "Python 3" && ((failed++)))
    
    if [ "$failed" -gt 0 ]; then
        warning "$failed tool(s) missing - some features may not work"
    else
        success "All tools available"
    fi
    
    # Check repositories
    if [ -d "$REPOS_PATH/code-server" ]; then
        success "Repositories cloned"
    else
        error "Repository clone failed"
    fi
}

###############################################################################
# Finalization
###############################################################################

phase_finalization() {
    heading "Finalization & Next Steps"
    
    log "Onboarding complete!"
    echo ""
    
    # Print summary
    echo -e "${GREEN}Developer Environment Setup Complete${NC}"
    echo ""
    echo "Repository: $REPOS_PATH/code-server"
    echo "Tools Path: $TOOLS_PATH"
    echo "kubeconfig: $KUBECONFIG"
    echo ""
    
    # Next steps
    echo -e "${BLUE}Next Steps:${NC}"
    echo "1. cd $REPOS_PATH/code-server"
    echo "2. Read DEVELOPMENT.md for dev environment guide"
    echo "3. Run: make dev (to start development server)"
    echo "4. Create feature branch: git checkout -b feature/your-feature"
    echo "5. Make changes and commit"
    echo "6. Create pull request"
    echo ""
    
    # Useful commands
    echo -e "${BLUE}Useful Commands:${NC}"
    echo "  make help              - Show all make targets"
    echo "  make dev               - Start development server"
    echo "  make test              - Run test suite"
    echo "  make lint              - Run linters"
    echo "  make build             - Build project"
    echo "  make health-check      - System health check"
    echo "  make logs              - View service logs"
    echo ""
    
    elapsed_time
    echo ""
}

###############################################################################
# MAIN
###############################################################################

main() {
    # Parse arguments
    SHOW_HELP=false
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                SHOW_HELP=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done
    
    if [ "$SHOW_HELP" = true ]; then
        echo "Developer Onboarding Script"
        echo ""
        echo "Usage: bash onboard-dev.sh [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  -h, --help       Show this help message"
        echo "  -v, --verbose    Enable verbose output"
        echo ""
        return 0
    fi
    
    # Run phases
    phase_preflight
    phase_repositories
    phase_tools
    phase_kubernetes
    phase_precommit
    phase_codeserver
    phase_configuration
    phase_validation
    phase_finalization
}

# Execute
main "$@"

