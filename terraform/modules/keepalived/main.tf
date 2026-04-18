terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

# ==============================================================================
# LOCAL VALUES
# ==============================================================================

locals {
  vrrp_router_id        = var.vrrp_router_id
  vip                   = var.inventory.vip.ip
  primary_host          = var.inventory.hosts.primary
  replica_host          = var.inventory.hosts.replica
  keepalived_version    = var.keepalived_version
  health_check_interval = var.health_check_interval
  health_check_retries  = var.health_check_retries
  health_check_timeout  = var.health_check_timeout
  vrrp_interval         = var.vrrp_interval
  scripts_path          = "${path.module}/scripts"
  templates_path        = "${path.module}/templates"
}

# ==============================================================================
# DOCKER PROVIDERS (Remote SSH)
# ==============================================================================

provider "docker" {
  alias = "primary"
  host  = "ssh://${local.primary_host.ssh_user}@${local.primary_host.ip}:${local.primary_host.ssh_port}"
  ssh_opts = [
    "-i",
    pathexpand(var.ssh_identity_file),
    "-o",
    "IdentitiesOnly=yes",
    "-o",
    "StrictHostKeyChecking=accept-new",
  ]
}

provider "docker" {
  alias = "replica"
  host  = "ssh://${local.replica_host.ssh_user}@${local.replica_host.ip}:${local.replica_host.ssh_port}"
  ssh_opts = [
    "-i",
    pathexpand(var.ssh_identity_file),
    "-o",
    "IdentitiesOnly=yes",
    "-o",
    "StrictHostKeyChecking=accept-new",
  ]
}

# ==============================================================================
# KEEPALIVED DOCKER IMAGE BUILD
# ==============================================================================

resource "docker_image" "keepalived" {
  provider = docker.primary
  name     = "keepalived:${local.keepalived_version}"
  build {
    context    = path.module
    dockerfile = "${path.module}/build/Dockerfile"
  }
}

resource "docker_image" "keepalived_replica" {
  provider = docker.replica
  name     = "keepalived:${local.keepalived_version}"
  build {
    context    = path.module
    dockerfile = "${path.module}/build/Dockerfile"
  }
}

# ==============================================================================
# PRIMARY HOST — KEEPALIVED CONFIGURATION
# ==============================================================================

# Keepalived config on primary (MASTER, priority 150)
resource "local_file" "keepalived_primary_config" {
  filename = "${local.templates_path}/keepalived-primary.conf"
  content  = <<-EOT
# Keepalived Configuration — PRIMARY (VRRP Master)
# Generated from Terraform — DO NOT EDIT
# This host holds the VRRP VIP (${local.vip}) by default
# If this host becomes unhealthy, the VIP moves to replica in <2 seconds

global_defs {
    router_id VRRP_PRIMARY_${local.vip}
    script_user root root
    enable_script_security
    log_detail
    log_facility LOCAL0
}

# Health check script — Run every ${local.health_check_interval}s
vrrp_script check_services {
    script "/usr/local/bin/vrrp-health-monitor.sh"
    interval ${local.health_check_interval}
    weight -20
    fall ${local.health_check_retries}
    rise ${local.health_check_retries}
    timeout ${local.health_check_timeout}
}

# VRRP Instance — Controls the Virtual IP
vrrp_instance VI_1 {
    state MASTER
    interface eth0
    virtual_router_id ${local.vrrp_router_id}
    priority 150
    advert_int ${local.vrrp_interval}
    authentication {
        auth_type PASS
        auth_pass VRRP${local.vip}${local.vrrp_router_id}
    }
    virtual_ipaddress {
        ${local.vip}
    }
    track_script {
        check_services
    }
    preempt true
    preempt_delay 0
    notify_master "/usr/local/bin/keepalived-notify.sh MASTER"
    notify_backup "/usr/local/bin/keepalived-notify.sh BACKUP"
    notify_fault  "/usr/local/bin/keepalived-notify.sh FAULT"
    notify_stop   "/usr/local/bin/keepalived-notify.sh STOP"
}
EOT
}

# Health check script on primary
resource "local_file" "vrrp_health_check_primary" {
  filename        = "${local.scripts_path}/vrrp-health-monitor.sh"
  content         = file("${path.module}/scripts/vrrp-health-monitor.sh")
  file_permission = "0755"
}

