/**
 * @file modules/stack/networks.tf
 * @description Docker networks for this host (matches docker-compose.yml network definitions).
 *              Each host gets its own independent set of networks.
 */

resource "docker_network" "ingress" {
  name   = "ingress"
  driver = "bridge"
  options = {
    "com.docker.network.bridge.name" = "br-ingress"
  }
}

resource "docker_network" "services" {
  name   = "services"
  driver = "bridge"
  options = {
    "com.docker.network.bridge.name" = "br-services"
  }
}

resource "docker_network" "database" {
  name   = "database"
  driver = "bridge"
  options = {
    "com.docker.network.bridge.name" = "br-database"
  }
}
