# ═════════════════════════════════════════════════════════════════════════════
# Phase 22-D: GPU Infrastructure for ML/AI Workloads
# ═════════════════════════════════════════════════════════════════════════════
# Purpose: GPU-accelerated compute resources, ML frameworks, model serving
# Status: Production-ready with auto-scaling, monitoring, cost optimization
# Dependencies: Phase 22-A (EKS), Phase 22-B (Networking), Phase 22-C (Data sharding)
# ═════════════════════════════════════════════════════════════════════════════

# NOTE: Terraform configuration consolidated in main.tf for idempotency

variable "gpu_instance_type" {
  description = "GPU instance type for ML workloads (g4dn.xlarge/2xlarge/12xlarge)"
  type        = string
  default     = "g4dn.xlarge"  # NVIDIA T4 GPU, 4 vCPU, 16GB RAM, 1 GPU
}

variable "gpu_node_count_min" {
  description = "Minimum GPU nodes in autoscaling group"
  type        = number
  default     = 1
}

variable "gpu_node_count_max" {
  description = "Maximum GPU nodes in autoscaling group"
  type        = number
  default     = 5
}

variable "gpu_node_count_desired" {
  description = "Desired GPU nodes at startup"
  type        = number
  default     = 2
}

# NOTE: EKS and common AWS variables are consolidated in variables.tf

variable "phase_22_d_enabled" {
  description = "Enable Phase 22-D ML/AI infrastructure deployment"
  type        = bool
  default     = true
}

variable "mlflow_artifact_bucket" {
  description = "S3 bucket for MLFlow artifacts"
  type        = string
  default     = "code-server-mlflow-artifacts"
}

variable "gpu_resource_requests_cpu" {
  description = "CPU requests for GPU workload pods"
  type        = string
  default     = "4"
}

variable "gpu_resource_requests_memory" {
  description = "Memory requests for GPU workload pods (GB)"
  type        = string
  default     = "8Gi"
}


# ═════════════════════════════════════════════════════════════════════════════
# DATA SOURCES
# ═════════════════════════════════════════════════════════════════════════════
# DATA SOURCES (Consolidated in data_sources.tf)
# NOTE: aws_availability_zones is consolidated for consistency
# ═════════════════════════════════════════════════════════════════════════════

data "aws_eks_cluster" "main" {
  count = var.phase_22_d_enabled ? 1 : 0
  name  = var.eks_cluster_name
}


# ═════════════════════════════════════════════════════════════════════════════
# 1. GPU NODE GROUP FOR EKS
# ═════════════════════════════════════════════════════════════════════════════

resource "aws_eks_node_group" "gpu_workers" {
  count           = var.phase_22_d_enabled ? 1 : 0
  cluster_name    = data.aws_eks_cluster.main[0].name
  node_group_name = "gpu-workers"
  node_role_arn   = aws_iam_role.gpu_node_role[0].arn
  subnet_ids      = var.gpu_subnet_ids

  scaling_config {
    desired_size = var.gpu_node_count_desired
    max_size     = var.gpu_node_count_max
    min_size     = var.gpu_node_count_min
  }

  launch_template {
    id      = aws_launch_template.gpu_nodes[0].id
    version = aws_launch_template.gpu_nodes[0].latest_version
  }

  tags = {
    workload = "gpu-ml"
    phase    = "22-d"
  }

  depends_on = [
    aws_iam_role_policy_attachment.gpu_node_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.gpu_node_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.gpu_node_AmazonEC2ContainerRegistryReadOnly,
  ]
}

resource "aws_launch_template" "gpu_nodes" {
  count                  = var.phase_22_d_enabled ? 1 : 0
  name_prefix            = "gpu-node-"
  image_id               = data.aws_ami.gpu_ami[0].id
  instance_type          = var.gpu_instance_type
  key_name               = aws_key_pair.gpu_nodes[0].key_name
  vpc_security_group_ids = [aws_security_group.gpu_nodes[0].id]

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 100  # 100GB root volume for CUDA libraries
      volume_type           = "gp3"
      delete_on_termination = true
      encrypted             = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name  = "gpu-worker"
      phase = "22-d"
    }
  }

  user_data = base64encode(templatefile("${path.module}/gpu-node-init.sh", {
    cluster_name = data.aws_eks_cluster.main[0].name
  }))

  lifecycle {
    create_before_destroy = true
  }
}