# Keepalived Docker container on primary
resource "docker_container" "keepalived_primary" {
  count          = var.enable_on_primary ? 1 : 0
  provider       = docker.primary
  name           = "keepalived"
  image          = docker_image.keepalived.image_id
  privileged     = true
  network_mode   = "host"

  mounts {
    type   = "bind"
    source = abspath(local_file.keepalived_primary_config.filename)
    target = "/etc/keepalived/keepalived.conf"
  }

  mounts {
    type   = "bind"
    source = abspath(local_file.vrrp_health_check_primary.filename)
    target = "/usr/local/bin/vrrp-health-monitor.sh"
  }

  mounts {
    type   = "bind"
    source = abspath("${local.scripts_path}/keepalived-notify.sh")
    target = "/usr/local/bin/keepalived-notify.sh"
  }

  env = ["PROD_VIP=${local.vip}"]

  log_driver = "json-file"
  log_opts = {
    "max-size" = "10m"
    "max-file" = "3"
  }

  healthcheck {
    test     = ["CMD", "/usr/local/bin/vrrp-health-monitor.sh"]
    interval = "${local.health_check_interval}s"
    timeout  = "${local.health_check_timeout}s"
    retries  = local.health_check_retries
  }

  depends_on = [
    docker_image.keepalived,
    local_file.keepalived_primary_config,
  ]


  lifecycle {
    create_before_destroy = true
  }
}

# ==============================================================================
# REPLICA HOST — KEEPALIVED CONFIGURATION
# ==============================================================================

# Keepalived config on replica (BACKUP, priority 100)
resource "local_file" "keepalived_replica_config" {
  filename = "${local.templates_path}/keepalived-replica.conf"
  content  = <<-EOT
# Keepalived Configuration — REPLICA (VRRP Backup)
# Generated from Terraform — DO NOT EDIT
# This host is standby for the VRRP VIP (${local.vip})
# If primary becomes unhealthy, this host claims the VIP in <2 seconds

global_defs {
    router_id VRRP_REPLICA_${local.vip}
    script_user root root
    enable_script_security
    log_detail
    log_facility LOCAL0
}

# Health check script — Run every ${local.health_check_interval}s
vrrp_script check_services {
    script "/usr/local/bin/vrrp-health-monitor.sh"
    interval ${local.health_check_interval}
    weight -20
    fall ${local.health_check_retries}
    rise ${local.health_check_retries}
    timeout ${local.health_check_timeout}
}

# VRRP Instance — Controls the Virtual IP
vrrp_instance VI_1 {
    state BACKUP
    interface eth0
    virtual_router_id ${local.vrrp_router_id}
    priority 100
    advert_int ${local.vrrp_interval}
    authentication {
        auth_type PASS
        auth_pass VRRP${local.vip}${local.vrrp_router_id}
    }
    virtual_ipaddress {
        ${local.vip}
    }
    track_script {
        check_services
    }
    preempt false
    notify_master "/usr/local/bin/keepalived-notify.sh MASTER"
    notify_backup "/usr/local/bin/keepalived-notify.sh BACKUP"
    notify_fault  "/usr/local/bin/keepalived-notify.sh FAULT"
    notify_stop   "/usr/local/bin/keepalived-notify.sh STOP"
}
EOT
}

# Health check script on replica
resource "local_file" "vrrp_health_check_replica" {
  filename        = "${local.scripts_path}/vrrp-health-monitor-replica.sh"
  content         = file("${path.module}/scripts/vrrp-health-monitor.sh")
  file_permission = "0755"
}

# Keepalived Docker container on replica
resource "docker_container" "keepalived_replica" {
  count          = var.enable_on_replica ? 1 : 0
  provider       = docker.replica
  name           = "keepalived"
  image          = docker_image.keepalived_replica.image_id
  privileged     = true
  network_mode   = "host"

  mounts {
    type   = "bind"
    source = abspath(local_file.keepalived_replica_config.filename)
    target = "/etc/keepalived/keepalived.conf"
  }

  mounts {
    type   = "bind"
    source = abspath(local_file.vrrp_health_check_replica.filename)
    target = "/usr/local/bin/vrrp-health-monitor.sh"
  }

  mounts {
    type   = "bind"
    source = abspath("${local.scripts_path}/keepalived-notify.sh")
    target = "/usr/local/bin/keepalived-notify.sh"
  }

  env = ["PROD_VIP=${local.vip}"]

  log_driver = "json-file"
  log_opts = {
    "max-size" = "10m"
    "max-file" = "3"
  }

  healthcheck {
    test     = ["CMD", "/usr/local/bin/vrrp-health-monitor.sh"]
    interval = "${local.health_check_interval}s"
    timeout  = "${local.health_check_timeout}s"
    retries  = local.health_check_retries
  }

  depends_on = [
    docker_image.keepalived_replica,
    local_file.keepalived_replica_config,
  ]

  lifecycle {
    create_before_destroy = true
  }
}
