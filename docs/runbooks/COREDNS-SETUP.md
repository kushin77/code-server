# CoreDNS Internal DNS Configuration
## Issue #363

CoreDNS provides internal DNS resolution for the `*.prod.internal` domain, enabling service discovery across the production environment.

### Why CoreDNS?

Instead of hardcoding `192.168.168.31` and `192.168.168.42` everywhere, services use DNS names:
- `primary.prod.internal` → Always resolves to the primary host
- `prod.internal` (VIP) → Floats between primary and replica during failover
- `db.prod.internal` → CNAME to primary (database service alias)
- `prometheus.prod.internal` → CNAME to primary (monitoring endpoint)

**Benefits**:
- Service discovery without hardcoded IPs
- Transparent failover: when primary fails, VIP changes, DNS resolves to replica
- Scalable: adding a 3rd node = one zone file update
- No external dependencies: runs in Docker on the primary host

### Architecture

```
192.168.168.31 (primary) runs CoreDNS
          ↓
    Responds to queries for *.prod.internal
          ↓
All hosts (primary + replica) point to :53 for DNS
          ↓
Services use FQDN instead of IP
          ↓
On failover: VIP moves, services still work (DNS TTL expires)
```

### Files

| File | Purpose |
|------|---------|
| `config/coredns/Corefile` | CoreDNS configuration (forward rules, caching, logging) |
| `config/coredns/zones/prod.internal.zone` | Forward DNS zone (A records for hosts) |
| `config/coredns/zones/prod.internal.rev` | Reverse DNS zone (PTR records) |
| `docker-compose.yml` | CoreDNS service definition |

### Configuration

#### Corefile (`config/coredns/Corefile`)

Controls how CoreDNS behaves:
- **Forward zones**: `prod.internal` + reverse zone `168.168.192.in-addr.arpa`
- **Zone file reload**: 30 seconds (changes propagate quickly)
- **Upstream resolvers**: 1.1.1.1 (Cloudflare) + 8.8.8.8 (Google)
- **Caching**: 300 seconds (5 minutes) for external domains
- **Logging**: Full query logging (optional, verbose)

#### Zone File (`config/coredns/zones/prod.internal.zone`)

Defines all DNS records:
```
primary         A   192.168.168.31     # Primary host IP
replica         A   192.168.168.42     # Replica host IP
@               A   192.168.168.30     # VIP (prod.internal = VIP)
db              CNAME primary          # Database alias
prometheus      CNAME primary          # Monitoring alias
```

Full list of records:
- **A records**: `primary`, `replica` (physical host IPs)
- **VIP**: `@` (prod.internal) = 192.168.168.30
- **Service aliases**: `db`, `cache`, `prometheus`, `grafana`, `alertmanager`, `jaeger`
- **CNAME chains**: e.g., `code-server` → prod.internal → VIP

### Deployment

#### 1. CoreDNS is already in docker-compose.yml

```yaml
coredns:
  image: coredns/coredns:1.11.1
  restart: always
  ports:
    - "53:53/udp"
    - "53:53/tcp"
  volumes:
    - ./config/coredns/Corefile:/etc/coredns/Corefile:ro
    - ./config/coredns/zones:/etc/coredns/zones:ro
  healthcheck:
    test: ["CMD-SHELL", "dig @127.0.0.1 primary.prod.internal +short"]
```

#### 2. Start CoreDNS

```bash
# From production host (192.168.168.31):
cd code-server-enterprise
docker-compose up -d coredns

# Verify it's running:
docker-compose ps coredns
# Should show: coredns ... Up (healthy)

# Test DNS resolution:
dig @127.0.0.1 primary.prod.internal
# Expected response: 192.168.168.31
```

#### 3. Configure host DNS resolution

Each host (`.31`, `.42`) should point to CoreDNS for `.prod.internal` lookups:

```bash
# On each host:
sudo bash -c 'cat > /etc/systemd/resolved.conf.d/prod-internal.conf' << 'EOF'
[Resolve]
DNS=192.168.168.31
FallbackDNS=8.8.8.8 1.1.1.1
Domains=~prod.internal
EOF

# Reload DNS resolver:
sudo systemctl restart systemd-resolved

# Test from the host:
dig primary.prod.internal
# Should return 192.168.168.31
```

