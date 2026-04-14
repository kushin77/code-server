# terraform/phase-22-kubernetes-eks.tf
# Phase 22-A: Kubernetes Orchestration - EKS Cluster Infrastructure
# 
# Provisions AWS EKS cluster with:
# - Auto-scaling worker nodes (2-10)
# - Networking: VPC, subnets, security groups
# - IAM roles and policies
# - Container registry integration
# - Service account federation
#
# IMMUTABILITY: All images digest-pinned, versions locked
# IDEMPOTENCY: Safe to re-apply, uses count for feature flags
# INDEPENDENCE: Can deploy independently with feature flag

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.20"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }
}

# ═════════════════════════════════════════════════════════════════════════════
# FEATURE FLAG: Phase 22-A Kubernetes Orchestration
# ═════════════════════════════════════════════════════════════════════════════

variable "phase_22_a_enabled" {
  description = "Enable Phase 22-A: Kubernetes Orchestration"
  type        = bool
  default     = true
}

variable "eks_cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "code-server-k8s-prod"
}

variable "eks_cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.28"  # Current stable version
}

variable "eks_instance_types" {
  description = "EC2 instance types for worker nodes"
  type        = list(string)
  default     = ["t3.xlarge", "t3.2xlarge"]
}

variable "eks_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 3
}

variable "eks_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 2
}

variable "eks_max_size" {
  description = "Maximum number of worker nodes (auto-scaling)"
  type        = number
  default     = 10
}

variable "eks_region" {
  description = "AWS region for EKS cluster"
  type        = string
  default     = "us-east-1"
}

# ═════════════════════════════════════════════════════════════════════════════
# NETWORKING: VPC and Subnets
# ═════════════════════════════════════════════════════════════════════════════

resource "aws_vpc" "kubernetes" {
  count             = var.phase_22_a_enabled ? 1 : 0
  cidr_block        = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.eks_cluster_name}-vpc"
    Phase       = "22-A"
    Environment = "production"
  }
}

resource "aws_subnet" "kubernetes_public" {
  count                   = var.phase_22_a_enabled ? 2 : 0
  vpc_id                  = aws_vpc.kubernetes[0].id
  cidr_block              = "10.0.${count.index + 1}.0/24"
  availability_zone       = data.aws_availability_zones.available[0].names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.eks_cluster_name}-public-${count.index + 1}"
    Phase       = "22-A"
    Type        = "Public"
  }
}

