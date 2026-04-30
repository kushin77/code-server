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
    "-o", "ControlMaster=auto",
    "-o", "ControlPath=/tmp/docker-ssh-primary-%r-%h-%p",
    "-o", "ControlPersist=60s",
    "-o", "StrictHostKeyChecking=accept-new",  # Accept new hosts once; fail on key mismatch
    "-o", "BatchMode=yes",
  ]
}

provider "docker" {
  alias    = "replica"
  host     = "ssh://${var.ssh_user}@${var.replica_host}:${var.ssh_port}"
  ssh_opts = [
    "-o", "ControlMaster=auto",
    "-o", "ControlPath=/tmp/docker-ssh-replica-%r-%h-%p",
    "-o", "ControlPersist=60s",
    "-o", "StrictHostKeyChecking=accept-new",  # Accept new hosts once; fail on key mismatch
    "-o", "BatchMode=yes",
  ]
}

provider "local" {}

provider "null" {}