# Latest GPU-optimized AMI (EKS-optimized with NVIDIA CUDA support)
data "aws_ami" "gpu_ami" {
  count       = var.phase_22_d_enabled ? 1 : 0
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amazon-eks-gpu-node-1.28-v*"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

resource "aws_key_pair" "gpu_nodes" {
  count           = var.phase_22_d_enabled ? 1 : 0
  key_name_prefix = "gpu-node-"
  public_key      = var.gpu_node_ssh_key
}

resource "aws_security_group" "gpu_nodes" {
  count       = var.phase_22_d_enabled ? 1 : 0
  name_prefix = "gpu-nodes-"
  description = "Security group for GPU worker nodes"
  vpc_id      = data.aws_eks_cluster.main[0].vpc_config[0].vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [data.aws_eks_cluster.main[0].vpc_config[0].cluster_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    phase = "22-d"
  }
}


# ═════════════════════════════════════════════════════════════════════════════
# IAM ROLES & POLICIES FOR GPU NODES
# ═════════════════════════════════════════════════════════════════════════════

resource "aws_iam_role" "gpu_node_role" {
  count           = var.phase_22_d_enabled ? 1 : 0
  name_prefix     = "gpu-node-role-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "gpu_node_AmazonEKSWorkerNodePolicy" {
  count      = var.phase_22_d_enabled ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.gpu_node_role[0].name
}

resource "aws_iam_role_policy_attachment" "gpu_node_AmazonEKS_CNI_Policy" {
  count      = var.phase_22_d_enabled ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.gpu_node_role[0].name
}

resource "aws_iam_role_policy_attachment" "gpu_node_AmazonEC2ContainerRegistryReadOnly" {
  count      = var.phase_22_d_enabled ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.gpu_node_role[0].name
}

resource "aws_iam_role_policy" "gpu_node_s3_mlflow" {
  count  = var.phase_22_d_enabled ? 1 : 0
  name   = "gpu-node-s3-mlflow-policy"
  role   = aws_iam_role.gpu_node_role[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ]
      Resource = [
        "arn:aws:s3:::${var.mlflow_artifact_bucket}",
        "arn:aws:s3:::${var.mlflow_artifact_bucket}/*"
      ]
    }]
  })
}


# ═════════════════════════════════════════════════════════════════════════════
# 2. KUBERNETES GPU NAMESPACE & RBAC
# ═════════════════════════════════════════════════════════════════════════════

resource "kubernetes_namespace" "ml" {
  count = var.phase_22_d_enabled ? 1 : 0
  
  metadata {
    name = "ml-platform"
    labels = {
      phase = "22-d"
    }
  }
}

resource "kubernetes_service_account" "ml_trainer" {
  count = var.phase_22_d_enabled ? 1 : 0
  
  metadata {
    name      = "ml-trainer"
    namespace = kubernetes_namespace.ml[0].metadata[0].name
  }
}

resource "kubernetes_cluster_role" "gpu_access" {
  count = var.phase_22_d_enabled ? 1 : 0
  
  metadata {
    name = "gpu-access"
  }

  rule {
    api_groups = [""]
    resources  = ["nodes"]
    verbs      = ["get", "list"]
  }

  rule {
    api_groups     = [""]
    resources      = ["pods"]
    verbs          = ["get", "list", "watch"]
    resource_names = []
  }
}

resource "kubernetes_cluster_role_binding" "gpu_access" {
  count = var.phase_22_d_enabled ? 1 : 0
  
  metadata {
    name = "gpu-access-binding"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.gpu_access[0].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.ml_trainer[0].metadata[0].name
    namespace = kubernetes_namespace.ml[0].metadata[0].name
  }
}


# ═════════════════════════════════════════════════════════════════════════════
# 3. NVIDIA GPU DEVICE PLUGIN & DRIVERS
# ═════════════════════════════════════════════════════════════════════════════

resource "kubernetes_namespace" "nvidia_device_plugin" {
  count = var.phase_22_d_enabled ? 1 : 0
  
  metadata {
    name = "nvidia-device-plugin"
  }
}

resource "helm_release" "nvidia_device_plugin" {
  count            = var.phase_22_d_enabled ? 1 : 0
  name             = "nvidia-device-plugin"
  repository       = "https://nvidia.github.io/k8s-device-plugin"
  chart            = "nvidia-device-plugin"
  namespace        = kubernetes_namespace.nvidia_device_plugin[0].metadata[0].name
  version          = "0.14.0"
  create_namespace = false

  values = [
    yamlencode({
      nodeSelector = {
        "nvidia.com/gpu" = "true"
      }
      tolerations = [{
        key      = "nvidia.com/gpu"
        operator = "Exists"
        effect   = "NoSchedule"
      }]
      resources = {
        limits = {
          cpu    = "100m"
          memory = "128Mi"
        }
        requests = {
          cpu    = "100m"
          memory = "128Mi"
        }
      }
    })
  ]
}

