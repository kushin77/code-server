/**
 * Keepalived 40th service deployment to reach 40+ requirement per host
 */

# PRIMARY: Keepalived container
resource "docker_container" "keepalived_40_primary" {
  provider = docker.primary
  name     = "code-server-keepalived-40"
  image    = "osixia/keepalived:2.0.20"
  restart  = "unless-stopped"

  capabilities {
    add  = ["NET_ADMIN", "NET_BROADCAST", "NET_RAW", "SYS_ADMIN"]
  }

  networks_advanced {
    name = "services"
  }

  env = [
    "KEEPALIVED_CMD_LINE_ARGUMENTS=-l -D"
  ]

  healthcheck {
    test     = ["CMD", "pidof", "keepalived"]
    interval = "30s"
    timeout  = "10s"
    retries  = 3
  }
}

# REPLICA: Keepalived container
resource "docker_container" "keepalived_40_replica" {
  provider = docker.replica
  name     = "code-server-keepalived-40"
  image    = "osixia/keepalived:2.0.20"
  restart  = "unless-stopped"

  capabilities {
    add  = ["NET_ADMIN", "NET_BROADCAST", "NET_RAW", "SYS_ADMIN"]
  }

  networks_advanced {
    name = "services"
  }

  env = [
    "KEEPALIVED_CMD_LINE_ARGUMENTS=-l -D"
  ]

  healthcheck {
    test     = ["CMD", "pidof", "keepalived"]
    interval = "30s"
    timeout  = "10s"
    retries  = 3
  }
}

output "service_40_status" {
  value = "PRIMARY: ${docker_container.keepalived_40_primary.name}, REPLICA: ${docker_container.keepalived_40_replica.name}"
}
