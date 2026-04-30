/**
 * @file providers.tf
 * @description Docker provider aliases for primary and replica hosts.
 *              Both connect via SSH to the remote Docker daemon — no local Docker socket needed.
 *
 * Usage:
 *   terraform init
 *   terraform plan    ← shows all 80 container diffs across both hosts
 *   terraform apply   ← creates/updates/destroys containers declaratively
 *
 * Requirements:
 *   - SSH agent or key forwarding for akushnir@<host>
 *   - akushnir must be in the 'docker' group on each host
 */

provider "docker" {
  alias    = "primary"
  host     = "ssh://${var.ssh_user}@${var.primary_host}:${var.ssh_port}"
  ssh_opts = [
    "-o", "StrictHostKeyChecking=accept-new",
    "-o", "BatchMode=yes",
    "-o", "ConnectTimeout=30",
    "-o", "ServerAliveInterval=15",
    "-o", "ServerAliveCountMax=4",
  ]
}

provider "docker" {
  alias    = "replica"
  host     = "ssh://${var.ssh_user}@${var.replica_host}:${var.ssh_port}"
  ssh_opts = [
    "-o", "StrictHostKeyChecking=accept-new",
    "-o", "BatchMode=yes",
    "-o", "ConnectTimeout=30",
    "-o", "ServerAliveInterval=15",
    "-o", "ServerAliveCountMax=4",
  ]
}

provider "local" {}

provider "null" {}
