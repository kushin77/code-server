# Monitoring & Observability Setup for 192.168.168.31
## Comprehensive Prometheus, Grafana, and Alerting Implementation

**Version**: 1.0  
**Date**: April 13, 2026  
**Scope**: GPU, NAS, Application, and System Monitoring  
**SLA Targets**: GPU 99.99%, NAS 99.95%, Application latency <500ms p99

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│             Monitoring Stack for 192.168.168.31                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  Data Collectors:                                                 │
│  ├─ Node Exporter (9100): System, CPU, memory, disk, network     │
│  ├─ NVIDIA DCGM (9400): GPU metrics, temp, power, ECC            │
│  ├─ cAdvisor (8080): Container resource usage                    │
│  ├─ Custom NAS Health Exporter: Mount, capacity, latency, IOPS   │
│  ├─ Code-Server Metrics (8443): IDE performance metrics          │
│  └─ Ollama Metrics (11434): LLM inference latency, VRAM          │
│                                                                   │
│  Time-Series Database:                                            │
│  └─ Prometheus (9090): 30-day retention, 15s scrape interval     │
│                                                                   │
│  Visualization & Alerting:                                        │
│  ├─ Grafana (3000): 3 dashboards (GPU, System, NAS)              │
│  ├─ AlertManager (9093): Alert routing and notification          │
│  └─ Alert Rules (config): 20+ alerts for SLA enforcement         │
│                                                                   │
│  Data Pipelines:                                                  │
│  └─ Node Exporter Textfile Collector: Custom NAS metrics         │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 1. Prometheus Configuration

### File: `/etc/prometheus/prometheus-31.yml`

**Key Metrics Collected**:

#### GPU Metrics (NVIDIA DCGM)
- `dcgm_gpu_active`: GPU availability (0=down, 1=up)
- `dcgm_gpu_utilization`: GPU compute utilization (0-100%)
- `dcgm_fb_free`: Free VRAM (bytes)
- `dcgm_fb_used`: Used VRAM (bytes)
- `dcgm_gpu_temp`: GPU temperature (°C)
- `dcgm_power_usage`: Power consumption (W)
- `dcgm_power_limit`: Power limit specification (W)
- `dcgm_sm_clock`: Streaming Multiprocessor clock (MHz)
- `dcgm_mem_clock`: Memory clock speed (MHz)
- `dcgm_ecc_errors_corrected`: ECC error count
- `dcgm_throttle_thermal`: Thermal throttling events

#### System Metrics (Node Exporter)
- `node_cpu_seconds_total`: CPU time per mode (user, system, idle)
- `node_memory_MemTotal_bytes`: Total system memory
- `node_memory_MemAvailable_bytes`: Available memory
- `node_filesystem_avail_bytes`: Available disk space
- `node_network_receive_bytes_total`: Network RX bytes
- `node_network_transmit_bytes_total`: Network TX bytes

#### NAS Metrics (Custom Exporter)
- `nas_mount_up`: Mount point availability (0/1)
- `nas_fs_size`: Total capacity (bytes)
- `nas_fs_avail`: Available space (bytes)
- `nas_fs_used`: Used space (bytes)
- `nas_io_latency_seconds`: I/O operation latency (histogram)
- `nas_io_operations_total`: Read/write operation count
- `nas_backup_succeeded_total`: Successful backups
- `nas_backup_failed_total`: Failed backups

#### Application Metrics
- `ollama_inference_latency_seconds`: Model inference time (histogram)
- `ollama_model_load_errors_total`: Model load failures
- `ollama_tokens_generated_total`: Token generation count

### Scrape Configuration

```yaml
# 15-second scrape interval for GPU and application metrics
# 30-second for NAS (reduce noise)
# 60-second for system metrics (lower priority)

scrape_configs:
  - job_name: 'nvidia-dcgm'
    scrape_interval: 30s  # GPU metrics every 30s
    static_configs:
      - targets: ['localhost:9400']

  - job_name: 'node-exporter'
    scrape_interval: 15s
    static_configs:
      - targets: ['localhost:9100']

  - job_name: 'ollama'
    scrape_interval: 30s  # LLM metrics
    static_configs:
      - targets: ['localhost:11434']
```

---

## 2. Alert Rules Configuration

### File: `/etc/prometheus/alert-rules-31.yml`

**Alert Groups**:

#### GPU Alerts (7 rules)
1. **GPUUnavailable** (CRITICAL)
   - Condition: GPU active == 0 for 2 min
   - Action: Check NVIDIA driver, container runtime permissions
   - SLA Impact: YES (affects 99.99% availability target)

2. **GPUHighTemperature** (WARNING)
   - Condition: Temp > 85°C for 5 min
   - Action: Check cooling, reduce workload
   
3. **GPUCriticalTemperature** (CRITICAL)
   - Condition: Temp > 95°C for 1 min
   - Action: Shutdown GPU workloads immediately

4. **GPUMemoryExhaustion** (WARNING)
   - Condition: <10% free VRAM for 5 min
   - Action: Reduce batch size, offload inference

5. **GPUPowerLimit** (WARNING)
   - Condition: Power usage > 95% of limit for 5 min
   - Action: Check thermal throttling risk

6. **GPUECCErrors** (WARNING)
   - Condition: >10 ECC errors in last hour
   - Action: Monitor for hardware degradation

#### NAS Alerts (6 rules)
1. **NASMountPointDown** (CRITICAL)
   - Condition: Mount unavailable for 2 min
   - Action: Check network, NAS health
   - SLA Impact: YES

2. **NASCapacityCritical** (CRITICAL)
   - Condition: >90% full for 5 min
   - Action: Immediate cleanup required

3. **NASCapacityWarning** (WARNING)
   - Condition: >75% full for 10 min
   - Action: Plan capacity expansion

4. **NASLatencyDegraded** (WARNING)
   - Condition: p99 latency > 100ms for 5 min
   - Action: Check network, NAS performance

5. **NASIOPSSaturation** (WARNING)
   - Condition: >100k IOPS sustained for 5 min
   - Action: Investigate workload concentration

6. **NASBackupFailure** (CRITICAL)
   - Condition: No successful backup for >1 hour
   - Action: Check backup logs, resume

#### Application Alerts (3 rules)
1. **CodeServerUnhealthy** (CRITICAL)
   - Condition: Service down for 2 min
   - Action: Check logs, restart container

2. **OllamaModelLoadFailure** (WARNING)
   - Condition: Load failures in last 5 min
   - Action: Check model availability, VRAM

3. **OllamaInferenceTimeout** (WARNING)
   - Condition: p99 latency > 5s for 5 min
   - Action: Check GPU saturation, batch size

#### SLO Compliance Alerts (3 rules)
1. **GPUAvailabilitySLOViolation** (CRITICAL)
   - Target: 99.99% (4m29s/month downtime)
   - Window: 1 hour evaluation

2. **NASAvailabilitySLOViolation** (CRITICAL)
   - Target: 99.95% (21m42s/month downtime)
   - Window: 1 hour evaluation

3. **ApplicationLatencySLOViolation** (WARNING)
   - Target: <500ms p99 (Ollama)
   - Window: 15-minute evaluation

---

## 3. Grafana Dashboards

### Dashboard 1: GPU Monitoring
**File**: `config/grafana-dashboards-31.yaml`

**Panels**:
- GPU Utilization (stat, per GPU)
- GPU Memory Usage (gauge, percentage)
- GPU Temperature (time series, trending)
- GPU Power Consumption (time series)
- GPU Memory Free Space (time series)
- GPU Clock Speeds (SM + memory clocks)
- ECC Errors Last Hour (stat)
- Thermal Throttle Events (stat)

**Refresh Rate**: 30s  
**Time Range**: Last 1 hour (customizable)  
**Use Case**: Real-time GPU health and performance monitoring

### Dashboard 2: System Monitoring
**Panels**:
- CPU Utilization (stat)
- Memory Utilization (gauge)
- Disk Usage (pie chart)
- System Load Average (time series, 1m/5m/15m)
- Network Traffic (time series, RX/TX)
- Disk I/O Utilization (time series)
- Process Top CPU (table)
- Process Top Memory (table)

**Refresh Rate**: 15s  
**Time Range**: Last 1 hour  
**Use Case**: Overall system health and resource pressure detection

### Dashboard 3: NAS/Storage Monitoring
**Panels**:
- NAS Mount Status (stat, per mount point)
- NAS Capacity by Mount Point (pie chart)
- NAS I/O Latency p99 (time series)
- NAS IOPS (time series, read/write)
- NAS Backup Success Rate (stat, 24-hour)
- NAS Free Space Trend (time series, 30-day)
- Capacity Projection (derived metrics)

