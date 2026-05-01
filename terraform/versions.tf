terraform {
  required_version = ">= 1.6.0, < 1.15.0"

  # Pinned provider versions for reproducibility and security
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "= 3.0.2"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "= 2.23.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "= 3.2.1"
    }
    local = {
      source  = "hashicorp/local"
      version = "= 2.4.0"
    }
  }
}

# Provider configurations
provider "docker" {
  host = "unix:///var/run/docker.sock"
}

provider "kubernetes" {
  config_path = var.kubeconfig_path
}

provider "local" {
  # No configuration needed
}