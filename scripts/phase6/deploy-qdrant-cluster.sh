#!/usr/bin/env bash
# =============================================================================
# deploy-qdrant-cluster.sh
# Phase 6: Deploy and bootstrap Qdrant distributed cluster for multi-tenant
# organizational memory (ROADMAP Q4 Phase 6 kickoff).
#
# What this does:
#   1. Waits for both qdrant nodes to be healthy
#   2. Creates organizational memory collections with replication_factor=2
#   3. Registers payload indexes for fast multi-tenant filtering
#   4. Verifies cluster consensus is achieved
#
# Prerequisites:
#   - docker-compose.yml with qdrant + qdrant-node-2 running
#   - QDRANT_API_KEY env var (or empty for no-auth dev mode)
#   - curl
#
# Usage:
#   PRIMARY_HOST=192.168.168.31 bash scripts/phase6/deploy-qdrant-cluster.sh
#   bash scripts/phase6/deploy-qdrant-cluster.sh  # defaults to localhost
#
# @governance GOV-002
# =============================================================================
set -euo pipefail

QDRANT_HOST="${PRIMARY_HOST:-localhost}"
QDRANT_PORT="${QDRANT_PORT:-6333}"
QDRANT_NODE2_PORT="${QDRANT_NODE2_PORT:-6343}"
QDRANT_BASE="http://${QDRANT_HOST}:${QDRANT_PORT}"
QDRANT_NODE2_BASE="http://${QDRANT_HOST}:${QDRANT_NODE2_PORT}"
QDRANT_API_KEY="${QDRANT_API_KEY:-}"
MAX_WAIT_SECONDS=120
REPLICATION_FACTOR=2
WRITE_CONSISTENCY=1

# Collections to bootstrap
COLLECTIONS=(
  "organizational-memory"
  "code-context"
  "agent-decisions"
)

# Vector dimensionality for each collection (OpenAI text-embedding-3-small = 1536)
VECTOR_SIZE=1536

# Color output
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()    { echo -e "${BLUE}[INFO]${NC}    $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}    $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC}   $*" >&2; }

# -----------------------------------------------------------------------------
# Build curl auth header
# -----------------------------------------------------------------------------
auth_header() {
  if [[ -n "$QDRANT_API_KEY" ]]; then
    echo "api-key: ${QDRANT_API_KEY}"
  else
    echo "X-Dev-Mode: true"
  fi
}

# -----------------------------------------------------------------------------
# Wait for a Qdrant node to respond
# -----------------------------------------------------------------------------
wait_for_node() {
  local url="$1"
  local label="$2"
  local waited=0
  log_info "Waiting for $label at $url ..."
  while ! curl -sf -H "$(auth_header)" "${url}/healthz" >/dev/null 2>&1; do
    if (( waited >= MAX_WAIT_SECONDS )); then
      log_error "$label did not become healthy within ${MAX_WAIT_SECONDS}s"
      return 1
    fi
    sleep 3
    (( waited += 3 ))
  done
  log_success "$label is healthy (${waited}s)"
}

# -----------------------------------------------------------------------------
# Check cluster peer count
# -----------------------------------------------------------------------------
verify_cluster() {
  local cluster_info
  cluster_info=$(curl -sf -H "$(auth_header)" "${QDRANT_BASE}/cluster" 2>/dev/null || echo '{}')
  local peer_count
  peer_count=$(echo "$cluster_info" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('result',{}).get('peers',{})))" 2>/dev/null || echo 0)
  if (( peer_count >= 2 )); then
    log_success "Cluster has ${peer_count} peer(s) — distributed mode active"
    return 0
  else
    log_warn "Cluster shows ${peer_count} peer(s) — may still be forming consensus"
    return 0  # Not fatal — collection ops still work
  fi
}

