# Phase 16-B: HAProxy Load Balancing & Auto-Scaling

**Status:** IN PROGRESS
**Effort:** 6 hours
**Target Completion:** April 17, 2026
**Dependencies:** None (parallel with 16-A)
**Owner:** DevOps Team

---

## Overview

Deploy highly available load balancing with:
- **HAProxy primary + standby** (99.95% availability)
- **Application auto-scaling** (1-50+ instances)
- **Health check probes** (every 10 seconds)
- **Session persistence** (for stateful operations)
- **Rate limiting** (per developer, per IP)
- **Metrics & monitoring** (real-time dashboard)

### Current State vs Target

```
CURRENT (Single application):
  Developers → 192.168.168.31:8080 (single node)
  Problem: No scaling, no failover, bottleneck at 1000 req/s

TARGET (Scaled & Load-Balanced):
  Developers
       ↓
  ┌─────────────────────┐
  │ HAProxy Primary     │────────┐
  │ 192.168.168.33:443  │        │ (automatic failover)
  │ Health checks: 10s  │        │
  └─────────────────────┘        │
       ↓                    ┌─────────────────────┐
  ┌───────────────────────┤ HAProxy Standby     │
  │                       │ 192.168.168.34:443  │
  ✓ (active)             │ (hot spare)         │
  │                       └─────────────────────┘
  ├─→ AppServer-1 (192.168.168.31:8080)  ✓ health OK
  ├─→ AppServer-2 (192.168.168.41:8080)  ✓ health OK
  ├─→ AppServer-3 (192.168.168.42:8080)  ✓ health OK
  └─→ AppServer-N (192.168.168.4x:8080)  ✓ auto-added

Results:
  • Throughput: 1,000 → 50,000+ req/s (50x scaling)
  • Latency: sub-100ms even under load
  • Availability: 99.95% (no downtime for deploys)
  • Automatic failover: <10 seconds
```

---

## Implementation: 6 Hours

### Hour 1: Deploy HAProxy Nodes

**Provision HAProxy Primary (192.168.168.33):**
```bash
# Terraform provisioning
resource "aws_instance" "haproxy_primary" {
  ami = data.aws_ami.ubuntu_20_04.id
  instance_type = "t3.large"  # 2 CPU, 8GB RAM for 50k conn/s
  private_ip = "192.168.168.33"
  security_groups = [aws_security_group.loadbalancer.id]
  tags = {role = "haproxy-primary"}
}

# Install HAProxy
apt-get install haproxy keepalived

# Enable
systemctl enable haproxy keepalived
```

**Provision HAProxy Standby (192.168.168.34):**
```bash
# Same as above with IP 192.168.168.34
# Both nodes use keepalived for VIP management (virtual IP)
```

### Hour 2: Configure HAProxy

**Global Configuration: /etc/haproxy/haproxy.cfg**
```ini
global
  log 127.0.0.1 local0
  maxconn 50000
  daemon

  # Tuning for high throughput
  tune.maxconn 50000
  tune.http.maxhdr 16384
  tune.ssl.default-dh-param 2048

  # Stats socket for monitoring
  stats socket /var/run/haproxy.sock mode 660 level admin
  stats timeout 30s

defaults
  mode http
  log global
  option httplog
  option http-keep-alive

  # Timeouts
  timeout connect 5000ms
  timeout client 50000ms
  timeout server 50000ms
  timeout http-request 10000ms
  timeout tunnel 1h

  retries 3

  # Error files
  errorfile 400 /etc/haproxy/errors/400.http
  errorfile 403 /etc/haproxy/errors/403.http
  errorfile 408 /etc/haproxy/errors/408.http
  errorfile 500 /etc/haproxy/errors/500.http

# Frontend: Accept client connections
frontend web_https
  bind *:443 ssl crt /etc/ssl/certs/code-server.pem
  bind *:80

  # Redirect HTTP to HTTPS
  http-request redirect scheme https code 301 if !{ ssl_fc }

  # ACLs: Route by hostname/path
  acl is_api path_beg /api/
  acl is_ide hdr(host) -i ide.dev.yourdomain.com

  # Request rate limiting (per IP)
  declare counter http_requests_per_ip
  http-request track-sc0 src
  http-request deny if { sc_http_req_rate(0) gt 1000 }  # 1000 req/s per IP

  # Logging
  option httplog
  log-request-file /var/log/haproxy/haproxy-requests.log

  # Route to backend
  use_backend api_servers if is_api
  default_backend ide_servers

# Backend: Application servers
backend ide_servers
  mode http
  balance roundrobin  # or leastconn for persistent connections

  # Session persistence (for stateful apps)
  cookie SERVERID insert indirect nocache

  # Health checks (every 10 seconds)
  option httpchk GET /health HTTP/1.1\r\nHost:\ code-server
  option forwardfor

  # Servers
  server app-1 192.168.168.31:8080 check fall 3 rise 2 cookie app1
  server app-2 192.168.168.41:8080 check fall 3 rise 2 cookie app2
  server app-3 192.168.168.42:8080 check fall 3 rise 2 cookie app3
  server app-4 192.168.168.43:8080 check disabled  # Spare for auto-scaling

# Backend: API servers (higher throughput, no sessions)
backend api_servers
  mode http
  balance leastconn  # Send to least-connected backend

  # Health checks
  option httpchk GET /api/health HTTP/1.1\r\nHost:\ code-server

  # Servers
  server api-1 192.168.168.31:8080 check
  server api-2 192.168.168.41:8080 check
  server api-3 192.168.168.42:8080 check

# Stats UI (admin only)
listen stats
  bind 127.0.0.1:8404
  stats enable
  stats admin if TRUE
  stats uri /stats
  stats refresh 30s
```

