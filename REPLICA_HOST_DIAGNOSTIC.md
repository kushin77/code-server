# Replica Host Connectivity Diagnostic Report
**Date**: 2026-04-28  
**Status**: 🔴 CRITICAL - Replica host (192.168.168.42) unreachable

## Executive Summary
The replica host at 192.168.168.42 is currently inaccessible via SSH (port 22), preventing:
- Cluster replication status verification
- High availability failover testing
- Multi-node deployment validation
- Active-active cluster operations

## Issue Details

### Observed Symptoms
1. **SSH Connection Timeout**: `ssh akushnir@192.168.168.42` times out after 30 seconds
2. **Service Verification**: Unable to run remote diagnostics on replica
3. **Container Status**: Unknown if replica containers are running or have failed
4. **Network Reachability**: Potential network isolation or incorrect routing

### Last Known Status
- **Previous Report**: CLUSTER-SHUTDOWN-REPORT-2026-04-27.md (April 27, 2026)
- **Result**: Primary host containers successfully stopped (13 containers)
- **Replica Status**: Inaccessible (connection timeout on SSH)

## Diagnostic Steps

### 1. Network Connectivity Check (Local Environment)
```bash
# Test DNS resolution
getent hosts 192.168.168.42
nslookup 192.168.168.42

# Test basic ICMP connectivity
ping -c 3 192.168.168.42

# Test TCP connectivity to SSH port
nc -zv 192.168.168.42 22

# Test ARP connectivity
arp -a | grep 192.168.168.42
```

### 2. SSH Configuration Review
```bash
# Check SSH config for explicit overrides
cat ~/.ssh/config | grep -A 5 "192.168.168.42"

# Test SSH with verbose output
ssh -vvv akushnir@192.168.168.42 'echo ok' 2>&1 | head -50

# Check SSH key accessibility
ls -la ~/.ssh/id_rsa ~/.ssh/id_ed25519

# Verify key permissions
chmod 600 ~/.ssh/id_rsa
```

### 3. Remote Infrastructure Investigation (if accessible)
```bash
# Once connected via SSH:
ssh akushnir@192.168.168.42 << 'EOF'
  echo "=== System Status ==="
  uptime
  uname -a
  
  echo "=== Network Interfaces ==="
  ip addr show
  
  echo "=== Docker Status ==="
  docker ps -a
  
  echo "=== SSH Service ==="
  sudo systemctl status ssh
  
  echo "=== Firewall Rules ==="
  sudo iptables -L -n | grep -i port\ 22 || echo "No specific SSH rules"
  
  echo "=== System Logs (recent errors) ==="
  sudo journalctl -n 50 --no-pager
EOF
```

### 4. Network Configuration Checks
- **Verify IP Address**: Is 192.168.168.42 correct per infrastructure documentation?
- **Check Subnet Mask**: Should be on same /24 network as primary (192.168.168.31)
- **Verify Routing**: Check if all traffic is correctly routed to replica subnet
- **Check Firewall Rules**: Ensure port 22 is not blocked on local firewall

### 5. Fail2ban Investigation
Per user memory, SSH can be blocked by fail2ban on on-prem hosts:
```bash
# If you can access from another host with sudo:
sudo fail2ban-client status sshd
sudo fail2ban-client set sshd unbanip akushnir@<YOUR_IP>
```

## Root Cause Analysis

### Likely Causes (in order of probability)
1. **Replica Host Offline**: VM/bare metal is not running or has crashed
2. **Network Isolation**: Host is on different network/VLAN, not accessible from primary
3. **SSH Service Disabled**: Remote sshd is not running or has crashed
4. **Firewall Blocking**: UFW, iptables, or cloud firewall blocking port 22
5. **fail2ban Lockout**: Too many failed connection attempts (IDS blocked)
6. **Incorrect IP Address**: Configuration points to wrong IP address

## Remediation Steps

### Immediate Action (If infrastructure access available)
```bash
# Check if host is reachable from local network
ping -c 1 192.168.168.42

# If ping works, try SSH with extended timeout
ssh -o ConnectTimeout=60 akushnir@192.168.168.42 'uptime'

# If fail2ban blocks exist:
# Coordinate with infrastructure team to unban IP
# From replica host: sudo fail2ban-client set sshd unbanip <SOURCE_IP>
```

### Escalation Path
1. **Infrastructure Team**: Verify replica host is powered on and network accessible
2. **Network Team**: Confirm routing between primary (192.168.168.31) and replica (192.168.168.42)
3. **Security Team**: Check if SSH port is blocked by organizational firewall
4. **Ops Team**: Verify docker-compose files are deployed on replica; restart if needed

### Long-Term Fixes
1. **Add Health Checks**: Implement automated replica host monitoring
2. **Documentation**: Update infrastructure as code with correct host IPs
3. **Automation**: Create automated failover detection and alerting
4. **High Availability**: Implement keepalive/heartbeat between primary and replica

## Deployment Impact

### Blocked Operations
- ❌ Multi-node Docker Compose deployments
- ❌ Cluster failover testing
- ❌ Active-active mode validation
- ❌ Replica sync verification
- ❌ Full deployment test execution

### Workarounds (Temporary)
1. Single-node deployment to primary host only
2. Manual failover via direct replica access
3. Separate testing environment if available

## Monitoring & Recovery

### Automated Detection Script
```bash
#!/bin/bash
# Test replica connectivity every 5 minutes
while true; do
  if timeout 10 ssh -o ConnectTimeout=5 akushnir@192.168.168.42 'echo ok' &>/dev/null; then
    echo "[$(date)] ✅ Replica host is reachable"
    break
  else
    echo "[$(date)] ❌ Replica host unreachable - retrying in 5 minutes"
    sleep 300
  fi
done
```

### Alert Triggers
- SSH connection timeout > 2 consecutive failures
- Docker status shows "Exited" or "Error" on 3+ containers
- Replication lag > 30 seconds (if applicable)

## References
- Primary Host: 192.168.168.31 (✅ Accessible)
- Replica Host: 192.168.168.42 (❌ Inaccessible)
- Previous Status: [CLUSTER-SHUTDOWN-REPORT-2026-04-27.md](CLUSTER-SHUTDOWN-REPORT-2026-04-27.md)
- Infrastructure Documentation: See terraform/environments/

## Next Steps
1. **Day 1**: Run diagnostic checks to identify root cause
2. **Day 2**: Coordinate with infrastructure team for remediation
3. **Day 3**: Validate replica connectivity and cluster health
4. **Day 4**: Execute full deployment test with replica participation
5. **Day 5**: Implement automated monitoring per "Long-Term Fixes"

---
**Generated**: 2026-04-28T04:32:00Z  
**Audit Bot**: Infrastructure Audit System  
**Status**: Awaiting manual investigation and infrastructure team escalation
