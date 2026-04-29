/**
 * @file modules/stack/containers-init.tf
 * @description Init containers — run once at volume creation to set ownership/permissions.
 *              must_run = false: Terraform creates them but does not try to keep them running.
 *              lifecycle ignore_changes: after first create, Terraform ignores state changes.
 */

resource "docker_container" "grafana_init" {
  name         = "code-server-grafana-init"
  image        = docker_image.alpine.image_id
  user         = "0:0"
  must_run     = false
  restart      = "no"
  command      = ["sh", "-lc", "mkdir -p /var/lib/grafana; owner=$(stat -c '%u:%g' /var/lib/grafana 2>/dev/null || true); [ \"$owner\" = '472:472' ] || chown -R 472:472 /var/lib/grafana"]
  network_mode = "bridge"

  networks_advanced {
    name = docker_network.services.id
  }

  mounts {
    target = "/var/lib/grafana"
    source = docker_volume.grafana_data.name
    type   = "volume"
  }

  lifecycle {
    ignore_changes = [command, image]
  }
}

resource "docker_container" "redis_init" {
  name         = "code-server-redis-init"
  image        = docker_image.alpine.image_id
  user         = "0:0"
  must_run     = false
  restart      = "no"
  command      = ["sh", "-lc", "mkdir -p /data; owner=$(stat -c '%u:%g' /data 2>/dev/null || true); [ \"$owner\" = '999:999' ] || chown -R 999:999 /data"]
  network_mode = "bridge"

  networks_advanced {
    name = docker_network.services.id
  }

  mounts {
    target = "/data"
    source = docker_volume.redis_data.name
    type   = "volume"
  }

  lifecycle {
    ignore_changes = [command, image]
  }
}

resource "docker_container" "redpanda_init" {
  name         = "code-server-redpanda-init"
  image        = docker_image.alpine.image_id
  user         = "0:0"
  must_run     = false
  restart      = "no"
  command      = ["sh", "-lc", "mkdir -p /var/lib/redpanda/data; owner=$(stat -c '%u:%g' /var/lib/redpanda/data 2>/dev/null || true); [ \"$owner\" = '101:101' ] || chown -R 101:101 /var/lib/redpanda/data"]
  network_mode = "bridge"

  networks_advanced {
    name = docker_network.services.id
  }

  mounts {
    target = "/var/lib/redpanda/data"
    source = docker_volume.redpanda_data.name
    type   = "volume"
  }

  lifecycle {
    ignore_changes = [command, image]
  }
}

resource "docker_container" "prometheus_init" {
  name         = "code-server-prometheus-init"
  image        = docker_image.alpine.image_id
  user         = "0:0"
  must_run     = false
  restart      = "no"
  command      = ["sh", "-lc", "mkdir -p /prometheus; owner=$(stat -c '%u:%g' /prometheus 2>/dev/null || true); [ \"$owner\" = '65534:65534' ] || chown -R 65534:65534 /prometheus"]
  network_mode = "bridge"

  networks_advanced {
    name = docker_network.services.id
  }

  mounts {
    target = "/prometheus"
    source = docker_volume.prometheus_data.name
    type   = "volume"
  }

  lifecycle {
    ignore_changes = [command, image]
  }
}

resource "docker_container" "loki_init" {
  name         = "code-server-loki-init"
  image        = docker_image.alpine.image_id
  user         = "0:0"
  must_run     = false
  restart      = "no"
  command      = ["sh", "-lc", "mkdir -p /loki; owner=$(stat -c '%u:%g' /loki 2>/dev/null || true); [ \"$owner\" = '10001:10001' ] || chown -R 10001:10001 /loki"]
  network_mode = "bridge"

  networks_advanced {
    name = docker_network.services.id
  }

  mounts {
    target = "/loki"
    source = docker_volume.loki_data.name
    type   = "volume"
  }

  lifecycle {
    ignore_changes = [command, image]
  }
}

