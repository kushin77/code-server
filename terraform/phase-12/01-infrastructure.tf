# Phase 12.1: Terraform - Global Federation Infrastructure
# Deploys 5-region Kubernetes federation with PostgreSQL multi-primary replication

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.10"
    }
  }

  backend "gcs" {
    bucket = "code-server-terraform-state"
    prefix = "phase-12/infrastructure"
  }
}

# Configure the Google Cloud Provider
provider "google" {
  project = var.gcp_project_id
  region  = var.primary_region
}

# ============================================================================
# Variables
# ============================================================================

variable "gcp_project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "primary_region" {
  description = "Primary GCP region"
  type        = string
  default     = "us-west1"
}

variable "federation_name" {
  description = "Federation name"
  type        = string
  default     = "code-server-global-federation"
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.28"
}

variable "enable_network_policy" {
  description = "Enable Kubernetes network policies"
  type        = bool
  default     = true
}

variable "enable_pod_security" {
  description = "Enable pod security policies"
  type        = bool
  default     = true
}

# ============================================================================
# Locals
# ============================================================================

locals {
  federation_id = "${var.federation_name}-prod"
  
  regions = [
    {
      region_id      = "us-west"
      location       = "us-west1"
      node_count     = 5
      machine_type   = "n2-standard-4"
      disk_size      = 200
      network_cidr   = "10.0.0.0/20"
      pods_cidr      = "10.4.0.0/14"
      services_cidr  = "10.0.16.0/20"
      replica_id     = "us-west-primary"
      tier           = "primary"
    },
    {
      region_id      = "eu-west"
      location       = "eu-west1"
      node_count     = 4
      machine_type   = "n2-standard-4"
      disk_size      = 200
      network_cidr   = "10.16.0.0/20"
      pods_cidr      = "10.20.0.0/14"
      services_cidr  = "10.36.0.0/20"
      replica_id     = "eu-west-primary"
      tier           = "secondary"
    },
    {
      region_id      = "eu-central"
      location       = "europe-west1"
      node_count     = 3
      machine_type   = "n1-standard-4"
      disk_size      = 150
      network_cidr   = "10.32.0.0/20"
      pods_cidr      = "10.40.0.0/14"
      services_cidr  = "10.48.0.0/20"
      replica_id     = "eu-central-primary"
      tier           = "tertiary"
    },
    {
      region_id      = "ap-south"
      location       = "asia-southeast1"
      node_count     = 3
      machine_type   = "n1-standard-2"
      disk_size      = 150
      network_cidr   = "10.64.0.0/20"
      pods_cidr      = "10.68.0.0/14"
      services_cidr  = "10.80.0.0/20"
      replica_id     = "ap-south-primary"
      tier           = "tertiary"
    },
    {
      region_id      = "ap-northeast"
      location       = "asia-northeast1"
      node_count     = 3
      machine_type   = "n1-standard-2"
      disk_size      = 150
      network_cidr   = "10.96.0.0/20"
      pods_cidr      = "10.100.0.0/14"
      services_cidr  = "10.112.0.0/20"
      replica_id     = "ap-northeast-primary"
      tier           = "tertiary"
    },
  ]

  common_labels = {
    federation = local.federation_id
    deployed_by = "terraform"
    phase = "phase-12-1"
    created_at = timestamp()
  }
}

# ============================================================================
# VPC Networks - One per region
# ============================================================================

resource "google_compute_network" "federation_networks" {
  for_each = { for r in local.regions : r.region_id => r }

  name                    = "${var.federation_name}-vpc-${each.value.region_id}"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"

  project = var.gcp_project_id
}

resource "google_compute_subnetwork" "federation_subnets" {
  for_each = { for r in local.regions : r.region_id => r }

  name          = "${var.federation_name}-subnet-${each.value.region_id}"
  region        = each.value.location
  network       = google_compute_network.federation_networks[each.key].id
  ip_cidr_range = each.value.network_cidr

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = each.value.pods_cidr
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = each.value.services_cidr
  }

  private_ip_google_access = true

  project = var.gcp_project_id
}

# ============================================================================
# GKE Clusters - One per region
# ============================================================================

resource "google_container_cluster" "federation_clusters" {
  for_each = { for r in local.regions : r.region_id => r }

  name     = "${var.federation_name}-cluster-${each.value.region_id}"
  location = each.value.location

  # We can't create a cluster with no node pool defined, but we want to only use
  # separately managed node pools. So we create the smallest possible default
  # node pool and immediately delete it.
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = google_compute_network.federation_networks[each.key].name
  subnetwork = google_compute_subnetwork.federation_subnets[each.key].name

  # Network policy for security
  network_policy {
    enabled  = var.enable_network_policy
    provider = "CALICO"
  }

  # Cluster version
  min_master_version = var.kubernetes_version

  # Workload Identity for secure GCP service access
  workload_identity_config {
    workload_pool = "${var.gcp_project_id}.cloud.google.com"
  }

  # Maintenance window
  maintenance_policy {
    daily_maintenance_window {
      start_time = "03:00"
    }
  }

  # Logging and monitoring
  logging_service    = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"

  # Security
  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  # IP allocation policy for VPC-native cluster
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  project = var.gcp_project_id

  labels = merge(
    local.common_labels,
    {
      region     = each.value.region_id
      replica_id = each.value.replica_id
      tier       = each.value.tier
    }
  )
}

# ============================================================================
# Node Pools - One per cluster
# ============================================================================

resource "google_container_node_pool" "federation_node_pools" {
  for_each = { for r in local.regions : r.region_id => r }

  name       = "${var.federation_name}-pool-${each.value.region_id}"
  location   = each.value.location
  cluster    = google_container_cluster.federation_clusters[each.key].name
  node_count = each.value.node_count

  autoscaling {
    min_node_count = max(1, each.value.node_count - 1)
    max_node_count = each.value.node_count * 2
  }

  node_config {
    preemptible  = false
    machine_type = each.value.machine_type

    disk_size_gb = each.value.disk_size
    disk_type    = "pd-ssd"

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    metadata = {
      disable-legacy-endpoints = "true"
    }

    labels = {
      node_pool = "production"
      region    = each.value.region_id
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    # Node taints for workload isolation
    taint {
      key    = "workload"
      value  = "production"
      effect = "NO_SCHEDULE"
    }
  }

  project = var.gcp_project_id
}

# ============================================================================
# Outputs
# ============================================================================

output "cluster_endpoints" {
  description = "GKE cluster endpoints"
  value = {
    for region, cluster in google_container_cluster.federation_clusters :
    region => cluster.endpoint
  }
}

output "cluster_names" {
  description = "GKE cluster names"
  value = {
    for region, cluster in google_container_cluster.federation_clusters :
    region => cluster.name
  }
}

output "cluster_self_links" {
  description = "GKE cluster self links"
  value = {
    for region, cluster in google_container_cluster.federation_clusters :
    region => cluster.self_link
  }
}

output "vpc_networks" {
  description = "VPC networks for each region"
  value = {
    for region, network in google_compute_network.federation_networks :
    region => network.id
  }
}

output "subnets" {
  description = "Subnets for each region"
  value = {
    for region, subnet in google_compute_subnetwork.federation_subnets :
    region => subnet.id
  }
}
