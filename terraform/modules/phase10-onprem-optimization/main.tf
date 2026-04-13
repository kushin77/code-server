# Phase 10: On-Premises Optimization
# Implements on-premises-specific optimizations for resource efficiency, 
# performance, and operational excellence

# ===== RESOURCE QUOTA & LIMITS =====

# Namespace resource quotas to prevent resource exhaustion
resource "kubernetes_resource_quota" "monitoring_quota" {
  count = var.enable_resource_quotas ? 1 : 0
  metadata {
    name      = "monitoring-quota"
    namespace = var.namespace_monitoring
    labels = {
      "app.kubernetes.io/name"    = "resource-quota"
      "app.kubernetes.io/part-of" = "optimization"
      "environment"               = var.environment
    }
  }

  spec {
    hard = {
      "requests.cpu"    = var.monitoring_quota_cpu
      "requests.memory" = var.monitoring_quota_memory
      "limits.cpu"      = var.monitoring_quota_cpu_limit
      "limits.memory"   = var.monitoring_quota_memory_limit
      "pods"            = "100"
      "persistentvolumeclaims" = "10"
      "services.nodeports" = "5"
    }
    scope_selector {
      match_expression {
        operator = "In"
        scope_name = "PriorityClass"
        values = ["high-priority", "standard"]
      }
    }
  }

  lifecycle {
    ignore_changes = [metadata[0].resource_version]
  }
}

resource "kubernetes_resource_quota" "code_server_quota" {
  count = var.enable_resource_quotas ? 1 : 0
  metadata {
    name      = "code-server-quota"
    namespace = var.namespace_code_server
    labels = {
      "app.kubernetes.io/name"    = "resource-quota"
      "app.kubernetes.io/part-of" = "optimization"
      "environment"               = var.environment
    }
  }

  spec {
    hard = {
      "requests.cpu"    = var.code_server_quota_cpu
      "requests.memory" = var.code_server_quota_memory
      "limits.cpu"      = var.code_server_quota_cpu_limit
      "limits.memory"   = var.code_server_quota_memory_limit
      "pods"            = "20"
      "persistentvolumeclaims" = "20"
    }
  }

  lifecycle {
    ignore_changes = [metadata[0].resource_version]
  }
}

# ===== PRIORITY CLASSES =====

# High-priority workloads (monitoring, core services)
resource "kubernetes_priority_class" "high_priority" {
  count = var.enable_priority_classes ? 1 : 0
  metadata {
    name = "high-priority"
    labels = {
      "app.kubernetes.io/name"    = "priority-class"
      "app.kubernetes.io/part-of" = "optimization"
      "environment"               = var.environment
    }
  }

  value       = 1000
  global_default = false
  description = "High priority for critical infrastructure components (monitoring, backup)"

  lifecycle {
    ignore_changes = [metadata[0].resource_version]
  }
}

# Standard priority workloads
resource "kubernetes_priority_class" "standard_priority" {
  count = var.enable_priority_classes ? 1 : 0
  metadata {
    name = "standard"
    labels = {
      "app.kubernetes.io/name"    = "priority-class"
      "app.kubernetes.io/part-of" = "optimization"
    }
  }

  value       = 100
  global_default = true
  description = "Standard priority for general workloads"

  lifecycle {
    ignore_changes = [metadata[0].resource_version]
  }
}

# Development priority (preemptible)
resource "kubernetes_priority_class" "development_priority" {
  count = var.enable_priority_classes ? 1 : 0
  metadata {
    name = "development"
    labels = {
      "app.kubernetes.io/name"    = "priority-class"
      "app.kubernetes.io/part-of" = "optimization"
    }
  }

  value       = 1
  global_default = false
  description = "Development workloads (can be preempted)"

  lifecycle {
    ignore_changes = [metadata[0].resource_version]
  }
}

# ===== HORIZONTAL POD AUTOSCALING =====