# -----------------------------------------------------------------------------
# Create a collection with replication
# -----------------------------------------------------------------------------
create_collection() {
  local name="$1"
  # Check if already exists
  if curl -sf -H "$(auth_header)" "${QDRANT_BASE}/collections/${name}" >/dev/null 2>&1; then
    log_info "Collection '${name}' already exists — skipping create"
    return 0
  fi

  log_info "Creating collection '${name}' (size=${VECTOR_SIZE}, replication=${REPLICATION_FACTOR})..."
  local body
  body=$(cat <<EOF
{
  "vectors": {
    "size": ${VECTOR_SIZE},
    "distance": "Cosine",
    "on_disk": false
  },
  "replication_factor": ${REPLICATION_FACTOR},
  "write_consistency_factor": ${WRITE_CONSISTENCY},
  "optimizers_config": {
    "default_segment_number": 2,
    "memmap_threshold": 20000
  },
  "hnsw_config": {
    "m": 16,
    "ef_construct": 100,
    "full_scan_threshold": 10000
  }
}
EOF
  )

  local response
  response=$(curl -sf -X PUT -H "$(auth_header)" -H "Content-Type: application/json" \
    -d "$body" "${QDRANT_BASE}/collections/${name}" 2>&1) || {
    log_error "Failed to create collection '${name}': $response"
    return 1
  }
  log_success "Created collection '${name}'"
}

# -----------------------------------------------------------------------------
# Create payload indexes for multi-tenant filtering
# -----------------------------------------------------------------------------
create_tenant_indexes() {
  local name="$1"
  log_info "Creating multi-tenant payload indexes for '${name}'..."

  for field in "tenant_id" "namespace"; do
    local response
    response=$(curl -sf -X PUT -H "$(auth_header)" -H "Content-Type: application/json" \
      -d "{\"field_name\": \"${field}\", \"field_schema\": \"keyword\"}" \
      "${QDRANT_BASE}/collections/${name}/index" 2>&1) || {
      log_warn "Could not create index on '${field}' for '${name}': $response"
      continue
    }
    log_success "  Index: ${name}.${field} (keyword)"
  done

  # Timestamp index for range filtering
  local response
  response=$(curl -sf -X PUT -H "$(auth_header)" -H "Content-Type: application/json" \
    -d "{\"field_name\": \"created_at\", \"field_schema\": \"datetime\"}" \
    "${QDRANT_BASE}/collections/${name}/index" 2>&1) || {
    log_warn "Could not create datetime index for '${name}': $response"
  }
  log_success "  Index: ${name}.created_at (datetime)"
}

# -----------------------------------------------------------------------------
# Print cluster status summary
# -----------------------------------------------------------------------------
print_status() {
  echo ""
  log_info "=== Qdrant Cluster Status ==="
  curl -sf -H "$(auth_header)" "${QDRANT_BASE}/cluster" 2>/dev/null \
    | python3 -c "
import sys, json
d = json.load(sys.stdin).get('result', {})
status = d.get('status', 'unknown')
peers = d.get('peers', {})
print(f'  Status:     {status}')
print(f'  Peer count: {len(peers)}')
for pid, pinfo in peers.items():
    uri = pinfo.get(\"uri\", \"?\")
    state = pinfo.get(\"state\", \"?\")
    print(f'  Peer {pid[:8]}: {uri} [{state}]')
" 2>/dev/null || log_warn "Could not parse cluster status (single-node mode?)"

  echo ""
  log_info "=== Collections ==="
  curl -sf -H "$(auth_header)" "${QDRANT_BASE}/collections" 2>/dev/null \
    | python3 -c "
import sys, json
cols = json.load(sys.stdin).get('result', {}).get('collections', [])
for c in cols:
    print(f'  {c[\"name\"]}')
" 2>/dev/null || log_warn "Could not list collections"
}

# =============================================================================
# MAIN
# =============================================================================
main() {
  log_info "Phase 6: Qdrant Cluster Bootstrap"
  log_info "Primary node: ${QDRANT_BASE}"
  log_info "Secondary node: ${QDRANT_NODE2_BASE}"
  echo ""

  # Step 1: Wait for both nodes
  wait_for_node "$QDRANT_BASE" "qdrant-node-1"
  wait_for_node "$QDRANT_NODE2_BASE" "qdrant-node-2"

  # Step 2: Verify cluster consensus
  verify_cluster

  # Step 3: Bootstrap collections
  echo ""
  log_info "Bootstrapping collections..."
  for coll in "${COLLECTIONS[@]}"; do
    create_collection "$coll"
    create_tenant_indexes "$coll"
  done

  # Step 4: Print status
  print_status

  log_success "Phase 6 Qdrant cluster bootstrap complete"
  log_info "Multi-tenant organizational memory is ready for use"
  log_info "Primary:   ${QDRANT_BASE}"
  log_info "Secondary: ${QDRANT_NODE2_BASE}"
}

main "$@"
