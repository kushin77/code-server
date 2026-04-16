# Phase 12.1: Terraform Outputs
# Exports infrastructure details for deployment and configuration

output "kubernetes_clusters" {
  description = "GKE cluster information for all regions"
  value = {
    for region, cluster in google_container_cluster.federation_clusters :
    region => {
      name               = cluster.name
      endpoint           = cluster.endpoint
      location           = cluster.location
      kubernetes_version = cluster.min_master_version
      ca_certificate     = base64decode(cluster.master_auth[0].cluster_ca_certificate)
    }
  }
  sensitive = false
}

output "kubernetes_credentials" {
  description = "Kubernetes cluster credentials"
  value = {
    for region, cluster in google_container_cluster.federation_clusters :
    region => {
      cluster_name = cluster.name
      endpoint     = cluster.endpoint
      region       = cluster.location
    }
  }
}

output "node_pools" {
  description = "Node pool information"
  value = {
    for region, pool in google_container_node_pool.federation_node_pools :
    region => {
      name         = pool.name
      node_count   = pool.node_count
      machine_type = pool.node_config[0].machine_type
    }
  }
}

output "databases" {
  description = "PostgreSQL database instances"
  value = {
    for region, db in google_sql_database_instance.federation_databases :
    region => {
      name              = db.name
      connection_name   = db.connection_name
      version           = db.database_version
      private_ip        = try(db.private_ip_address, null)
      availability_type = try(db.settings[0].availability_type, null)
    }
  }
}

output "database_credentials_secret_ids" {
  description = "Secret Manager secret IDs for database credentials"
  value = {
    replication = {
      for region, secret in google_secret_manager_secret.replication_credentials :
      region => secret.id
    }
    app = {
      for region, secret in google_secret_manager_secret.app_credentials :
      region => secret.id
    }
  }
}

output "vpc_networks" {
  description = "VPC networks for each region"
  value = {
    for region, network in google_compute_network.federation_networks :
    region => {
      name = network.name
      id   = network.id
    }
  }
}

output "subnets" {
  description = "Subnets for each region"
  value = {
    for region, subnet in google_compute_subnetwork.federation_subnets :
    region => {
      name          = subnet.name
      ip_cidr_range = subnet.ip_cidr_range
      secondary_ranges = [
        for sr in subnet.secondary_ip_range : {
          range_name    = sr.range_name
          ip_cidr_range = sr.ip_cidr_range
        }
      ]
    }
  }
}

output "federation_config" {
  description = "Complete federation configuration"
  value = {
    federation_id      = var.federation_name
    regions            = keys(google_container_cluster.federation_clusters)
    kubernetes_version = var.kubernetes_version
    total_nodes        = sum([for pool in google_container_node_pool.federation_node_pools : pool.node_count])
  }
}

output "access_commands" {
  description = "Commands to access clusters from each region"
  value = {
    for region, cluster in google_container_cluster.federation_clusters :
    region => "gcloud container clusters get-credentials ${cluster.name} --region ${cluster.location} --project ${var.gcp_project_id}"
  }
}

output "deployment_summary" {
  description = "Summary of deployed infrastructure"
  value = {
    total_regions    = length(google_container_cluster.federation_clusters)
    total_clusters   = length(google_container_cluster.federation_clusters)
    total_databases  = length(google_sql_database_instance.federation_databases)
    total_node_pools = length(google_container_node_pool.federation_node_pools)
    backend_config = {
      backend_type = "gcs"
      bucket       = "code-server-terraform-state"
      prefix       = "phase-12/infrastructure"
    }
  }
}