**Refresh Rate**: 60s (lower frequency for storage)  
**Time Range**: Last 30 days  
**Use Case**: Storage capacity planning and health monitoring

---

## 4. Implementation Checklist

### Phase 1: Install Prometheus
```bash
# Install Prometheus
wget https://github.com/prometheus/prometheus/releases/download/v2.49.2/prometheus-2.49.2.linux-amd64.tar.gz
tar xvfz prometheus-2.49.2.linux-amd64.tar.gz
sudo mv prometheus-2.49.2.linux-amd64 /opt/prometheus

# Create system user
sudo useradd -r prometheus

# Configure prometheus-31.yml (from config/prometheus-31.yml)
sudo cp config/prometheus-31.yml /etc/prometheus/
sudo chown prometheus:prometheus /etc/prometheus/prometheus-31.yml

# Create systemd service
sudo tee /etc/systemd/system/prometheus.service << EOF
[Unit]
Description=Prometheus
After=network.target

[Service]
Type=simple
User=prometheus
ExecStart=/opt/prometheus/prometheus --config.file=/etc/prometheus/prometheus-31.yml --storage.tsdb.path=/var/lib/prometheus
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable prometheus
sudo systemctl start prometheus

# Verify: http://localhost:9090
```

### Phase 2: Install Exporters

#### Node Exporter
```bash
wget https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz
tar xvfz node_exporter-1.7.0.linux-amd64.tar.gz
sudo mv node_exporter-1.7.0.linux-amd64/node_exporter /usr/local/bin/

# Enable textfile collector for custom NAS metrics
sudo mkdir -p /var/lib/node_exporter/textfile_collector
sudo chown node_exporter:node_exporter /var/lib/node_exporter/textfile_collector

# Systemd service with textfile collector
sudo tee /etc/systemd/system/node_exporter.service << EOF
[Unit]
Description=Node Exporter
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/node_exporter --collector.textfile.directory=/var/lib/node_exporter/textfile_collector
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable node_exporter
sudo systemctl start node_exporter
```

#### NVIDIA DCGM Exporter
```bash
# Docker method (recommended)
docker run -d \
  --name nvidia-dcgm-exporter \
  --gpus all \
  -p 9400:9400 \
  nvcr.io/nvidia/k8s/dcgm-exporter:3.1.7-3.1.4-ubuntu20.04

# Verify: curl http://localhost:9400/metrics | grep dcgm_gpu_active
```

#### cAdvisor (Container Metrics)
```bash
docker run -d \
  --name cadvisor \
  --volume /:/rootfs:ro \
  --volume /var/run:/var/run:rw \
  --volume /sys:/sys:ro \
  --volume /var/lib/docker/:/var/lib/docker:ro \
  -p 8080:8080 \
  gcr.io/cadvisor/cadvisor:latest
```

### Phase 3: Install Grafana
```bash
# Install Grafana
sudo apt-get install -y grafana-server

sudo systemctl daemon-reload
sudo systemctl enable grafana-server
sudo systemctl start grafana-server

# Access: http://localhost:3000 (admin/admin)

# Add Prometheus data source
curl -X POST http://admin:admin@localhost:3000/api/datasources \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Prometheus",
    "type": "prometheus",
    "url": "http://localhost:9090",
    "access": "proxy",
    "isDefault": true
  }'

# Import dashboards from config/grafana-dashboards-31.yaml
```

### Phase 4: Configure Alertmanager
```bash
# Install Alertmanager
wget https://github.com/prometheus/alertmanager/releases/download/v0.26.0/alertmanager-0.26.0.linux-amd64.tar.gz
tar xvfz alertmanager-0.26.0.linux-amd64.tar.gz
sudo mv alertmanager-0.26.0.linux-amd64/alertmanager /usr/local/bin/

# Create config
sudo tee /etc/alertmanager/config.yml << EOF
global:
  resolve_timeout: 5m

route:
  receiver: 'default'
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h
  routes:
    - match:
        severity: critical
      receiver: 'critical'
      repeat_interval: 5m

receivers:
  - name: 'default'
    webhook_configs:
      - url: 'http://localhost:5001/'

  - name: 'critical'
    email_configs:
      - to: 'ops-team@example.com'
        from: 'alertmanager@192.168.168.31'
        smarthost: 'mail.example.com:587'
        auth_username: 'alertmanager'
        auth_password: 'PASSWORD'
EOF

sudo systemctl restart prometheus
```