This is automated in `scripts/bootstrap-node.sh` (Issue #367).

#### 4. Update zone file on changes

When you add a new host:

1. Update `environments/production/hosts.yml` (Issue #364)
2. Update `config/coredns/zones/prod.internal.zone` with new A record
3. CoreDNS auto-reloads zone file every 30 seconds
4. Alternatively, trigger immediate reload:

```bash
ssh akushnir@192.168.168.31 'docker-compose exec -T coredns sh -c "kill -HUP 1"'
# Or use: make dns-reload (from Makefile-topology)
```

### Testing

#### Local testing (from any machine with dig/nslookup)

```bash
# Test from local machine (if network allows):
dig @192.168.168.31 primary.prod.internal
dig @192.168.168.31 prod.internal          # VIP query
dig @192.168.168.31 prometheus.prod.internal

# Reverse DNS lookup:
dig -x 192.168.168.31 @192.168.168.31
# Should return: primary.prod.internal
```

#### Testing from within containers

```bash
# Test from code-server container:
docker-compose exec code-server bash
nslookup primary.prod.internal
nslookup db.prod.internal
ping prod.internal
```

#### CoreDNS health check

CoreDNS has a built-in health check in docker-compose:
```bash
docker-compose ps coredns
# Status: Up (healthy) = DNS is working
```

### Troubleshooting

#### "DNS resolution of prod.internal not working"

1. **Check CoreDNS is running**:
   ```bash
   docker-compose ps coredns
   # Should show: Up (healthy)
   ```

2. **Check zone file is valid**:
   ```bash
   docker-compose exec coredns coredns -test -conf /etc/coredns/Corefile
   # Should have no errors
   ```

3. **Check DNS query locally**:
   ```bash
   docker-compose exec coredns dig @127.0.0.1 primary.prod.internal +short
   # Should return: 192.168.168.31
   ```

4. **Check host resolver configuration**:
   ```bash
   cat /etc/systemd/resolved.conf.d/prod-internal.conf
   systemctl status systemd-resolved
   ```

5. **Check logs**:
   ```bash
   docker-compose logs -f coredns
   # Look for DNS queries and responses
   ```

#### "Zone file changes not taking effect"

CoreDNS reloads the zone file every 30 seconds. If changes aren't reflected:
1. Force reload: `make dns-reload`
2. Or restart CoreDNS: `docker-compose restart coredns`
3. Or wait 30 seconds for auto-reload

#### "What if CoreDNS goes down?"

Services stop resolving `.prod.internal` names. Mitigation:
1. Services should have fallback connection mechanisms
2. Code-server, PostgreSQL, Redis can work with IP addresses
3. High-priority fix: restart CoreDNS immediately
   ```bash
   docker-compose up -d coredns
   ```

### Integration with other issues

- **#364 (Inventory)**: Zone records derived from `environments/production/hosts.yml`
- **#365 (VRRP/VIP)**: VIP (`prod.internal`) floats between hosts, DNS handles resolution
- **#366 (Hardcoded IPs)**: All hardcoded IPs replaced with FQDN names resolved by CoreDNS
- **#367 (Bootstrap)**: New node provisioning updates zone file and reloads CoreDNS

### Acceptance Criteria (Issue #363)

- [x] CoreDNS container healthy on primary host
- [x] `dig @192.168.168.31 primary.prod.internal` → 192.168.168.31
- [x] `dig @192.168.168.31 replica.prod.internal` → 192.168.168.42
- [x] `dig @192.168.168.31 prod.internal` → 192.168.168.30 (VIP)
- [x] Upstream DNS (1.1.1.1) works for external domains
- [x] Zone files committed under `config/coredns/zones/`
- [x] Both .31 and .42 resolve .prod.internal names natively
- [x] CoreDNS metrics scraped by Prometheus (Prometheus config updated)
- [x] Pre-commit hook enforces no new hardcoded IPs

### References

- [CoreDNS Documentation](https://coredns.io/docs/)
- [Corefile Format](https://coredns.io/manual/toc/#corefile)
- [Zone File Format (RFC 1035)](https://tools.ietf.org/html/rfc1035)
- Related issues: #362 (epic), #364 (inventory), #365 (VIP), #366 (refactor IPs), #367 (bootstrap)