# HPA for code-server (scale based on CPU)
resource "kubernetes_horizontal_pod_autoscaler_v2" "code_server" {
  count = var.enable_hpa && var.enable_code_server_hpa ? 1 : 0
  metadata {
    name      = "code-server-hpa"
    namespace = var.namespace_code_server
    labels = {
      "app.kubernetes.io/name"    = "code-server"
      "app.kubernetes.io/part-of" = "optimization"
      "environment"               = var.environment
    }
  }

  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "StatefulSet"
      name        = "code-server"
    }

    min_replicas = var.code_server_hpa_min
    max_replicas = var.code_server_hpa_max

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = var.code_server_cpu_threshold
        }
      }
    }

    metric {
      type = "Resource"
      resource {
        name = "memory"
        target {
          type                = "Utilization"
          average_utilization = var.code_server_memory_threshold
        }
      }
    }

    behavior {
      scale_down {
        stabilization_window_seconds = 300
        policies {
          type          = "Percent"
          value         = 50
          period_seconds = 60
        }
      }
      scale_up {
        stabilization_window_seconds = 60
        policies {
          type          = "Percent"
          value         = 100
          period_seconds = 30
        }
        policies {
          type          = "Pods"
          value         = 1
          period_seconds = 30
        }
        select_policy = "Max"
      }
    }
  }

  lifecycle {
    ignore_changes = [metadata[0].resource_version]
  }
}

# ===== NODE AFFINITY & OPTIMIZATION =====

# ConfigMap: Node optimization script
resource "kubernetes_config_map" "node_optimization" {
  count = var.create_node_optimization_script ? 1 : 0
  metadata {
    name      = "node-optimization"
    namespace = "kube-system"
    labels = {
      "app.kubernetes.io/name"    = "node-optimization"
      "app.kubernetes.io/part-of" = "optimization"
      "environment"               = var.environment
    }
  }

  data = {
    "optimize-nodes.sh" = <<-EOT
#!/bin/bash
set -euo pipefail

# Node optimization script for on-premises clusters

echo "=== Node Optimization for On-Premises Clusters ==="

# Enable CPU and memory overcommit monitoring
echo "Configuring kernel parameters..."

# Increase file descriptor limits
sysctl -w fs.file-max=2097152 || true
sysctl -w net.ipv4.ip_local_port_range="1024 65535" || true

# Enable TCP connection tracking
sysctl -w net.netfilter.nf_conntrack_max=1000000 || true

# Disable swap (Kubernetes requirement)
swapoff -a || true
sed -i '/ swap / s/^/#/' /etc/fstab || true

# Enable IP forwarding
sysctl -w net.ipv4.ip_forward=1 || true

# Optimize disk I/O
echo noop > /sys/block/sda/queue/scheduler 2>/dev/null || true

echo "Node optimization complete"
    EOT
  }

  lifecycle {
    ignore_changes = [metadata[0].resource_version]
  }
}

# ===== CLUSTER METRICS & MONITORING OPTIMIZATION =====

# ConfigMap: Metrics retention policy
resource "kubernetes_config_map" "metrics_optimization" {
  count = var.create_metrics_optimization ? 1 : 0
  metadata {
    name      = "metrics-optimization"
    namespace = var.namespace_monitoring
    labels = {
      "app.kubernetes.io/name"    = "metrics-optimization"
      "app.kubernetes.io/part-of" = "optimization"
      "environment"               = var.environment
    }
  }

  data = {
    "retention-policy.yaml" = yamlencode({
      apiVersion = "v1"
      kind       = "ConfigMap"
      metadata = {
        name      = "prometheus-retention"
        namespace = var.namespace_monitoring
      }
      data = {
        retention = var.metrics_retention_days
        chunkSize = var.metrics_chunk_size
        compactInterval = var.metrics_compact_interval
      }
    })

    "optimization-guide.md" = <<-EOT
# Metrics Optimization for On-Premises Clusters

## Retention Configuration
- Prometheus retention: ${var.metrics_retention_days} days
- Chunk size: ${var.metrics_chunk_size} MB
- Compaction interval: ${var.metrics_compact_interval} hours

## Storage Optimization
1. Enable compression in Prometheus
2. Configure StorageClass with local-fast tier for ephemeral metrics
3. Archive old metrics to long-term storage

## Query Optimization
1. Increase wal.segment-duration for batch I/O
2. Enable cache-control headers
3. Use recording rules for expensive queries

## Memory Optimization
1. Limit cardinality (labels)
2. Use metric relabeling to drop unnecessary labels
3. Configure --storage.tsdb.max-block-duration

## Example: Storage Optimization
graph_storage:
  retention_size: "${var.metrics_max_storage_size}"
  retention_days: ${var.metrics_retention_days}
  compression: true
  wal_compression: true
    EOT
  }

  lifecycle {
    ignore_changes = [metadata[0].resource_version]
  }
}