### Phase 5: Setup Custom NAS Metrics Exporter
```bash
# Create textfile exporter script
sudo tee /usr/local/bin/nas-metrics-exporter.sh << 'EOF'
#!/bin/bash
# Export NAS metrics to Node Exporter textfile collector

OUTPUT=/var/lib/node_exporter/textfile_collector/nas_metrics.prom

# Monitor mount points
for mount in /mnt/nas-primary /mnt/nas-backup /mnt/nas-archive; do
    if mountpoint -q "$mount"; then
        status=1
    else
        status=0
    fi
    
    echo "nas_mount_up{mount_path=\"$mount\"} $status" >> $OUTPUT.tmp
    
    if [ $status -eq 1 ]; then
        # Get filesystem stats
        stats=$(df "$mount" | tail -1)
        size=$(echo "$stats" | awk '{print $2 * 1024}')
        avail=$(echo "$stats" | awk '{print $4 * 1024}')
        used=$((size - avail))
        
        echo "nas_fs_size{mount_path=\"$mount\"} $size" >> $OUTPUT.tmp
        echo "nas_fs_avail{mount_path=\"$mount\"} $avail" >> $OUTPUT.tmp
        echo "nas_fs_used{mount_path=\"$mount\"} $used" >> $OUTPUT.tmp
    fi
done

# Check backup status
last_backup=$(stat -c %Y /backup/last-backup.timestamp 2>/dev/null || echo 0)
now=$(date +%s)
diff=$((now - last_backup))

if [ $diff -lt 3600 ]; then
    echo "nas_backup_succeeded_total 1" >> $OUTPUT.tmp
else
    echo "nas_backup_failed_total 1" >> $OUTPUT.tmp
fi

echo "nas_backup_last_success_epoch $last_backup" >> $OUTPUT.tmp

mv $OUTPUT.tmp $OUTPUT
EOF

sudo chmod +x /usr/local/bin/nas-metrics-exporter.sh

# Schedule via cron (every 5 minutes)
sudo crontab -e
# Add: */5 * * * * /usr/local/bin/nas-metrics-exporter.sh
```

---

## 5. SLO Targets & Thresholds

| Component | Metric | Target | Alert Threshold | Window |
|-----------|--------|--------|-----------------|--------|
| GPU | Availability | 99.99% | <99.99% * 0.001 | 1 hour |
| NAS | Availability | 99.95% | <99.95% * 0.001 | 1 hour |
| Ollama | p99 Latency | <500ms | >500ms | 15 min |
| Ollama | Token Rate | 50+ tokens/sec | Varies | N/A |
| GPU | Memory | 80-90% utilization | >90% | 5 min |
| NAS | Capacity | <90% | >90% | 5 min |
| System | CPU | <75% sustained | >80% | 5 min |
| System | Memory | <80% | >85% | 5 min |

---

## 6. Operational Procedures

### Daily Checks
```bash
# Check Prometheus targets
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'

# Check alert status
curl http://localhost:9090/api/v1/alerts | jq '.data[] | {alertname, state, value}'

# Check Grafana health
curl http://localhost:3000/api/health
```

### Troubleshooting

**NoData in Dashboard**:
```bash
# Check Prometheus has metrics
curl http://localhost:9090/api/v1/query?query=dcgm_gpu_active
# Check collection job is scraping
curl http://localhost:9090/api/v1/targets | grep nvidia-dcgm
```

**High Alert Frequency**:
- Tune alert thresholds in alert-rules-31.yml
- Adjust for your baseline (collect 1-week baseline first)

**Missing GPU Metrics**:
```bash
# Check NVIDIA DCGM exporter
docker logs nvidia-dcgm-exporter
# Check GPU visibility
nvidia-smi
```

---

## 7. Maintenance

- **Prometheus Storage**: 30-day retention, monitor disk usage
- **Alertmanager Logs**: Rotate weekly
- **Grafana Database**: Backup weekly
- **Rule Updates**: Test in non-prod first

---

## Next Steps

1. Deploy this month: Phase 5-6 (Production Monitoring Setup)
2. Establish baselines: 1 week of metrics collection
3. Tune alert thresholds based on actual behavior
4. Create on-call runbooks for each alert type
5. Document alert routing and escalation procedures

