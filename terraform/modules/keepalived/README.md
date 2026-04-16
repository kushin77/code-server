# Keepalived Module for VRRP Failover

Manages Virtual Router Redundancy Protocol (VRRP) failover between primary and replica hosts. Automatically floats a Virtual IP (VIP) from primary to replica when primary becomes unhealthy.

## Architecture

```
Primary (192.168.168.31)              Replica (192.168.168.42)
├─ Keepalived priority=150            ├─ Keepalived priority=100
├─ state=MASTER                       ├─ state=BACKUP
├─ Holds VIP by default               ├─ Ready to claim VIP
│  └─ 192.168.168.30                  │
└─ Health checks every 5s             └─ Health checks every 5s
   ↓ Unhealthy?                          ↑ Primary unhealthy?
   └──→ VIP moves to replica in <2s ←─┘
```

## SLA

- **Failover time**: <2 seconds (from primary failure to replica claims VIP)
- **Health check interval**: 5 seconds
- **Failover triggers**: 2 consecutive failed health checks

## Files

```
keepalived/
├── main.tf                           # Main Keepalived resources
├── variables.tf                      # Input variables
├── outputs.tf                        # Output values (VIP, container IDs)
├── scripts/
│   ├── keepalived-notify.sh          # Called on state changes (MASTER/BACKUP/FAULT)
│   └── vrrp-health-monitor.sh        # Checks service health every 5s
├── build/
│   └── Dockerfile                    # Keepalived container image
└── templates/
    └── (Keepalived configs generated in main.tf)
```

## Usage

```hcl
module "keepalived" {
  source = "./modules/keepalived"
  
  # Inventory: production topology
  inventory = {
    vip = {
      ip   = "192.168.168.30"
      fqdn = "prod.internal"
    }
    hosts = {
      primary = {
        ip       = "192.168.168.31"
        fqdn     = "primary.prod.internal"
        ssh_user = "akushnir"
        ssh_port = 22
        roles    = ["code-server", "postgresql", "prometheus"]
      }
      replica = {
        ip       = "192.168.168.42"
        fqdn     = "replica.prod.internal"
        ssh_user = "akushnir"
        ssh_port = 22
        roles    = ["code-server", "postgresql", "prometheus"]
      }
    }
  }
  
  # Keepalived behavior
  enable_on_primary = true
  enable_on_replica = true
  keepalived_version = "2.2.8"
  
  # Health checks
  health_check_interval = 5      # seconds between checks
  health_check_retries = 2       # failed checks before failover
  health_check_timeout = 2       # seconds timeout per check
  
  # VRRP tuning
  vrrp_interval = 1              # seconds between VRRP advertisements
  vrrp_router_id = 51            # unique ID (1-255)
  failover_sla_seconds = 2       # expected failover time
}
```

## Key Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `inventory` | — | Production topology (required) |
| `keepalived_version` | 2.2.8 | Container image version |
| `health_check_interval` | 5 | Seconds between health checks |
| `health_check_retries` | 2 | Failed checks to trigger failover |
| `vrrp_interval` | 1 | Seconds between VRRP advertisements |
| `vrrp_router_id` | 51 | VRRP virtual router ID (1-255) |

## Health Checks

The `vrrp-health-monitor.sh` script checks:
- Prometheus (port 9090)
- PostgreSQL (port 5432)
- Code-server (port 8080)

If ≥2 services are down, the host is marked unhealthy and VIP failover is triggered.

## Monitoring

Watch Keepalived logs:
```bash
docker logs -f keepalived
```

Watch health checks:
```bash
tail -f /var/log/keepalived/health-check.log
```

Watch VRRP state changes:
```bash
tail -f /var/log/keepalived-notify.log
```

## Troubleshooting

### VIP not moving to replica when primary fails
1. Check primary health check log: `tail /var/log/keepalived/health-check.log`
2. Verify replica can see primary down: `docker logs keepalived`
3. Check replica can bind VIP: `ip addr show | grep 192.168.168.30`

### Container won't start
1. Check Keepalived logs: `docker logs keepalived`
2. Verify privileged mode: `docker inspect keepalived | grep Privileged`
3. Verify network_mode=host: `docker inspect keepalived | grep NetworkMode`

### Failover slower than 2s
1. Increase health check frequency: `health_check_interval = 2`
2. Decrease retries: `health_check_retries = 1`
3. Verify network latency: `ping -c 5 <replica-ip>`

## References

- [Keepalived Official](https://www.keepalived.org/)
- [VRRP RFC 5798](https://tools.ietf.org/html/rfc5798)
- [Debian Keepalived Docs](https://manpages.debian.org/keepalived.conf.5)
