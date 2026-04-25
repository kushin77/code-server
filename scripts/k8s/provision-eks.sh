#!/bin/bash
# scripts/k8s/provision-eks.sh
# Automated EKS cluster provisioning for code-server-enterprise
# Usage: bash provision-eks.sh [environment]

set -euo pipefail

# ===== CONFIGURATION =====
ENVIRONMENT="${1:-production}"
AWS_REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="code-server-enterprise-${ENVIRONMENT}"
NODE_GROUP_MIN=3
NODE_GROUP_MAX=10
NODE_GROUP_DESIRED=5
NODE_INSTANCE_TYPE="t3.xlarge"
NODE_DISK_SIZE=50

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}[INFO]${NC} Starting EKS cluster provisioning for ${ENVIRONMENT}"

# ===== PHASE 1: PRE-FLIGHT CHECKS =====
echo -e "${YELLOW}[PHASE 1]${NC} Pre-flight validation"

if ! command -v aws &> /dev/null; then
  echo -e "${RED}[ERROR]${NC} AWS CLI not found. Please install: https://aws.amazon.com/cli/"
  exit 1
fi

if ! command -v terraform &> /dev/null; then
  echo -e "${RED}[ERROR]${NC} Terraform not found. Please install: https://www.terraform.io/"
  exit 1
fi

if ! command -v kubectl &> /dev/null; then
  echo -e "${RED}[ERROR]${NC} kubectl not found. Please install: https://kubernetes.io/docs/tasks/tools/"
  exit 1
fi

# Verify AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
  echo -e "${RED}[ERROR]${NC} AWS credentials not configured"
  exit 1
fi

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo -e "${GREEN}[✓]${NC} AWS Account ID: ${AWS_ACCOUNT_ID}"

# ===== PHASE 2: TERRAFORM INITIALIZATION =====
echo -e "${YELLOW}[PHASE 2]${NC} Terraform initialization"

cd terraform/eks

if [ ! -f .terraform ]; then
  echo -e "${GREEN}[INFO]${NC} Initializing Terraform"
  terraform init -upgrade
fi

terraform validate
echo -e "${GREEN}[✓]${NC} Terraform configuration validated"

# ===== PHASE 3: CREATE TERRAFORM VARIABLES =====
echo -e "${YELLOW}[PHASE 3]${NC} Creating Terraform variables"

cat > terraform.tfvars <<EOF
cluster_name            = "${CLUSTER_NAME}"
region                  = "${AWS_REGION}"
node_group_min_size     = ${NODE_GROUP_MIN}
node_group_max_size     = ${NODE_GROUP_MAX}
node_group_desired_size = ${NODE_GROUP_DESIRED}
node_instance_type      = "${NODE_INSTANCE_TYPE}"
node_disk_size          = ${NODE_DISK_SIZE}
enable_cluster_logging  = true
enable_vpc_cni_plugin   = true
enable_ebs_csi_driver   = true
enable_autoscaling      = true
log_retention_days      = 30
EOF

echo -e "${GREEN}[✓]${NC} terraform.tfvars created"

# ===== PHASE 4: TERRAFORM PLAN =====
echo -e "${YELLOW}[PHASE 4]${NC} Planning infrastructure"

terraform plan -out=tfplan
echo -e "${GREEN}[✓]${NC} Terraform plan created"

# ===== PHASE 5: TERRAFORM APPLY =====
echo -e "${YELLOW}[PHASE 5]${NC} Applying infrastructure (this may take 15-20 minutes)"

terraform apply tfplan
echo -e "${GREEN}[✓]${NC} EKS cluster provisioned"

# ===== PHASE 6: CONFIGURE KUBECTL =====
echo -e "${YELLOW}[PHASE 6]${NC} Configuring kubectl access"

aws eks update-kubeconfig \
  --region ${AWS_REGION} \
  --name ${CLUSTER_NAME}

echo -e "${GREEN}[✓]${NC} kubectl configured"

# ===== PHASE 7: VERIFY CLUSTER =====
echo -e "${YELLOW}[PHASE 7]${NC} Verifying cluster status"