resource "docker_container" "alertmanager_init" {
  name         = "code-server-alertmanager-init"
  image        = docker_image.alpine.image_id
  user         = "0:0"
  must_run     = false
  restart      = "no"
  command      = ["sh", "-lc", "mkdir -p /alertmanager; owner=$(stat -c '%u:%g' /alertmanager 2>/dev/null || true); [ \"$owner\" = '65534:65534' ] || chown -R 65534:65534 /alertmanager"]
  network_mode = "bridge"

  networks_advanced {
    name = docker_network.services.id
  }

  mounts {
    target = "/alertmanager"
    source = docker_volume.alertmanager_data.name
    type   = "volume"
  }

  lifecycle {
    ignore_changes = [command, image]
  }
}

resource "docker_container" "caddy_init" {
  name         = "code-server-caddy-init"
  image        = docker_image.alpine.image_id
  user         = "0:0"
  must_run     = false
  restart      = "no"
  command      = ["sh", "-lc", "mkdir -p /data /config; chown -R 101:101 /data /config"]
  network_mode = "bridge"

  networks_advanced {
    name = docker_network.services.id
  }

  mounts {
    target = "/data"
    source = docker_volume.caddy_data.name
    type   = "volume"
  }

  mounts {
    target = "/config"
    source = docker_volume.caddy_config.name
    type   = "volume"
  }

  lifecycle {
    ignore_changes = [command, image]
  }
}

resource "docker_container" "qdrant_init" {
  name         = "code-server-qdrant-init"
  image        = docker_image.alpine.image_id
  user         = "0:0"
  must_run     = false
  restart      = "no"
  command      = ["sh", "-lc", "mkdir -p /qdrant/storage; owner=$(stat -c '%u:%g' /qdrant/storage 2>/dev/null || true); [ \"$owner\" = '1000:1000' ] || chown -R 1000:1000 /qdrant/storage"]
  network_mode = "bridge"

  networks_advanced {
    name = docker_network.services.id
  }

  mounts {
    target = "/qdrant/storage"
    source = docker_volume.qdrant_data.name
    type   = "volume"
  }

  lifecycle {
    ignore_changes = [command, image]
  }
}

resource "docker_container" "postgres_init" {
  name         = "code-server-postgres-init"
  image        = docker_image.alpine.image_id
  user         = "0:0"
  must_run     = false
  restart      = "no"
  command      = ["sh", "-lc", "mkdir -p /var/lib/postgresql/data; owner=$(stat -c '%u:%g' /var/lib/postgresql/data 2>/dev/null || true); [ \"$owner\" = '999:999' ] || chown -R 999:999 /var/lib/postgresql/data"]
  network_mode = "bridge"

  networks_advanced {
    name = docker_network.services.id
  }

  networks_advanced {
    name = docker_network.database.id
  }

  mounts {
    target = "/var/lib/postgresql/data"
    source = docker_volume.postgres_data.name
    type   = "volume"
  }

  lifecycle {
    ignore_changes = [command, image]
  }
}

resource "docker_container" "ollama_init" {
  name         = "code-server-ollama-init"
  image        = docker_image.alpine.image_id
  user         = "0:0"
  must_run     = false
  restart      = "no"
  command      = ["sh", "-lc", "mkdir -p /home/ollama/.ollama; owner=$(stat -c '%u:%g' /home/ollama/.ollama 2>/dev/null || true); [ \"$owner\" = '11434:11434' ] || chown -R 11434:11434 /home/ollama/.ollama"]
  network_mode = "bridge"

  networks_advanced {
    name = docker_network.services.id
  }

  mounts {
    target = "/home/ollama/.ollama"
    source = docker_volume.ollama_models.name
    type   = "volume"
  }

  lifecycle {
    ignore_changes = [command, image]
  }
}

resource "docker_container" "tempo_init" {
  name         = "code-server-tempo-init"
  image        = docker_image.alpine.image_id
  user         = "0:0"
  must_run     = false
  restart      = "no"
  command      = ["sh", "-lc", "mkdir -p /var/tempo; owner=$(stat -c '%u:%g' /var/tempo 2>/dev/null || true); [ \"$owner\" = '10001:10001' ] || chown -R 10001:10001 /var/tempo"]
  network_mode = "bridge"

  networks_advanced {
    name = docker_network.services.id
  }

  mounts {
    target = "/var/tempo"
    source = docker_volume.tempo_data.name
    type   = "volume"
  }

  lifecycle {
    ignore_changes = [command, image]
  }
}