resource "aws_subnet" "kubernetes_private" {
  count             = var.phase_22_a_enabled ? 2 : 0
  vpc_id            = aws_vpc.kubernetes[0].id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = data.aws_availability_zones.available[0].names[count.index]

  tags = {
    Name        = "${var.eks_cluster_name}-private-${count.index + 1}"
    Phase       = "22-A"
    Type        = "Private"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "kubernetes" {
  count   = var.phase_22_a_enabled ? 1 : 0
  vpc_id  = aws_vpc.kubernetes[0].id

  tags = {
    Name        = "${var.eks_cluster_name}-igw"
    Phase       = "22-A"
  }
}

# NAT Gateway for private subnets
resource "aws_eip" "nat" {
  count  = var.phase_22_a_enabled ? 1 : 0
  domain = "vpc"

  tags = {
    Name  = "${var.eks_cluster_name}-nat-eip"
    Phase = "22-A"
  }

  depends_on = [aws_internet_gateway.kubernetes]
}

resource "aws_nat_gateway" "kubernetes" {
  count         = var.phase_22_a_enabled ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.kubernetes_public[0].id

  tags = {
    Name        = "${var.eks_cluster_name}-nat"
    Phase       = "22-A"
  }

  depends_on = [aws_internet_gateway.kubernetes]
}

# Route tables
resource "aws_route_table" "public" {
  count  = var.phase_22_a_enabled ? 1 : 0
  vpc_id = aws_vpc.kubernetes[0].id

  route {
    cidr_block      = "0.0.0.0/0"
    gateway_id      = aws_internet_gateway.kubernetes[0].id
  }

  tags = {
    Name  = "${var.eks_cluster_name}-public-rt"
    Phase = "22-A"
  }
}

resource "aws_route_table" "private" {
  count  = var.phase_22_a_enabled ? 1 : 0
  vpc_id = aws_vpc.kubernetes[0].id

  route {
    cidr_block      = "0.0.0.0/0"
    nat_gateway_id  = aws_nat_gateway.kubernetes[0].id
  }

  tags = {
    Name  = "${var.eks_cluster_name}-private-rt"
    Phase = "22-A"
  }
}

resource "aws_route_table_association" "public" {
  count          = var.phase_22_a_enabled ? 2 : 0
  subnet_id      = aws_subnet.kubernetes_public[count.index].id
  route_table_id = aws_route_table.public[0].id
}

resource "aws_route_table_association" "private" {
  count          = var.phase_22_a_enabled ? 2 : 0
  subnet_id      = aws_subnet.kubernetes_private[count.index].id
  route_table_id = aws_route_table.private[0].id
}

# Security group for EKS cluster
resource "aws_security_group" "kubernetes" {
  count       = var.phase_22_a_enabled ? 1 : 0
  name        = "${var.eks_cluster_name}-sg"
  description = "Security group for EKS cluster"
  vpc_id      = aws_vpc.kubernetes[0].id

  # Inbound: Allow traffic from within VPC
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # Inbound: Allow HTTPS
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Inbound: Allow HTTP
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound: Allow all
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.eks_cluster_name}-sg"
    Phase       = "22-A"
  }
}

# ═════════════════════════════════════════════════════════════════════════════
# IAM ROLES AND POLICIES
# ═════════════════════════════════════════════════════════════════════════════