# ===== COST OPTIMIZATION =====

# ConfigMap: Cost optimization report
resource "kubernetes_config_map" "cost_optimization" {
  count = var.create_cost_optimization_report ? 1 : 0
  metadata {
    name      = "cost-optimization-report"
    namespace = "default"
    labels = {
      "app.kubernetes.io/name"    = "cost-optimization"
      "app.kubernetes.io/part-of" = "optimization"
      "environment"               = var.environment
    }
  }

  data = {
    "cost-analysis.md" = <<-EOT
# On-Premises Cost Optimization Report

## Current Configuration
- Nodes: ${var.cluster_node_count} (on-premises servers)
- Average utilization: ${var.target_node_utilization}%
- Power efficiency: Tier-${var.power_efficiency_tier}

## Cost Breakdown
### Hardware
- Server cost per unit: \$${var.cost_per_server}
- Total server cost: \$${var.cost_per_server * var.cluster_node_count}
- Amortization: ${var.server_amortization_years} years

### Infrastructure
- Power consumption per server: ${var.power_per_server_kw}kW
- Annual power cost: \$${var.annual_power_cost}
- Network bandwidth: \$${var.network_cost_per_month}/month
- Cooling/facilities: \$${var.cooling_cost_per_month}/month

### Personnel
- Operations team: ${var.ops_team_size} FTE
- Annual labor cost: \$${var.ops_team_size * var.engineering_cost_annual}

## Total On-Premises Cost (Annual)
- Hardware depreciation: \$${var.cost_per_server * var.cluster_node_count / var.server_amortization_years}
- Power & cooling: \$${(var.annual_power_cost + (var.cooling_cost_per_month * 12))}
- Network: \$${var.network_cost_per_month * 12}
- Labor: \$${var.ops_team_size * var.engineering_cost_annual}
- **TOTAL: \$${(var.cost_per_server * var.cluster_node_count / var.server_amortization_years) + (var.annual_power_cost + (var.cooling_cost_per_month * 12)) + (var.network_cost_per_month * 12) + (var.ops_team_size * var.engineering_cost_annual)}**

## Cost Optimization Strategies

### 1. Right-Sizing Workloads
- Reduce over-provisioned resources
- Use HPA for automatic scaling
- Set appropriate request/limit ratios

### 2. Bin Packing Optimization
- Run daemonsets on dedicated nodes
- Use node affinity for workload distribution
- Monitor and compact node usage

### 3. Storage Optimization
- Compress logs and metrics
- Archive old data to cold storage
- Remove unused persistent volumes

### 4. Network Optimization
- Enable local DNS caching
- Optimize inter-zone bandwidth
- Consolidate egress paths

## ROI Analysis
- Cost per year: \$${(var.cost_per_server * var.cluster_node_count / var.server_amortization_years) + (var.annual_power_cost + (var.cooling_cost_per_month * 12)) + (var.network_cost_per_month * 12) + (var.ops_team_size * var.engineering_cost_annual)}
- Uptime SLA: ${var.uptime_sla}%
- Cost per 9s: \$${((var.cost_per_server * var.cluster_node_count / var.server_amortization_years) + (var.annual_power_cost + (var.cooling_cost_per_month * 12)) + (var.network_cost_per_month * 12) + (var.ops_team_size * var.engineering_cost_annual)) / (1 - (1 - var.uptime_sla/100))}
    EOT
  }

  lifecycle {
    ignore_changes = [metadata[0].resource_version]
  }
}

# ===== OPERATIONAL RUNBOOKS =====

