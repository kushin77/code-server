# PostgreSQL database for Synapse
resource "docker_image" "postgres" {
  name          = "postgres:${var.postgres_version}-alpine"
  pull_triggers = [var.postgres_version]
}

resource "docker_container" "postgres" {
  name    = "synapse-postgres-${var.region}"
  image   = docker_image.postgres.image_id
  restart = "unless-stopped"

  ports {
    internal = 5432
    external = 5433
  }

  env = [
    "POSTGRES_DB=synapse",
    "POSTGRES_USER=synapse",
    "POSTGRES_PASSWORD=${random_password.postgres_password.result}",
    "POSTGRES_INITDB_ARGS=-c max_connections=200",
  ]

  healthcheck {
    test     = ["CMD-SHELL", "pg_isready -U synapse"]
    interval = "10s"
    timeout  = "5s"
    retries  = 5
  }

  labels = {
    "com.example.environment" = var.environment
    "com.example.module"      = "matrix-homeserver"
  }
}

resource "random_password" "postgres_password" {
  length  = 32
  special = true
}

# Synapse homeserver
resource "docker_image" "synapse" {
  name          = var.docker_image
  pull_triggers = [var.docker_image]
}

resource "docker_container" "synapse" {
  name    = "synapse-homeserver-${var.region}"
  image   = docker_image.synapse.image_id
  restart = "unless-stopped"

  depends_on = [docker_container.postgres]

  ports {
    internal = 8008
    external = 8008
  }

  volumes {
    host_path      = "/srv/synapse/data"
    container_path = "/data"
  }

  env = [
    "SYNAPSE_SERVER_NAME=${var.matrix_domain}",
    "SYNAPSE_REPORT_STATS=no",
    "UID=991",
    "GID=991",
  ]

  healthcheck {
    test     = ["CMD", "curl", "-f", "http://localhost:8008/_matrix/client/versions"]
    interval = "30s"
    timeout  = "5s"
    retries  = 3
  }

  labels = {
    "com.example.environment" = var.environment
    "com.example.module"      = "matrix-homeserver"
  }
}

# Generate Synapse config file
resource "local_file" "synapse_config" {
  filename = "/srv/synapse/homeserver.yaml"
  
  content = templatefile("${path.module}/templates/homeserver.yaml.tpl", {
    server_name                 = var.matrix_domain
    report_stats                = false
    registration_allowed        = false
    password_config_enabled     = true
    postgres_host               = "synapse-postgres"
    postgres_port               = 5432
    postgres_dbname             = "synapse"
    postgres_user               = "synapse"
    postgres_password           = random_password.postgres_password.result
    postgres_pool_size          = var.db_pool_size
    max_upload_size             = var.max_upload_size
    redis_url                   = var.redis_url
    google_client_id            = var.google_client_id
    google_client_secret        = var.google_client_secret
    synapse_admin_token         = var.synapse_admin_token
    prometheus_url              = var.prometheus_url
  })

  depends_on = [docker_container.postgres]
}
