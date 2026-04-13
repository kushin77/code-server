# Phase 12.1: Terraform - PostgreSQL Multi-Primary Replication Setup
# Configures Cloud SQL instances with bidirectional replication across regions

resource "google_sql_database_instance" "federation_databases" {
  for_each = { for r in local.regions : r.region_id => r }

  name               = "${var.federation_name}-db-${each.value.region_id}"
  database_version   = "POSTGRES_15"
  region             = each.value.location
  deletion_protection = true

  instance_type = "CLOUD_SQL_INSTANCE"

  settings {
    tier              = "db-custom-2-8192"
    availability_type = "REGIONAL"
    disk_type         = "PD_SSD"
    disk_size         = 500

    # High availability configuration
    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      binary_log_enabled             = true
      backup_retention_settings {
        retained_backups = 30
        retention_unit   = "COUNT"
      }
    }

    # Network configuration
    ip_configuration {
      require_ssl = true
      
      # Allow all regional access (restrict further per use case)
      authorized_networks {
        name  = "office-network"
        value = "0.0.0.0/0"
      }
    }

    # Replication configuration
    database_flags {
      name  = "max_wal_senders"
      value = "10"
    }

    database_flags {
      name  = "max_replication_slots"
      value = "10"
    }

    database_flags {
      name  = "wal_level"
      value = "logical"
    }

    # Performance configuration
    database_flags {
      name  = "shared_buffers"
      value = "2097152" # 16GB
    }

    database_flags {
      name  = "effective_cache_size"
      value = "6291456" # 48GB
    }

    database_flags {
      name  = "work_mem"
      value = "16384" # 16MB
    }

    # Replication settings for BDR
    database_flags {
      name  = "bdr.enable"
      value = "off" # Will be enabled per region during init
    }

    maintenance_window {
      day          = 0  # Sunday
      hour         = 3  # 3 AM UTC
      update_track = "stable"
    }

    insights_config {
      query_insights_enabled  = true
      query_plans_per_minute  = 5
      query_string_length     = 1024
      record_application_tags = true
    }
  }

  project = var.gcp_project_id

  labels = merge(
    local.common_labels,
    {
      region     = each.value.region_id
      replica_id = each.value.replica_id
      database   = "primary"
    }
  )
}

# Create databases
resource "google_sql_database" "federation_databases" {
  for_each = { for r in local.regions : r.region_id => r }

  name     = "federation"
  instance = google_sql_database_instance.federation_databases[each.key].name

  depends_on = [google_sql_database_instance.federation_databases]

  project = var.gcp_project_id
}

# Create root user for replication
resource "google_sql_user" "replication_user" {
  for_each = { for r in local.regions : r.region_id => r }

  name     = "replication"
  instance = google_sql_database_instance.federation_databases[each.key].name
  type     = "BUILT_IN"

  password = random_password.replication_password.result

  project = var.gcp_project_id
}

# Create application user
resource "google_sql_user" "app_user" {
  for_each = { for r in local.regions : r.region_id => r }

  name     = "app"
  instance = google_sql_database_instance.federation_databases[each.key].name
  type     = "BUILT_IN"

  password = random_password.app_password.result

  project = var.gcp_project_id
}

# Random passwords
resource "random_password" "replication_password" {
  length  = 32
  special = true
}

resource "random_password" "app_password" {
  length  = 32
  special = true
}

# Store secrets in Secret Manager
resource "google_secret_manager_secret" "replication_credentials" {
  for_each = { for r in local.regions : r.region_id => r }

  secret_id = "${var.federation_name}-postgres-replication-${each.value.region_id}"

  replication {
    automatic = true
  }

  project = var.gcp_project_id
}

resource "google_secret_manager_secret_version" "replication_credentials" {
  for_each = { for r in local.regions : r.region_id => r }

  secret      = google_secret_manager_secret.replication_credentials[each.key].id
  secret_data = jsonencode({
    username = google_sql_user.replication_user[each.key].name
    password = random_password.replication_password.result
    host     = google_sql_database_instance.federation_databases[each.key].private_ip_address
    database = google_sql_database.federation_databases[each.key].name
    port     = 5432
  })

  project = var.gcp_project_id
}

resource "google_secret_manager_secret" "app_credentials" {
  for_each = { for r in local.regions : r.region_id => r }

  secret_id = "${var.federation_name}-postgres-app-${each.value.region_id}"

  replication {
    automatic = true
  }

  project = var.gcp_project_id
}

resource "google_secret_manager_secret_version" "app_credentials" {
  for_each = { for r in local.regions : r.region_id => r }

  secret      = google_secret_manager_secret.app_credentials[each.key].id
  secret_data = jsonencode({
    username = google_sql_user.app_user[each.key].name
    password = random_password.app_password.result
    host     = google_sql_database_instance.federation_databases[each.key].private_ip_address
    database = google_sql_database.federation_databases[each.key].name
    port     = 5432
  })

  project = var.gcp_project_id
}

# ============================================================================
# Outputs
# ============================================================================

output "database_instances" {
  description = "Cloud SQL database instances"
  value = {
    for region, instance in google_sql_database_instance.federation_databases :
    region => {
      name              = instance.name
      connection_name   = instance.connection_name
      private_ip        = instance.private_ip_address
      public_ip         = instance.public_ip_address
      database_version  = instance.database_version
    }
  }

  sensitive = false
}

output "database_names" {
  description = "Database names per region"
  value = {
    for region, db in google_sql_database.federation_databases :
    region => db.name
  }
}

output "replication_user_names" {
  description = "Replication user names"
  value = {
    for region, user in google_sql_user.replication_user :
    region => user.name
  }
}

output "app_user_names" {
  description = "Application user names"
  value = {
    for region, user in google_sql_user.app_user :
    region => user.name
  }
}

output "secret_manager_secrets" {
  description = "Secret Manager secret IDs"
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
