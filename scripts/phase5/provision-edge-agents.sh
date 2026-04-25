#!/bin/bash
# @file scripts/phase5/provision-edge-agents.sh
# @description Automated provisioning of regional Edge Agents for Q3 Phase 5 Global Distribution
# @version 1.0.0
# @date April 25, 2026

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/artifacts/phase5/edge-provisioning-$(date +%Y%m%d-%H%M%S).log"
readonly EDGE_IMAGE="kushin77/kushnir-edge-agent:latest"
readonly INSTANCE_TYPE="${INSTANCE_TYPE:-t3.xlarge}"
readonly REGION="${REGION:-us-east-1}"
readonly COUNT="${COUNT:-1}"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# ============================================================================
# LOGGING
# ============================================================================

mkdir -p "$(dirname "$LOG_FILE")"

log_info() {
  echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_FILE"
}

log_success() {
  echo -e "${GREEN}[✓]${NC} $*" | tee -a "$LOG_FILE"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"
}

log_warning() {
  echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "$LOG_FILE"
}

# ============================================================================
# VALIDATION
# ============================================================================

validate_prerequisites() {
  log_info "Validating prerequisites..."
  
  # Check AWS CLI
  if ! command -v aws &> /dev/null; then
    log_error "AWS CLI not found"
    exit 1
  fi
  
  # Check AWS credentials
  if ! aws sts get-caller-identity &> /dev/null; then
    log_error "AWS credentials not configured"
    exit 1
  fi
  
  # Check Docker
  if ! command -v docker &> /dev/null; then
    log_error "Docker not found"
    exit 1
  fi
  
  log_success "All prerequisites satisfied"
}

# ============================================================================
# EDGE AGENT IMAGE PREPARATION
# ============================================================================

build_edge_agent_image() {
  log_info "Building Edge Agent Docker image..."
  
  local build_dir="${SCRIPT_DIR}/docker/edge-agent"
  
  if [[ ! -d "$build_dir" ]]; then
    log_error "Edge Agent Dockerfile not found at $build_dir"
    exit 1
  fi
  
  docker build \
    --tag "$EDGE_IMAGE" \
    --file "$build_dir/Dockerfile" \
    "$build_dir" | tee -a "$LOG_FILE"
  
  log_success "Edge Agent image built successfully"
}

push_edge_agent_image() {
  log_info "Pushing Edge Agent image to registry..."
  
  # Login to Docker registry (assumes credentials in ~/.docker/config.json)
  docker push "$EDGE_IMAGE" | tee -a "$LOG_FILE"
  
  log_success "Edge Agent image pushed successfully"
}

# ============================================================================
# EC2 INSTANCE PROVISIONING
# ============================================================================

provision_instances() {
  log_info "Provisioning $COUNT $INSTANCE_TYPE instances in $REGION..."
  
  local instance_ids=()
  
  # Launch instances
  local launch_result=$(aws ec2 run-instances \
    --region "$REGION" \
    --image-id "$(get_ami_id "$REGION")" \
    --instance-type "$INSTANCE_TYPE" \
    --count "$COUNT" \
    --key-name "kushnir-edge-$(echo "$REGION" | tr '-' '_')" \
    --security-groups "kushnir-edge-sg" \
    --iam-instance-profile "Name=kushnir-edge-instance-profile" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=kushnir-edge-agent},{Key=Region,Value=$REGION},{Key=Phase,Value=5}]" \
    --query 'Instances[*].InstanceId' \
    --output json)
  
  mapfile -t instance_ids < <(echo "$launch_result" | jq -r '.[]')
  
  log_success "Launched ${#instance_ids[@]} instances: ${instance_ids[*]}"
  
  # Wait for instances to be running
  log_info "Waiting for instances to reach running state..."
  aws ec2 wait instance-running \
    --region "$REGION" \
    --instance-ids "${instance_ids[@]}"
  
  log_success "All instances are running"
  
  # Get instance public IPs
  log_info "Retrieving instance details..."
  local instance_details=$(aws ec2 describe-instances \
    --region "$REGION" \
    --instance-ids "${instance_ids[@]}" \
    --query 'Reservations[*].Instances[*].[InstanceId,PublicIpAddress,PrivateIpAddress]' \
    --output json)
  
  echo "$instance_details" | jq -r '.[][] | "\(.[0]): \(.[1])"' | tee -a "$LOG_FILE"
  
  # Store instance IDs for next phase
  mkdir -p "${SCRIPT_DIR}/artifacts/phase5"
  echo "${instance_ids[@]}" > "${SCRIPT_DIR}/artifacts/phase5/edge-instances-${REGION}.txt"
  
  return 0
}