### Hour 3: Keepalived for Active-Passive Failover

**Primary (192.168.168.33): /etc/keepalived/keepalived.conf**
```
vrrp_script check_haproxy {
  script "/usr/local/bin/check_haproxy.sh"
  interval 2
  weight -20
}

vrrp_instance VI_1 {
  state MASTER
  interface eth0
  virtual_router_id 51
  priority 101  # Highest priority = master
  advert_int 1

  virtual_ipaddress {
    192.168.168.35/32 dev eth0  # Virtual IP
  }

  track_script {
    check_haproxy
  }
}
```

**Standby (192.168.168.34): /etc/keepalived/keepalived.conf**
```
vrrp_instance VI_1 {
  state BACKUP
  interface eth0
  virtual_router_id 51
  priority 100  # Lower priority = backup
  advert_int 1

  virtual_ipaddress {
    192.168.168.35/32 dev eth0  # Same virtual IP
  }

  track_script {
    check_haproxy
  }
}
```

**Health Check Script: /usr/local/bin/check_haproxy.sh**
```bash
#!/bin/bash
# Check if HAProxy is responding
if ! curl -s http://localhost:8404/stats > /dev/null 2>&1; then
  echo "HAProxy not responding, marking down"
  exit 1
fi
exit 0
```

### Hour 4: Auto-Scaling Groups

**Terraform ASG Configuration:**
```hcl
# Launch template for application servers
resource "aws_launch_template" "app_server" {
  name_prefix = "app-"
  image_id = data.aws_ami.ubuntu_20_04.id
  instance_type = "t3.medium"

  user_data = base64encode(file("${path.module}/scripts/bootstrap-app-server.sh"))

  tag_specifications {
    resource_type = "instance"
    tags = {role = "app-server"}
  }
}

# Auto-Scaling Group
resource "aws_autoscaling_group" "app_servers" {
  name = "app-servers-asg"
  min_size = 3
  max_size = 50
  desired_capacity = 5

  launch_template {
    id = aws_launch_template.app_server.id
    version = "$Latest"
  }

  vpc_zone_identifier = [aws_subnet.private.id]

  health_check_type = "ELB"
  health_check_grace_period = 300
}

# Scaling policies
resource "aws_autoscaling_policy" "scale_up" {
  name = "app-scale-up"
  scaling_adjustment = 2
  adjustment_type = "ChangeInCapacity"
  autoscaling_group_name = aws_autoscaling_group.app_servers.name
  cooldown = 60
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name = "app-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods = "2"
  metric_name = "CPUUtilization"
  namespace = "AWS/EC2"
  period = "60"
  statistic = "Average"
  threshold = "75"
  alarm_actions = [aws_autoscaling_policy.scale_up.arn]
}

resource "aws_autoscaling_policy" "scale_down" {
  name = "app-scale-down"
  scaling_adjustment = -1
  adjustment_type = "ChangeInCapacity"
  autoscaling_group_name = aws_autoscaling_group.app_servers.name
  cooldown = 300
}

resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name = "app-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods = "5"
  metric_name = "CPUUtilization"
  namespace = "AWS/EC2"
  period = "60"
  statistic = "Average"
  threshold = "20"
  alarm_actions = [aws_autoscaling_policy.scale_down.arn]
}
```