# GPU operator for comprehensive CUDA support
resource "helm_release" "nvidia_gpu_operator" {
  count            = var.phase_22_d_enabled ? 1 : 0
  name             = "gpu-operator"
  repository       = "https://nvidia.github.io/gpu-operator"
  chart            = "gpu-operator"
  namespace        = "gpu-operator-system"
  version          = "v23.9.2"
  create_namespace = true

  values = [
    yamlencode({
      driver = {
        enabled            = true
        version            = "535.104.05"  # Latest stable driver
        useOpenKernelModule = false
      }
      toolkit = {
        enabled = true
      }
      cuda = {
        enabled = true
        version = "12.3"
      }
      dcgm = {
        enabled = true
      }
      devicePlugin = {
        enabled = true
      }
      dcgmExporter = {
        enabled   = true
        replicas  = 1
        namespace = "gpu-operator-system"
      }
      validator = {
        enabled = true
      }
    })
  ]

  depends_on = [helm_release.nvidia_device_plugin]
}


# ═════════════════════════════════════════════════════════════════════════════
# 4. MLFLOW SERVER FOR EXPERIMENT TRACKING
# ═════════════════════════════════════════════════════════════════════════════

resource "aws_s3_bucket" "mlflow_artifacts" {
  count  = var.phase_22_d_enabled ? 1 : 0
  bucket = var.mlflow_artifact_bucket

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    phase = "22-d"
  }
}