# Wait for nodes to be ready
ATTEMPTS=0
MAX_ATTEMPTS=60
until kubectl get nodes | grep -q "Ready"; do
  if [ $ATTEMPTS -ge $MAX_ATTEMPTS ]; then
    echo -e "${RED}[ERROR]${NC} Nodes not ready after 10 minutes"
    exit 1
  fi
  ATTEMPTS=$((ATTEMPTS + 1))
  echo -e "${YELLOW}[WAIT]${NC} Waiting for nodes... ($ATTEMPTS/$MAX_ATTEMPTS)"
  sleep 10
done

NODE_COUNT=$(kubectl get nodes | tail -n +2 | wc -l)
echo -e "${GREEN}[✓]${NC} ${NODE_COUNT} nodes are Ready"

# ===== PHASE 8: INSTALL ADD-ONS =====
echo -e "${YELLOW}[PHASE 8]${NC} Installing cluster add-ons"

# VPC CNI Plugin
echo -e "${GREEN}[INFO]${NC} Installing VPC CNI plugin"
kubectl apply -f https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/master/config/master/aws-k8s-cni.yaml
sleep 30

# EBS CSI Driver
echo -e "${GREEN}[INFO]${NC} Installing EBS CSI driver"
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/ebs-csi-driver/master/deploy/kubernetes/base/rbac-controller.yaml

# CoreDNS patch
echo -e "${GREEN}[INFO]${NC} Patching CoreDNS for EKS"
kubectl patch daemonset -n kube-system aws-node -p '{"spec": {"template": {"spec": {"priorityClassName": "system-node-critical"}}}}'

echo -e "${GREEN}[✓]${NC} Add-ons installed"

# ===== PHASE 9: CREATE NAMESPACES =====
echo -e "${YELLOW}[PHASE 9]${NC} Creating namespaces"

kubectl create namespace code-server-enterprise --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace code-server-enterprise environment=${ENVIRONMENT} --overwrite
echo -e "${GREEN}[✓]${NC} code-server-enterprise namespace created"

kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
echo -e "${GREEN}[✓]${NC} monitoring namespace created"

# ===== PHASE 10: INSTALL INGRESS CONTROLLER =====
echo -e "${YELLOW}[PHASE 10]${NC} Installing NGINX Ingress Controller"

kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.0/deploy/static/provider/aws/deploy.yaml
sleep 30

# Wait for NLB
ATTEMPTS=0
MAX_ATTEMPTS=60
until kubectl get service -n ingress-nginx ingress-nginx-controller | grep -q "LoadBalancer"; do
  if [ $ATTEMPTS -ge $MAX_ATTEMPTS ]; then
    echo -e "${YELLOW}[WARN]${NC} NLB not fully provisioned, continuing..."
    break
  fi
  ATTEMPTS=$((ATTEMPTS + 1))
  sleep 10
done

NLB_ENDPOINT=$(kubectl get service -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")
echo -e "${GREEN}[✓]${NC} NGINX Ingress Controller installed (NLB: ${NLB_ENDPOINT})"

# ===== PHASE 11: INSTALL CERT-MANAGER =====
echo -e "${YELLOW}[PHASE 11]${NC} Installing cert-manager"

kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
sleep 30

# Create ClusterIssuer
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@kushnir.cloud
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
      - http01:
          ingress:
            class: nginx
EOF

echo -e "${GREEN}[✓]${NC} cert-manager installed and configured"

# ===== PHASE 12: SUMMARY =====
echo -e "${YELLOW}[SUMMARY]${NC} EKS Cluster Provisioning Complete"
echo -e "${GREEN}Cluster Name:${NC} ${CLUSTER_NAME}"
echo -e "${GREEN}Region:${NC} ${AWS_REGION}"
echo -e "${GREEN}Nodes:${NC} ${NODE_COUNT}/${NODE_GROUP_DESIRED}"
echo -e "${GREEN}Node Type:${NC} ${NODE_INSTANCE_TYPE}"
echo -e "${GREEN}NLB Endpoint:${NC} ${NLB_ENDPOINT}"

echo ""
echo -e "${GREEN}[SUCCESS]${NC} EKS cluster is ready for service deployment"
echo ""
echo "Next steps:"
echo "1. Deploy secrets: kubectl apply -f secrets/"
echo "2. Deploy services: helm install ... helm/code-server-enterprise"
echo "3. Configure DNS: Update Route53 to point to NLB endpoint"
echo "4. Monitor deployment: kubectl get pods -n code-server-enterprise -w"

cd - > /dev/null
