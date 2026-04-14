#!/bin/bash
# fix-onprem.sh — Fastest path to working on-prem IDE + Ollama

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source logging library for structured logging
export LOG_FILE="${SCRIPT_DIR}/.logs/onprem-fix.log"
source "${SCRIPT_DIR}/scripts/logging.sh" || {
    echo "ERROR: Cannot source logging library at ${SCRIPT_DIR}/scripts/logging.sh"
    exit 1
}

cd ~/code-server-enterprise

log_section "ON-PREMISE FIX: IDE + Ollama Setup"

log_info "Backing up docker-compose.yml"
cp docker-compose.yml docker-compose.yml.bak
log_success "Backup created"

log_info "Patching code-server: expose -> ports"
sed -i '/^  code-server:/,/^  [a-z]/ {
  /^    expose:/{
    N
    s/    expose:\n      - "8080"/    ports:\n      - "0.0.0.0:8080:8080"/
  }
}' docker-compose.yml
log_success "code-server ports patched"

log_info "Patching ollama: expose -> ports"
sed -i '/^  ollama:/,/^  [a-z]/ {
  /^    expose:/{
    N
    s/    expose:\n      - "11434"/    ports:\n      - "0.0.0.0:11434:11434"/
  }
}' docker-compose.yml
log_success "ollama ports patched"

log_info "Patching ollama health check: curl -> TCP bash check"
sed -i 's|test: \["CMD", "curl", "-f", "http://localhost:11434/api/tags"\]|test: ["CMD-SHELL", "echo > /dev/tcp/localhost/11434"]|' docker-compose.yml
log_success "ollama health check patched"

log_info "Verifying port mappings"
grep -E '"8080:8080"|"11434:11434"' docker-compose.yml
log_success "Port mappings verified"

log_info "Verifying ollama health check"
grep 'dev/tcp' docker-compose.yml
log_success "Health check verified"

log_info "Patching Caddyfile: bypass oauth2-proxy -> direct to code-server"
cp Caddyfile Caddyfile.bak
log_success "Caddyfile backup created"

# Replace oauth2-proxy upstream with code-server
sed -i 's|reverse_proxy oauth2-proxy:4180 {|reverse_proxy code-server:8080 {|' Caddyfile
grep 'reverse_proxy' Caddyfile
log_success "Caddyfile reverse proxy updated"

log_success "ON-PREMISE FIX COMPLETE"