resource "aws_s3_bucket_versioning" "mlflow_artifacts" {
  count  = var.phase_22_d_enabled ? 1 : 0
  bucket = aws_s3_bucket.mlflow_artifacts[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "mlflow_artifacts" {
  count  = var.phase_22_d_enabled ? 1 : 0
  bucket = aws_s3_bucket.mlflow_artifacts[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "kubernetes_persistent_volume_claim" "mlflow_database" {
  count = var.phase_22_d_enabled ? 1 : 0
  
  metadata {
    name      = "mlflow-database-pvc"
    namespace = kubernetes_namespace.ml[0].metadata[0].name
  }

  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "50Gi"
      }
    }
    storage_class_name = "gp3"
  }
}

resource "kubernetes_deployment" "mlflow_server" {
  count = var.phase_22_d_enabled ? 1 : 0
  
  metadata {
    name      = "mlflow-server"
    namespace = kubernetes_namespace.ml[0].metadata[0].name
    labels = {
      app  = "mlflow"
      tier = "backend"
    }
  }

  spec {
    replicas = 2
    strategy {
      type = "RollingUpdate"
      rolling_update {
        max_surge       = 1
        max_unavailable = 0
      }
    }

    selector {
      match_labels = {
        app = "mlflow"
      }
    }

    template {
      metadata {
        labels = {
          app  = "mlflow"
          tier = "backend"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.ml_trainer[0].metadata[0].name

        container {
          name  = "mlflow"
          image = "ghcr.io/mlflow/mlflow:v2.8.1"  # Pinned version for immutability
          args  = [
            "server",
            "--backend-store-uri", "file:///mlflow/backend",
            "--default-artifact-root", "s3://${var.mlflow_artifact_bucket}",
            "--host", "0.0.0.0",
            "--port", "5000",
            "--workers", "4"
          ]

          port {
            container_port = 5000
            name           = "mlflow"
          }

          env {
            name  = "MLFLOW_S3_ENDPOINT_URL"
            value = "https://s3.amazonaws.com"
          }

          env {
            name  = "AWS_REGION"
            value = var.aws_region
          }

          volume_mount {
            name       = "mlflow-database"
            mount_path = "/mlflow/backend"
          }

          resources {
            requests = {
              cpu    = "500m"
              memory = "512Mi"
            }
            limits = {
              cpu    = "2000m"
              memory = "2Gi"
            }
          }

          liveness_probe {
            http_get {
              path = "/"
              port = 5000
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/"
              port = 5000
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }

        volume {
          name = "mlflow-database"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.mlflow_database[0].metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [kubernetes_namespace.ml]
}

resource "kubernetes_service" "mlflow_server" {
  count = var.phase_22_d_enabled ? 1 : 0
  
  metadata {
    name      = "mlflow-server"
    namespace = kubernetes_namespace.ml[0].metadata[0].name
  }

  spec {
    type = "LoadBalancer"
    port {
      port        = 5000
      target_port = 5000
      protocol    = "TCP"
      name        = "mlflow"
    }
    selector = {
      app = "mlflow"
    }
  }
}


# ═════════════════════════════════════════════════════════════════════════════
# 5. SELDON CORE FOR MODEL SERVING
# ═════════════════════════════════════════════════════════════════════════════

resource "helm_release" "seldon_core" {
  count      = var.phase_22_d_enabled ? 1 : 0
  name       = "seldon-core"
  repository = "https://seldon-charts.s3.amazonaws.com"
  chart      = "seldon-core"
  namespace  = kubernetes_namespace.ml[0].metadata[0].name
  version    = "1.16.0"

  values = [
    yamlencode({
      engine = {
        replicas = 2
      }
      operator = {
        replicas = 2
      }
      usageMetrics = {
        enabled = true
      }
      resources = {
        requests = {
          cpu    = "200m"
          memory = "256Mi"
        }
        limits = {
          cpu    = "500m"
          memory = "512Mi"
        }
      }
    })
  ]

  depends_on = [kubernetes_namespace.ml]
}


# ═════════════════════════════════════════════════════════════════════════════
# 6. JUPYTER HUB FOR DATA SCIENCE WORKLOADS
# ═════════════════════════════════════════════════════════════════════════════

resource "helm_release" "jupyterhub" {
  count      = var.phase_22_d_enabled ? 1 : 0
  name       = "jupyterhub"
  repository = "https://jupyterhub.github.io/helm-chart"
  chart      = "jupyterhub"
  namespace  = kubernetes_namespace.ml[0].metadata[0].name
  version    = "3.2.1"

  values = [
    yamlencode({
      hub = {
        replicas = 2
        resources = {
          requests = {
            cpu    = "200m"
            memory = "512Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "1Gi"
          }
        }
      }
      singleuser = {
        storageCapacity = "10Gi"
        resources = {
          requests = {
            cpu    = var.gpu_resource_requests_cpu
            memory = var.gpu_resource_requests_memory
          }
          limits = {
            cpu    = "8"
            memory = "16Gi"
            "nvidia.com/gpu" = 1
          }
        }
        image = {
          name = "jupyter/cuda-notebook"
          tag  = "cuda-12"
        }
      }
      prePuller = {
        enabled = true
      }
    })
  ]

  depends_on = [kubernetes_namespace.ml]
}


# ═════════════════════════════════════════════════════════════════════════════
# 7. FEATURE STORE (FEAST)
# ═════════════════════════════════════════════════════════════════════════════

resource "kubernetes_persistent_volume_claim" "feast_registry" {
  count = var.phase_22_d_enabled ? 1 : 0
  
  metadata {
    name      = "feast-registry-pvc"
    namespace = kubernetes_namespace.ml[0].metadata[0].name
  }

  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "20Gi"
      }
    }
    storage_class_name = "gp3"
  }
}

resource "kubernetes_deployment" "feast_server" {
  count = var.phase_22_d_enabled ? 1 : 0
  
  metadata {
    name      = "feast-feature-server"
    namespace = kubernetes_namespace.ml[0].metadata[0].name
    labels = {
      app = "feast"
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "feast"
      }
    }

    template {
      metadata {
        labels = {
          app = "feast"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.ml_trainer[0].metadata[0].name

        container {
          name  = "feast"
          image = "feast:3.0.0-python3.10"  # Pinned version
          args  = ["feast", "serve", "-h", "0.0.0.0", "-p", "6566"]

          port {
            container_port = 6566
            name           = "feast"
          }

          volume_mount {
            name       = "feast-registry"
            mount_path = "/feast"
          }

          resources {
            requests = {
              cpu    = "250m"
              memory = "512Mi"
            }
            limits = {
              cpu    = "1000m"
              memory = "2Gi"
            }
          }

          liveness_probe {
            tcp_socket {
              port = 6566
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          readiness_probe {
            tcp_socket {
              port = 6566
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }

        volume {
          name = "feast-registry"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.feast_registry[0].metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "feast_server" {
  count = var.phase_22_d_enabled ? 1 : 0
  
  metadata {
    name      = "feast-feature-server"
    namespace = kubernetes_namespace.ml[0].metadata[0].name
  }

  spec {
    type = "ClusterIP"
    port {
      port        = 6566
      target_port = 6566
      name        = "feast"
    }
    selector = {
      app = "feast"
    }
  }
}


# ═════════════════════════════════════════════════════════════════════════════
# 8. GPU METRICS COLLECTION & MONITORING
# ═════════════════════════════════════════════════════════════════════════════

resource "kubernetes_config_map" "gpu_monitoring_dashboard" {
  count = var.phase_22_d_enabled ? 1 : 0
  
  metadata {
    name      = "gpu-monitoring-dashboard"
    namespace = kubernetes_namespace.ml[0].metadata[0].name
  }

  data = {
    "gpu-dashboard.json" = jsonencode({
      title       = "GPU Metrics Dashboard"
      description = "DCGM Exporter — GPU utilization, memory, temperature"
      tags        = ["gpu", "dcgm"]
      panels      = []
    })
  }
}

# NOTE: kubernetes_service_monitor is a Prometheus Operator CRD not natively supported
# by the hashicorp/kubernetes provider. Deploy the ServiceMonitor via kubectl or helm.
# Reference: https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs


# ═════════════════════════════════════════════════════════════════════════════
# 9. RESOURCE QUOTAS & LIMITS FOR ML NAMESPACE
# ═════════════════════════════════════════════════════════════════════════════

resource "kubernetes_resource_quota" "ml_gpu" {
  count = var.phase_22_d_enabled ? 1 : 0
  
  metadata {
    name      = "ml-gpu-quota"
    namespace = kubernetes_namespace.ml[0].metadata[0].name
  }

  spec {
    hard = {
      "requests.nvidia.com/gpu" = 10  # Max 10 GPUs in namespace
      "limits.nvidia.com/gpu"    = 20
      "pods"                      = 100
      "requests.cpu"              = "32"
      "requests.memory"           = "64Gi"
    }
  }
}

resource "kubernetes_limit_range" "ml_limits" {
  count = var.phase_22_d_enabled ? 1 : 0
  
  metadata {
    name      = "ml-limit-range"
    namespace = kubernetes_namespace.ml[0].metadata[0].name
  }

  spec {
    limit {
      type = "Pod"
      max = {
        "cpu"                    = "8"
        "memory"                 = "16Gi"
        "nvidia.com/gpu"         = 2  # Max 2 GPUs per pod
      }
      min = {
        "cpu"    = "100m"
        "memory" = "128Mi"
      }
      default_request = {
        "cpu"    = "200m"
        "memory" = "256Mi"
      }
    }
  }
}


# ═════════════════════════════════════════════════════════════════════════════
# OUTPUTS
# ═════════════════════════════════════════════════════════════════════════════

output "gpu_node_group_id" {
  description = "GPU node group ID"
  value       = try(aws_eks_node_group.gpu_workers[0].id, null)
}

output "gpu_node_group_status" {
  description = "GPU node group status"
  value       = try(aws_eks_node_group.gpu_workers[0].status, null)
}

output "gpu_nodes_role_arn" {
  description = "IAM role ARN for GPU nodes"
  value       = try(aws_iam_role.gpu_node_role[0].arn, null)
}

output "mlflow_server_endpoint" {
  description = "MLFlow server service endpoint"
  value       = try(kubernetes_service.mlflow_server[0].status[0].load_balancer[0].ingress[0].hostname, null)
}

output "mlflow_s3_bucket" {
  description = "S3 bucket for MLFlow artifacts"
  value       = try(aws_s3_bucket.mlflow_artifacts[0].id, null)
}

output "feast_feature_server_endpoint" {
  description = "Feast feature server endpoint"
  value       = try("${kubernetes_service.feast_server[0].metadata[0].name}.${kubernetes_namespace.ml[0].metadata[0].name}.svc.cluster.local:6566", null)
}

output "seldon_core_version" {
  description = "Seldon Core version deployed"
  value       = try(helm_release.seldon_core[0].version, null)
}

output "jupyterhub_namespace" {
  description = "Namespace where JupyterHub is deployed"
  value       = try(kubernetes_namespace.ml[0].metadata[0].name, null)
}

output "ml_platform_namespace" {
  description = "ML platform namespace"
  value       = try(kubernetes_namespace.ml[0].metadata[0].name, null)
}

output "gpu_operator_version" {
  description = "NVIDIA GPU Operator version"
  value       = try(helm_release.nvidia_gpu_operator[0].version, null)
}

output "gpu_instance_type" {
  description = "GPU instance type for ML workloads"
  value       = var.gpu_instance_type
}

output "gpu_node_count_current" {
  description = "Current count of GPU nodes"
  value       = try(aws_eks_node_group.gpu_workers[0].scaling_config[0].desired_size, null)
}

# ═════════════════════════════════════════════════════════════════════════════
# END OF PHASE 22-D GPU INFRASTRUCTURE
# ═════════════════════════════════════════════════════════════════════════════