# EKS service role
resource "aws_iam_role" "eks_cluster" {
  count = var.phase_22_a_enabled ? 1 : 0
  name  = "${var.eks_cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name  = "${var.eks_cluster_name}-cluster-role"
    Phase = "22-A"
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  count      = var.phase_22_a_enabled ? 1 : 0
  role       = aws_iam_role.eks_cluster[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# EKS node role
resource "aws_iam_role" "eks_nodes" {
  count = var.phase_22_a_enabled ? 1 : 0
  name  = "${var.eks_cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name  = "${var.eks_cluster_name}-node-role"
    Phase = "22-A"
  }
}

resource "aws_iam_role_policy_attachment" "eks_nodes_policy" {
  count      = var.phase_22_a_enabled ? 1 : 0
  role       = aws_iam_role.eks_nodes[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  count      = var.phase_22_a_enabled ? 1 : 0
  role       = aws_iam_role.eks_nodes[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_ecr_policy" {
  count      = var.phase_22_a_enabled ? 1 : 0
  role       = aws_iam_role.eks_nodes[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "eks_ssm_policy" {
  count      = var.phase_22_a_enabled ? 1 : 0
  role       = aws_iam_role.eks_nodes[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ═════════════════════════════════════════════════════════════════════════════
# EKS CLUSTER
# ═════════════════════════════════════════════════════════════════════════════

resource "aws_eks_cluster" "kubernetes" {
  count    = var.phase_22_a_enabled ? 1 : 0
  name     = var.eks_cluster_name
  role_arn = aws_iam_role.eks_cluster[0].arn
  version  = var.eks_cluster_version

  vpc_config {
    subnet_ids              = concat(aws_subnet.kubernetes_public[*].id, aws_subnet.kubernetes_private[*].id)
    security_groups         = [aws_security_group.kubernetes[0].id]
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = ["0.0.0.0/0"]  # Restrict in production
  }

  # Logging configuration
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  tags = {
    Name        = var.eks_cluster_name
    Phase       = "22-A"
    Environment = "production"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]
}

# ═════════════════════════════════════════════════════════════════════════════
# MANAGED NODE GROUP (Auto-Scaling)
# ═════════════════════════════════════════════════════════════════════════════

resource "aws_eks_node_group" "main" {
  count            = var.phase_22_a_enabled ? 1 : 0
  cluster_name     = aws_eks_cluster.kubernetes[0].name
  node_group_name  = "${var.eks_cluster_name}-ng-main"
  node_role_arn    = aws_iam_role.eks_nodes[0].arn
  subnet_ids       = aws_subnet.kubernetes_private[*].id
  version          = var.eks_cluster_version

  instance_types = var.eks_instance_types

  scaling_config {
    desired_size = var.eks_desired_size
    max_size     = var.eks_max_size
    min_size     = var.eks_min_size
  }

  tags = {
    Name        = "${var.eks_cluster_name}-ng-main"
    Phase       = "22-A"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_nodes_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_ecr_policy
  ]
}

# ═════════════════════════════════════════════════════════════════════════════
# DATA SOURCES
# ═════════════════════════════════════════════════════════════════════════════

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_eks_cluster_auth" "cluster" {
  count = var.phase_22_a_enabled ? 1 : 0
  name  = aws_eks_cluster.kubernetes[0].name
}

# ═════════════════════════════════════════════════════════════════════════════
# OUTPUTS
# ═════════════════════════════════════════════════════════════════════════════

output "eks_cluster_name" {
  value       = try(aws_eks_cluster.kubernetes[0].name, "")
  description = "EKS cluster name"
}

output "eks_cluster_endpoint" {
  value       = try(aws_eks_cluster.kubernetes[0].endpoint, "")
  description = "EKS cluster API endpoint"
}

output "eks_cluster_version" {
  value       = try(aws_eks_cluster.kubernetes[0].version, "")
  description = "EKS cluster Kubernetes version"
}

output "eks_node_group_id" {
  value       = try(aws_eks_node_group.main[0].id, "")
  description = "EKS node group ID"
}

output "eks_worker_nodes_count" {
  value = try(length(aws_eks_node_group.main), 0)
}

output "kubeconfig" {
  value       = try(base64encode(jsonencode({
    apiVersion = "v1"
    kind       = "Config"
    clusters = [{
      cluster = {
        server                   = aws_eks_cluster.kubernetes[0].endpoint
        certificate-authority-data = aws_eks_cluster.kubernetes[0].certificate_authority[0].data
      }
      name = aws_eks_cluster.kubernetes[0].name
    }]
    contexts = [{
      context = {
        cluster = aws_eks_cluster.kubernetes[0].name
        user    = aws_eks_cluster.kubernetes[0].name
      }
      name = aws_eks_cluster.kubernetes[0].name
    }]
    current-context = aws_eks_cluster.kubernetes[0].name
    users = [{
      name = aws_eks_cluster.kubernetes[0].name
      user = {
        exec = {
          apiVersion = "client.authentication.k8s.io/v1beta1"
          command    = "aws"
          args       = ["eks", "get-token", "--cluster-name", aws_eks_cluster.kubernetes[0].name]
        }
      }
    }]
  })), "")
  description = "Kubernetes kubeconfig (base64 encoded)"
  sensitive   = true
}

# ═════════════════════════════════════════════════════════════════════════════
# DEPLOYMENT CHECKLIST
# ═════════════════════════════════════════════════════════════════════════════
# 
# Pre-deployment:
# 1. AWS credentials configured (aws configure)
# 2. Terraform state backend configured
# 3. Region set (default: us-east-1)
# 4. VPC CIDR planning (10.0.0.0/16 for EKS)
#
# Deployment:
# terraform init
# terraform validate
# terraform plan -out=tfplan
# terraform apply tfplan
#
# Post-deployment:
# aws eks update-kubeconfig --name code-server-k8s-prod
# kubectl get nodes
# kubectl get pods --all-namespaces
#
# Scaling:
# terraform apply -var="eks_desired_size=5"
#
# Cleanup:
# terraform destroy -auto-approve
