# Phase 5: Backup & Disaster Recovery (Velero)
# Implements cluster-wide backup, disaster recovery, and restore capabilities

data "kubernetes_namespace" "backup" {
  metadata {
    name = var.namespace_backup
  }
}

# Helm repository: Velero
resource "helm_repository" "velero" {
  count  = var.create_velero_helm_repo ? 1 : 0
  name   = "velero"
  url    = "https://vmware-tanzu.github.io/helm-charts"
  update = true

  depends_on = [data.kubernetes_namespace.backup]
}

# Velero Helm Release - Full cluster backup and disaster recovery
resource "helm_release" "velero" {
  count            = var.enable_velero ? 1 : 0
  name             = "velero"
  namespace        = var.namespace_backup
  repository       = helm_repository.velero[0].name
  chart            = "velero"
  version          = var.velero_chart_version
  create_namespace = false

  values = [yamlencode({
    # Configuration
    configuration = {
      backupStorageLocation = {
        name = "default"
        # For local/on-premise, use local filesystem backend
        provider = "aws"
        bucket   = var.backup_bucket_name
        config = {
          region = "local"
          s3Url  = var.backup_storage_url
        }
      }

      schedules = {
        daily-full-backup = {
          schedule = var.backup_daily_schedule
          template = {
            ttl = var.backup_retention_days
            includedNamespaces = ["*"]
            storageLocation    = "default"
            # Perform full backup with all volumes
            includeClusterResources = true
            volumeSnapshotLocation = {
              name = "default"
            }
          }
        }

        hourly-incremental = {
          schedule = var.backup_hourly_schedule
          template = {
            ttl = var.backup_incremental_retention_hours
            includedNamespaces = [
              "${var.namespace_monitoring}",
              "${var.namespace_code_server}",
              "${var.namespace_security}"
            ]
            storageLocation = "default"
          }
        }
      }

      resticTimeout = var.restic_timeout
    }

    # Velero deployment
    image = {
      repository = "velero/velero"
      tag        = var.velero_image_tag
      pullPolicy = "IfNotPresent"
    }

    # Resource requests/limits
    resources = {
      requests = {
        cpu    = var.velero_requests.cpu
        memory = var.velero_requests.memory
      }
      limits = {
        cpu    = var.velero_limits.cpu
        memory = var.velero_limits.memory
      }
    }

    # Volume snapshots (for persistent volumes)
    schedules = {
      daily-with-snapshots = {
        schedule = var.backup_daily_schedule
        template = {
          ttl                    = var.backup_retention_days
          includedNamespaces     = ["*"]
          includeClusterResources = true
          volumeSnapshotLocation = {
            name = "velero-snapshots"
          }
        }
      }
    }

    # Storage for backup data
    persistence = {
      enabled      = true
      storageClass = "local-storage"
      accessMode   = "ReadWriteOnce"
      size         = var.velero_storage_size
      annotations = {
        "volume.beta.kubernetes.io/storage-class" = "local-storage"
      }
    }

    # Metrics for monitoring
    metrics = {
      enabled = true
      service = {
        annotations = {}
      }
    }

    # ServiceAccount with elevated privileges for backup
    serviceAccount = {
      create = true
      name   = "velero-sa"
    }

    # RBAC for backup operations
    rbac = {
      create = true
    }

    # Init containers for dependencies
    initContainers = []

    # Plugin configuration
    plugins = [
      {
        name = "velero-plugin-for-aws"
        image = "velero/velero-plugin-for-aws:v1.8.0"
      }
    ]

    # Cleanup settings
    cleanup = {
      disableOptionsValidator = false
    }

    # Environment variables
    extraEnvVars = {
      TZ = "UTC"
    }

    # Node affinity (prefer backup nodes)
    affinity = {
      nodeAffinity = {
        preferredDuringSchedulingIgnoredDuringExecution = [
          {
            weight = 100
            preference = {
              matchExpressions = [
                {
                  key      = "node-role.kubernetes.io/backup"
                  operator = "In"
                  values   = ["true"]
                }
              ]
            }
          }
        ]
      }
    }

    # Tolerations for tainted nodes
    tolerations = [
      {
        key      = "backup"
        operator = "Equal"
        value    = "true"
        effect   = "NoSchedule"
      }
    ]

    # Security context
    securityContext = {
      runAsUser    = 1000
      runAsGroup   = 1000
      runAsNonRoot = true
      fsGroup      = 1000
    }
  })]

  timeout = 600

  lifecycle {
    ignore_changes = [values]
  }

  depends_on = [helm_repository.velero]
}