# ConfigMap: On-premises runbooks
resource "kubernetes_config_map" "operational_runbooks" {
  count = var.create_operational_runbooks ? 1 : 0
  metadata {
    name      = "onprem-runbooks"
    namespace = "default"
    labels = {
      "app.kubernetes.io/name"    = "runbooks"
      "app.kubernetes.io/part-of" = "optimization"
      "environment"               = var.environment
    }
  }

  data = {
    "01-node-failure-recovery.md" = <<-EOT
# On-Premises: Node Failure Recovery Runbook

## Incident: Node Failure Detected

### Detection
- Kubernetes marks node as NotReady
- Pods fail to reach critical nodes
- HPA attempts to reschedule workloads

### Immediate Actions (T+0)
1. **Alert team** - Page on-call ops engineer
2. **Drain node**:
   ```bash
   kubectl drain NODE_NAME --ignore-daemonsets --delete-emptydir-data
   ```
3. **Check node status**:
   ```bash
   kubectl describe node NODE_NAME
   kubectl logs -n kube-system <kubelet-pod>
   ```

### Diagnosis (T+5 min)
1. **Physical inspection** of server hardware
2. **Check IPMI/iLO console** for boot/OS errors
3. **Verify network connectivity** (ping, SSH)
4. **Review system logs**:
   ```bash
   dmesg | tail -100
   journalctl -u kubelet -n 50
   ```

### Recovery (T+15 min)
1. **If hardware failure**: 
   - Physically replace or repair node
   - Rejoin cluster: `kubeadm join ...`
   - Uncordon node: `kubectl uncordon NODE_NAME`

2. **If OS corruption**:
   - Boot from recovery media
   - Reinstall OS and Kubernetes binaries
   - Initialize kubelet and restore node

3. **If network issue**:
   - Check switch configuration
   - Verify IP routing
   - Test connectivity: `kubectl get nodes`

### Verification (T+30 min)
```bash
# Node should reach Ready state
kubectl get nodes NODE_NAME

# Pods reschedule successfully
kubectl get pods -A | grep NODE_NAME

# Metrics flow resumes
kubectl top nodes
```

### Post-Incident (T+1 hour)
- [ ] Document root cause
- [ ] Update runbook if needed
- [ ] Schedule preventive maintenance
- [ ] Review backup/restore procedures
    EOT

    "02-storage-full-recovery.md" = <<-EOT
# On-Premises: Storage Full Recovery Runbook

## Incident: Persistent Volume or Node Storage Full

### Detection
- Pod fails with "Disk Pressure" condition
- `df -h` shows 100% usage on partition
- Application logs report write errors

### Immediate Actions (T+0)
```bash
# Check node disk pressure
kubectl describe node NODE_NAME | grep -A5 Conditions

# Identify full filesystem
df -h | grep 100%

# Check largest consumers
du -sh /* | sort -rh | head -10
```

### Clean Old Logs (T+5 min)
```bash
# Clean Docker/containerd logs
find /var/log/containers -mtime +7 -delete

# Clean old journal logs
journalctl --vacuum=30d

# Clean temporary files
rm -rf /tmp/* /var/tmp/*
```

### Resize PV (T+15 min)
```bash
# List PVCs with usage
kubectl get pvc -A

# Check PV size
kubectl get pv

# Resize PVC (if using dynamic provisioner)
kubectl patch pvc POD_NAME -p '{"spec":{"resources":{"requests":{"storage":"100Gi"}}}}'

# Or resize manually
kubectl edit pv PV_NAME
```

### Archive Old Data (T+30 min)
```bash
# Compress and archive metrics/logs
tar -czf logs-backup-$(date +%Y%m%d).tar.gz /var/log/

# Move to backup storage
mv logs-backup-*.tar.gz /mnt/backup/
```

### Monitoring (T+1 hour)
```bash
# Watch disk usage
watch -n 5 'df -h; echo; du -sh /*'

# Monitor recovery
kubectl describe node NODE_NAME
```
    EOT

    "03-network-partition-recovery.md" = <<-EOT
# On-Premises: Network Partition Recovery Runbook

## Incident: Network Partition or Latency

### Detection
- Nodes unable to communicate
- etcd cluster degraded
- API server timeouts

### Diagnosis (T+0)
```bash
# Check node connectivity
for node in \$(kubectl get nodes -o name); do
  echo "Testing \$node:"
  kubectl debug \$node --image=busybox -- ping -c 1 <other-node-ip>
done

# Check etcd cluster health
kubectl -n kube-system exec -it etcd-master -- \
  etcdctl --endpoints=127.0.0.1:2379 member list

# Check API server logs
kubectl logs -n kube-system -l component=kube-apiserver --tail=50
```

### Restore Connectivity (T+15 min)
1. **Network team** investigates switch/router
2. **Check routing tables** on affected nodes
3. **Verify DNS resolution**: `nslookup kubernetes.default`
4. **Force kubeadm rejoin** if needed

### Recover etcd (T+30 min)
```bash
# If etcd cluster is split:
kubectl -n kube-system exec etcd-master -- \
  etcdctl --endpoints=<all_cluster_members> \
  endpoint health

# Force remove unhealthy member
kubectl -n kube-system exec etcd-master -- \
  etcdctl member remove <member-id>
```

### Validation (T+1 hour)
```bash
# API server should respond
kubectl version

# All nodes should be Ready
kubectl get nodes

# Etcd should be healthy
kubectl -n kube-system exec -it etcd-master -- \
  etcdctl endpoint health
```
    EOT

    "04-backup-restore-procedure.md" = <<-EOT
# On-Premises: Backup & Restore Procedure

## Daily Backup Checklist
- [ ] Velero daily backup completed
- [ ] Backup storage verified
- [ ] Backup size within expectations
- [ ] No backup errors in logs

## Full Cluster Restore (Disaster Recovery)

### Preparation
```bash
# List available backups
kubectl -n backup exec velero-<pod> -- velero backup get

# Describe backup
kubectl -n backup exec velero-<pod> -- \
  velero backup describe <backup-name>
```

### Restore Procedure (Estimated: 1-2 hours)
```bash
# 1. Start with fresh Kubernetes cluster
kubeadm init --dry-run

# 2. Install Velero restore components
helm install velero vmware-tanzu/velero \\
  --namespace velero \\
  --values velero-values.yaml

# 3. Trigger restore
kubectl -n velero exec velero-<pod> -- \\
  velero restore create \\
    --from-backup <backup-name> \\
    --wait

# 4. Monitor restore progress
kubectl -n velero exec velero-<pod> -- \\
  velero restore describe <restore-name>

# 5. Verify all resources
kubectl get all -A
```

### Validation
```bash
# All pods should be running
kubectl get pods -A

# Services should be accessible
kubectl get svc -A

# Data should be intact
kubectl exec -it <app-pod> -- \
  ls -la /data/
```
    EOT
  }

  lifecycle {
    ignore_changes = [metadata[0].resource_version]
  }
}