get_ami_id() {
  local region=$1
  # Ubuntu 22.04 LTS with Docker pre-installed
  aws ec2 describe-images \
    --region "$region" \
    --owners canonical \
    --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
    --query 'sort_by(Images, &CreationDate)[-1].[ImageId]' \
    --output text
}

# ============================================================================
# INSTANCE CONFIGURATION
# ============================================================================

configure_instances() {
  log_info "Configuring instances..."
  
  local instance_ids=($(cat "${SCRIPT_DIR}/artifacts/phase5/edge-instances-${REGION}.txt"))
  
  # Get instance details
  local instances=$(aws ec2 describe-instances \
    --region "$REGION" \
    --instance-ids "${instance_ids[@]}" \
    --query 'Reservations[*].Instances[*].PublicIpAddress' \
    --output text)
  
  for ip in $instances; do
    log_info "Configuring instance at $ip..."
    
    # Wait for SSH to be ready
    local retry_count=0
    while ! ssh -o StrictHostKeyChecking=no -i ~/.ssh/kushnir-edge.pem "ubuntu@$ip" "echo 'SSH ready'" &> /dev/null; do
      if [[ $retry_count -ge 30 ]]; then
        log_error "SSH not ready after 5 minutes for $ip"
        exit 1
      fi
      sleep 10
      ((retry_count++))
    done
    
    # Deploy configuration
    ssh -o StrictHostKeyChecking=no -i ~/.ssh/kushnir-edge.pem "ubuntu@$ip" <<'EOF'
      # Install additional tools
      sudo apt-get update
      sudo apt-get install -y docker-compose prometheus-node-exporter jq
      
      # Configure Docker
      sudo usermod -aG docker ubuntu
      
      # Set up monitoring
      sudo systemctl enable prometheus-node-exporter
      sudo systemctl start prometheus-node-exporter
      
      # Create edge agent directory
      mkdir -p /home/ubuntu/edge-agent
      
      echo "✓ Instance configured successfully"
EOF
    
    log_success "Instance at $ip configured"
  done
}

# ============================================================================
# VALIDATION
# ============================================================================

validate_edge_agents() {
  log_info "Validating Edge Agent health..."
  
  local instance_ids=($(cat "${SCRIPT_DIR}/artifacts/phase5/edge-instances-${REGION}.txt"))
  local instances=$(aws ec2 describe-instances \
    --region "$REGION" \
    --instance-ids "${instance_ids[@]}" \
    --query 'Reservations[*].Instances[*].PublicIpAddress' \
    --output text)
  
  local healthy_count=0
  for ip in $instances; do
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i ~/.ssh/kushnir-edge.pem "ubuntu@$ip" "curl -s http://localhost:9100/metrics | grep -q 'node_cpu' && echo 'healthy'" &> /dev/null; then
      log_success "Instance at $ip is healthy"
      ((healthy_count++))
    else
      log_warning "Instance at $ip health check failed"
    fi
  done
  
  log_info "Health check: $healthy_count/${#instance_ids[@]} instances healthy"
  
  if [[ $healthy_count -lt ${#instance_ids[@]} ]]; then
    log_error "Not all instances are healthy"
    exit 1
  fi
  
  log_success "All Edge Agents validated successfully"
}

# ============================================================================
# REPORTING
# ============================================================================

generate_report() {
  log_info "Generating provisioning report..."
  
  local report_file="${SCRIPT_DIR}/artifacts/phase5/edge-provisioning-report-${REGION}-$(date +%Y%m%d).md"
  
  cat > "$report_file" <<EOF
# Edge Agent Provisioning Report

**Region**: $REGION
**Instance Type**: $INSTANCE_TYPE
**Count**: $COUNT
**Image**: $EDGE_IMAGE
**Date**: $(date -u +'%Y-%m-%d %H:%M:%S UTC')

## Instances Provisioned

$(aws ec2 describe-instances \
  --region "$REGION" \
  --instance-ids $(cat "${SCRIPT_DIR}/artifacts/phase5/edge-instances-${REGION}.txt") \
  --query 'Reservations[*].Instances[*].[InstanceId,PublicIpAddress,PrivateIpAddress,InstanceType,State.Name]' \
  --output table)

## Next Steps

1. Deploy Edge Agent application
2. Configure mesh networking
3. Set up monitoring and logging
4. Enable global load balancer routing

## Logs
See: $LOG_FILE
EOF
  
  log_success "Report generated: $report_file"
}

# ============================================================================
# MAIN
# ============================================================================

main() {
  log_info "Starting Edge Agent provisioning for region: $REGION"
  log_info "Instance type: $INSTANCE_TYPE, Count: $COUNT"
  
  validate_prerequisites
  build_edge_agent_image
  push_edge_agent_image
  provision_instances
  configure_instances
  validate_edge_agents
  generate_report
  
  log_success "✓ Edge Agent provisioning complete for region $REGION"
}

main "$@"