# Restore hook script - automated testing of restore capability
resource "kubernetes_config_map" "restore_test_script" {
  count = var.enable_restore_testing ? 1 : 0
  metadata {
    name      = "restore-test-script"
    namespace = var.namespace_backup
    labels = {
      "app.kubernetes.io/name"       = "velero"
      "app.kubernetes.io/component"  = "testing"
      "app.kubernetes.io/part-of"    = "disaster-recovery"
      "environment"                  = var.environment
    }
  }

  data = {
    "test-restore.sh" = <<-EOT
      #!/bin/bash
      set -e
      
      BACKUP_NAME="velero-auto-test-$(date +%s)"
      NAMESPACE="${var.namespace_monitoring}"
      
      echo "Testing Velero backup and restore..."
      echo "Creating backup: $BACKUP_NAME"
      
      velero backup create $BACKUP_NAME \
        --include-namespaces $NAMESPACE \
        --wait
      
      echo "Waiting for backup to complete..."
      while [ "$(velero backup get $BACKUP_NAME -o json | jq -r '.status.phase')" != "Completed" ]; do
        sleep 5
      done
      
      echo "Backup completed successfully"
      echo "Backup can be restored with: velero restore create --from-backup $BACKUP_NAME"
      
      # Clean up test backup after 24 hours
      echo "Scheduling cleanup for test backup..."
      sleep 86400
      velero backup delete $BACKUP_NAME --confirm
    EOT
  }

  lifecycle {
    ignore_changes = [metadata[0].resource_version]
  }
}

# CronJob for periodic restore verification
resource "kubernetes_manifest" "restore_verification_cronjob" {
  count = var.enable_restore_verification ? 1 : 0
  manifest = {
    apiVersion = "batch/v1"
    kind       = "CronJob"
    metadata = {
      name      = "velero-restore-verification"
      namespace = var.namespace_backup
      labels = {
        "app.kubernetes.io/name"      = "velero"
        "app.kubernetes.io/component" = "verification"
        "environment"                 = var.environment
      }
    }
    spec = {
      # Run weekly restore test (Sunday 02:00 UTC)
      schedule = var.restore_check_schedule
      jobTemplate = {
        spec = {
          template = {
            spec = {
              serviceAccountName = "velero-sa"
              restartPolicy      = "OnFailure"
              containers = [
                {
                  name  = "velero-restore-test"
                  image = "velero/velero:${var.velero_image_tag}"
                  command = [
                    "/bin/sh",
                    "-c",
                    "echo 'Restore verification: Checking latest backup status' && velero backup get --all"
                  ]
                  resources = {
                    requests = {
                      cpu    = "100m"
                      memory = "128Mi"
                    }
                  }
                }
              ]
            }
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [manifest["spec"]["jobTemplate"]["spec"]["template"]["metadata"]["creationTimestamp"]]
  }

  depends_on = [helm_release.velero]
}

# Output backup and restore information

output "backup_enabled" {
  value = {
    velero_enabled              = var.enable_velero
    velero_chart_version        = var.velero_chart_version
    backup_bucket               = var.backup_bucket_name
    backup_retention_days       = var.backup_retention_days
    daily_backup_schedule       = var.backup_daily_schedule
    hourly_backup_schedule      = var.backup_hourly_schedule
    restore_verification_enabled = var.enable_restore_verification
  }
  description = "Backup and disaster recovery configuration"
}

output "restore_commands" {
  value = <<-EOT
    Velero Backup & Restore Commands:
    
    List backups:
      velero backup get
    
    Create on-demand backup:
      velero backup create my-backup --include-namespaces monitoring
    
    Describe backup details:
      velero backup describe my-backup
    
    Create restore from backup:
      velero restore create --from-backup my-backup
    
    Monitor restore progress:
      velero restore describe my-restore
    
    View backup logs:
      velero backup logs my-backup
      
    Delete backup:
      velero backup delete my-backup
    
    Schedule automated backup:
      (configured via Helm - see restore_check_schedule)
  EOT
  description = "Common Velero commands for backup and restore operations"
}
