# Keepalived HA Deployment Guide

**Objective**: Enable automatic failover between primary (.31) and replica (.42) hosts using a shared VIP (192.168.168.30).

## Architecture

```
Router port-forward: 80/443 → 192.168.168.30 (VIP)
                                    ↓
                         ┌──────────┴──────────┐
                         ↓                     ↓
                     .31 (MASTER)         .42 (BACKUP)
                  priority: 100          priority: 90
                  Caddy: port 80         Caddy: port 80
                  Health: /health        Health: /health
```

## Configuration Files Location

- **Primary config**: `/etc/keepalived/keepalived.conf` (from `/tmp/keepalived.conf`)
- **Replica config**: `/etc/keepalived/keepalived.conf` (from `/tmp/keepalived.conf`)
- **Health check script**: `/usr/local/bin/check-caddy-health.sh` (already synced to `/tmp/`)
- **Notification scripts**: `/usr/local/bin/notify-{master,backup,fault}.sh` (already synced to `/tmp/`)

## Manual Deployment Steps

### On Primary Host (192.168.168.31):

```bash
ssh akushnir@192.168.168.31

# 1. Install keepalived
sudo apt-get update
sudo apt-get install -y keepalived

# 2. Deploy configuration
sudo cp /tmp/keepalived.conf /etc/keepalived/keepalived.conf

# 3. Deploy health check and notification scripts
sudo cp /tmp/check-caddy-health.sh /usr/local/bin/
sudo cp /tmp/notify-master.sh /usr/local/bin/
sudo cp /tmp/notify-backup.sh /usr/local/bin/
sudo cp /tmp/notify-fault.sh /usr/local/bin/

# 4. Make scripts executable
sudo chmod +x /usr/local/bin/check-caddy-health.sh
sudo chmod +x /usr/local/bin/notify-master.sh
sudo chmod +x /usr/local/bin/notify-backup.sh
sudo chmod +x /usr/local/bin/notify-fault.sh

# 5. Enable and start keepalived
sudo systemctl enable keepalived
sudo systemctl restart keepalived

# 6. Verify VIP assignment (should see 192.168.168.30)
ip addr show | grep 192.168.168.30

# 7. Check status
sudo systemctl status keepalived
sudo journalctl -u keepalived -n 20
```

### On Replica Host (192.168.168.42):

```bash
ssh akushnir@192.168.168.42

# Same steps 1-7 as primary
sudo apt-get update
sudo apt-get install -y keepalived
sudo cp /tmp/keepalived.conf /etc/keepalived/keepalived.conf
sudo cp /tmp/check-caddy-health.sh /usr/local/bin/
sudo cp /tmp/notify-*.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/check-caddy-health.sh
sudo chmod +x /usr/local/bin/notify-*.sh
sudo systemctl enable keepalived
sudo systemctl restart keepalived

# Verify (should NOT have VIP initially — replica is BACKUP)
ip addr show | grep 192.168.168.30

# Monitor for election
sudo journalctl -u keepalived -f
```

## VIP Behavior

- **Primary (.31) healthy**: owns VIP `192.168.168.30`
- **Primary fails** (Caddy down, port 80 unreachable): VIP migrates to .42 within 3-9 seconds
- **Primary recovers**: VIP migrates back to .31 (preempts replica)

## Health Check Details

The script `/usr/local/bin/check-caddy-health.sh`:
- Runs every 3 seconds (interval)
- Verifies `code-server-caddy` container is running
- Tests HTTP GET `http://127.0.0.1/health` (expects response containing "OK")
- If check fails 3 times consecutively (fall=3): host drops by 20 priority points
- If check recovers 2 times (rise=2): host regains priority

## Router Configuration

To complete the HA setup, update your router's port-forwarding rule:

**Change from:**
```
80/443 → 192.168.168.31:80/443
```

**Change to:**
```
80/443 → 192.168.168.30:80/443  (the VIP)
```

This allows automatic failover when .31 fails — traffic will reach .42 within seconds.

## Troubleshooting

**Check if VIP is active:**
```bash
ip addr show | grep 192.168.168.30
# Should show: inet 192.168.168.30/24 scope global secondary eth0
```

**Check keepalived status:**
```bash
sudo systemctl status keepalived
sudo journalctl -u keepalived -n 50
```

**Force election (test failover):**
```bash
# Stop keepalived on primary to trigger failover
sudo systemctl stop keepalived

# VIP should move to replica within 10 seconds
ssh akushnir@192.168.168.42 'ip addr show | grep 192.168.168.30'

# Restart on primary — VIP should return
sudo systemctl start keepalived
```

**Health check failing? Verify Caddy:**
```bash
docker ps | grep code-server-caddy
docker inspect code-server-caddy --format='{{.State.Running}}'
wget http://127.0.0.1/health
```

## Files Synced to Hosts

All config files are staged in `/tmp/` on both hosts:
- `/tmp/keepalived.conf` — keepalived configuration
- `/tmp/check-caddy-health.sh` — health check script
- `/tmp/notify-master.sh`, `/tmp/notify-backup.sh`, `/tmp/notify-fault.sh` — state change hooks

## DNS/Cloudflare Configuration

Once HA is deployed and router points 80/443 → VIP (.30):
- Cloudflare DNS for `kushnir.cloud` will resolve to your public IP
- Router NATs port 80/443 to 192.168.168.30 (the VIP)
- Requests automatically route to active master (.31 or .42)

## Next Steps

1. Manually deploy on both hosts using steps above, OR
2. Request user to provide sudo password for automated deployment, OR
3. Configure `/etc/sudoers.d/keepalived-nopass` for passwordless sudo

See [Container Port Mapping Commit](https://github.com/kushin77/code-server/commit/d0b07fca) for Caddy port binding context.