**Bootstrap Script: scripts/bootstrap-app-server.sh**
```bash
#!/bin/bash
set -e

# Update system
apt-get update && apt-get upgrade -y

# Install code-server
curl -fsSL https://code-server.dev/install.sh | sh

# Configure
sudo systemctl enable code-server
sudo systemctl start code-server

# Health check endpoint
cat > /opt/code-server-health.sh << 'EOF'
#!/bin/bash
curl -s http://localhost:8080/health || exit 1
EOF
chmod +x /opt/code-server-health.sh

# Metrics collection
curl -s https://repo.prometheus.io/debian/dists/bullseye/Release.gpg | apt-key add -
apt-get install prometheus-node-exporter
systemctl enable prometheus-node-exporter
```

### Hour 5: Monitoring & Metrics

**Prometheus Configuration: /etc/prometheus/prometheus.yml**
```yaml
scrape_configs:
  - job_name: 'haproxy'
    static_configs:
      - targets: ['127.0.0.1:8404']
    metrics_path: '/stats;csv'

  - job_name: 'autoscaling_group'
    ec2_sd_configs:
      - region: us-east-1
        port: 9100
    relabel_configs:
      - source_labels: [__meta_ec2_tag_role]
        target_label: instance_role
        regex: app-server
        action: keep

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['localhost:9093']

rule_files:
  - 'rules/haproxy.yml'
```

**Alert Rules: /etc/prometheus/rules/haproxy.yml**
```yaml
groups:
  - name: loadbalancer
    rules:
      - alert: HAProxyDown
        expr: up{job="haproxy"} == 0
        for: 30s
        annotations:
          severity: critical
          summary: "HAProxy is down"

      - alert: BackendServerDown
        expr: haproxy_backend_up != 1
        for: 2m
        annotations:
          severity: warning

      - alert: HighLatency
        expr: haproxy_backend_http_response_time_ms_quantile_p99 > 100
        for: 5m
        annotations:
          severity: warning

      - alert: RateLimitExceeded
        expr: rate(haproxy_frontend_request_errors_total[5m]) > 100
        for: 1m
        annotations:
          severity: info
```

**Grafana Dashboard Metrics:**
- Requests per second (frontend, backend)
- P99 latency (response time)
- Active connections (frontend, backend)
- Backend server health (up/down)
- Response codes (200, 4xx, 5xx)
- ASG capacity (desired, current, max)
- Server CPU/memory utilization
- Rate-limiting hits (per IP)

### Hour 6: Testing & Validation

**Test 1: Load Balancing Distribution**
```bash
# Generate load across all servers
ab -n 10000 -c 100 https://192.168.168.35/health

# Verify distribution (check HAProxy stats)
curl http://127.0.0.1:8404/stats | grep "# backend"

# Expected: Requests evenly distributed 33% each
```

**Test 2: Health Check Failover**
```bash
# Stop one backend server
ssh app-2 'sudo systemctl stop code-server'

# Observe:
# 1. HAProxy detects down within 10s (fall 3 × 3s)
# 2. No new requests sent to app-2
# 3. Existing connections gracefully drain
# 4. Metrics show 66% traffic to remaining servers

# Bring it back
ssh app-2 'sudo systemctl start code-server'

# Observe: Returns to normal distribution (33% each) within rise 2 × 3s = 6s
```

**Test 3: Auto-Scaling Under Load**
```bash
# Generate sustained high load
wrk -t 4 -c 1000 -d 10m https://192.168.168.35/api

# Monitor ASG in CloudWatch:
# 1. CPU rises above 75%
# 2. ASG alarm triggers scale-up
# 3. New instances launch (takes ~3 min)
# 4. New instances register with HAProxy health check
# 5. Traffic routes to new instances
# 6. Latency drops back to <100ms

# After load ends:
# 1. CPU drops below 20% for 5 min
# 2. ASG alarm triggers scale-down
# 3. Instances terminate gracefully (drain connections)
# 4. Capacity returns to minimum 3
```