# ===== OUTPUTS =====

output "optimization_status" {
  value = {
    resource_quotas_enabled    = var.enable_resource_quotas
    priority_classes_enabled   = var.enable_priority_classes
    hpa_enabled                = var.enable_hpa
    node_optimization_enabled  = var.create_node_optimization_script
    metrics_optimization       = var.create_metrics_optimization
    cost_analysis              = var.create_cost_optimization_report
  }
  description = "On-premises optimization features enabled"
}

output "cost_summary" {
  value = <<-EOT
ON-PREMISES COST ANALYSIS
========================

Annual Operating Cost Estimate:
  Hardware: \$${var.cost_per_server * var.cluster_node_count / var.server_amortization_years}
  Power: \$${var.annual_power_cost}
  Cooling: \$${var.cooling_cost_per_month * 12}
  Network: \$${var.network_cost_per_month * 12}
  Labor: \$${var.ops_team_size * var.engineering_cost_annual}
  
Total: \$${(var.cost_per_server * var.cluster_node_count / var.server_amortization_years) + var.annual_power_cost + (var.cooling_cost_per_month * 12) + (var.network_cost_per_month * 12) + (var.ops_team_size * var.engineering_cost_annual)}/year

See cost-optimization-report ConfigMap for detailed breakdown
  EOT
  description = "Annual operating cost summary"
}

output "optimization_commands" {
  value = <<-EOT
On-Premises Optimization Commands:

View resource quotas:
  kubectl get resourcequota -A

Scale workloads (HPA status):
  kubectl get hpa -A

Check node capacity:
  kubectl describe nodes | grep -A5 "Allocated resources"

View optimization runbooks:
  kubectl get configmap onprem-runbooks -o jsonpath='{.data}'

Monitor cost:
  kubectl get configmap cost-optimization-report -o jsonpath='{.data.cost-analysis\.md}'

Node optimization:
  kubectl get configmap node-optimization
  EOT
  description = "Common commands for on-premises optimization"
}
