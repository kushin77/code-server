terraform {
  required_version = ">= 1.5.0"

  required_providers {
    ssh = {
      source  = "lorenewton/ssh"
      version = "~> 2.7"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

# SSH Provider Configuration
provider "ssh" {
  host        = var.deploy_host
  user        = var.deploy_user
  private_key = file(pathexpand(var.deploy_ssh_key_path))
  timeout     = "2m"

  # Bastion hop (if needed)
  # bastion_host       = var.bastion_host
  # bastion_user       = var.bastion_user
  # bastion_private_key = file(pathexpand(var.bastion_ssh_key_path))
}