**Test 4: HAProxy Failover**
```bash
# Kill HAProxy on primary
ssh haproxy-primary 'sudo systemctl stop haproxy'

# Observe:
# 1. Keepalived detects failure (<2s)
# 2. Virtual IP (192.168.168.35) migrates to standby
# 3. Clients reconnect to standby HAProxy
# 4. No packet loss (<5s of disruption)
# 5. Health checks continue monitoring backends

# Bring primary back
ssh haproxy-primary 'sudo systemctl start haproxy'
# Rejoins as primary again (higher priority)
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│ Internet / Cloudflare Tunnel                            │
└─────────────────────────────────────────────────────────┘
                       ↓
        ┌────────────────────────────┐
        │ Virtual IP 192.168.168.35  │ (via Keepalived)
        └────────────────────────────┘
            /                    \
    MASTER (active)        STANDBY (hot-spare)
    192.168.168.33         192.168.168.34
    ┌───────────────┐      ┌───────────────┐
    │ HAProxy       │ ────→│ HAProxy       │
    │ Keepalived    │      │ Keepalived    │
    │ Running       │      │ Standby       │
    └───────────────┘      └───────────────┘
           ↓
    ┌──────────────────────────────────────┐
    │    Application Backend Servers       │
    ├──────────────────────────────────────┤
    │ app-1: 192.168.168.31:8080 ✓       │
    │ app-2: 192.168.168.41:8080 ✓       │
    │ app-3: 192.168.168.42:8080 ✓       │
    │ app-4: 192.168.168.43:8080 ✓ (ASG) │
    │ app-N: dynamic (auto-scaled)        │
    └──────────────────────────────────────┘
           ↓
    ┌──────────────────────────────────────┐
    │ Postgres Database (from Phase 16-A)  │
    │ Primary: 192.168.168.31:5432         │
    │ Standby: 192.168.168.32:5433         │
    └──────────────────────────────────────┘
```

---

## Success Criteria

✅ **All Met** (After implementation):

1. **Load Distribution**
   - [ ] Requests evenly distributed across backends
   - [ ] No single backend over-loaded
   - [ ] Round-robin or least-conn working correctly

2. **High Availability**
   - [ ] HAProxy failover: <2 seconds
   - [ ] Backend failure detection: <10 seconds
   - [ ] Connection draining: graceful
   - [ ] No client connection loss on failover

3. **Performance**
   - [ ] Throughput: >50,000 req/s capacity
   - [ ] P99 Latency: <100ms under load
   - [ ] Connections: 50,000 concurrent supported
   - [ ] SSL/TLS overhead: <5% latency

4. **Auto-Scaling**
   - [ ] Scale-up triggers when CPU >75% (60s confirmation)
   - [ ] New instances healthy within 3 minutes
   - [ ] Scale-down when CPU <20% for 5 minutes
   - [ ] No dropped requests during scaling events

5. **Rate Limiting**
   - [ ] Per-IP limits: 1000 req/s enforced
   - [ ] Graceful rejection (429 Too Many Requests)
   - [ ] Limits logged to access logs

6. **Monitoring**
   - [ ] Prometheus scraping HAProxy stats active
   - [ ] Grafana dashboard visible
   - [ ] All alert rules firing correctly
   - [ ] Health check metrics in Prometheus

---

## Post-Implementation

**Handoff to Operations:**
- [ ] Failover procedures documented and tested
- [ ] Auto-scaling policies reviewed and approved
- [ ] Monitoring dashboards set up for SRE
- [ ] Alert escalation procedures defined
- [ ] Monthly failover drills scheduled

**Next Phase: Phase 17-A (Multi-Region)**

Load balancer replicates to secondary region with:
- Cross-region traffic distribution
- DNS-based failover
- Replication lag monitoring

---

## Files/Scripts Created

- `setup-haproxy.sh` - Complete HAProxy setup
- `setup-keepalived.sh` - HA failover coordination
- `haproxy-monitoring.yml` - Prometheus rules
- `asg-terraform.tf` - Auto-scaling configuration
- `bootstrap-app-server.sh` - Instance initialization
- `test-load-distribution.sh` - Load test script
- `test-failover.sh` - HA failover testing
