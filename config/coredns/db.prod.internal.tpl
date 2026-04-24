; CoreDNS Zone File for prod.internal domain
;
; This file is GENERATED from environments/production/hosts.yml
; Do NOT edit manually. Regenerate via: scripts/render-inventory-templates.py
;
; TTL: 300 seconds (5 minutes) for all records
; Reloaded every 10 seconds to pick up inventory changes

$ORIGIN prod.internal.
$TTL    300

; ==============================================================================
; START OF AUTHORITY (SOA) — Zone metadata
; ==============================================================================
@   IN  SOA primary.prod.internal. hostmaster.prod.internal. (
            2026041600  ; Serial (YYYYMMDDVV format, version 00)
            3600        ; Refresh (1 hour)
            1800        ; Retry (30 minutes)
            604800      ; Expire (1 week)
            3600 )      ; Minimum TTL (1 hour)

; ==============================================================================
; NAMESERVERS — Authoritative DNS servers for this zone
; ==============================================================================
; CoreDNS runs on both primary and replica for resilience
@   IN  NS  primary.prod.internal.
@   IN  NS  replica.prod.internal.

; ==============================================================================
; A RECORDS — Hostname to IP mappings
; ==============================================================================

; Virtual IP — All external traffic and failover-aware services point here
@               IN  A   192.168.168.30  ; prod.internal (VIP, floating)

; Primary host — code-server, PostgreSQL primary, monitoring stack
primary         IN  A   192.168.168.31
mail._domainkey IN  A   192.168.168.31  ; SPF record (if mail is needed)

; Replica host — PostgreSQL replica, HAProxy, backup target, DNS secondary
replica         IN  A   192.168.168.42

; ==============================================================================
; CNAME RECORDS — Service aliases (point to logical hosts, not IPs)
; ==============================================================================
; These allow services to reference logical names like "db.prod.internal"
; instead of hardcoding to primary or replica.

; Database services — Route to primary for writes, can be updated for read-replica
db              IN  CNAME   primary.prod.internal.      ; PostgreSQL (primary)
database        IN  CNAME   primary.prod.internal.      ; Long form alias

; Cache services — Route to Redis primary
cache           IN  CNAME   primary.prod.internal.      ; Redis
redis           IN  CNAME   primary.prod.internal.      ; Redis long form

; Monitoring services — Route to primary
monitoring      IN  CNAME   primary.prod.internal.
prometheus      IN  CNAME   primary.prod.internal.      ; Prometheus
grafana         IN  CNAME   primary.prod.internal.      ; Grafana dashboards
alertmanager    IN  CNAME   primary.prod.internal.      ; AlertManager
alerts          IN  CNAME   primary.prod.internal.      ; Alerts (short alias)

; Tracing services — Route to primary
tracing         IN  CNAME   primary.prod.internal.
jaeger          IN  CNAME   primary.prod.internal.      ; Jaeger UI
traces          IN  CNAME   primary.prod.internal.      ; Traces (short alias)

; Logging services — Route to primary
logging         IN  CNAME   primary.prod.internal.
loki            IN  CNAME   primary.prod.internal.      ; Loki logs
logs            IN  CNAME   primary.prod.internal.      ; Logs (short alias)

; ==============================================================================
; SRV RECORDS — Service discovery (for advanced applications)
; ==============================================================================
; Format: _service._protocol.name TTL class SRV priority weight port target

; PostgreSQL service discovery (if using client-side service discovery)
_postgresql._tcp.prod.internal.  IN  SRV 10 60 5432 primary.prod.internal.
_postgresql._tcp.prod.internal.  IN  SRV 20 40 5432 replica.prod.internal.

; Redis service discovery
_redis._tcp.prod.internal.       IN  SRV 10 100 6379 primary.prod.internal.

; HTTP/HTTPS services
_http._tcp.prod.internal.        IN  SRV 10 100 80   primary.prod.internal.
_https._tcp.prod.internal.       IN  SRV 10 100 443  primary.prod.internal.

; ==============================================================================
; TXT RECORDS — Text metadata (SPF, DMARC, etc. if needed)
; ==============================================================================

; SPF record (if using email from this domain)
@       IN  TXT "v=spf1 -all"  ; Reject all email from this domain (we don't send)

; DMARC policy (optional)
_dmarc  IN  TXT "v=DMARC1; p=none"  ; Non-enforcing DMARC (monitoring only)

; ==============================================================================
; NOTES FOR MAINTENANCE
; ==============================================================================
;
; To add a new host (e.g., GPU worker at 192.168.168.43):
;   1. Update environments/production/hosts.yml
;   2. Run: scripts/render-inventory-templates.py
;   3. This file is regenerated automatically
;
; To change VIP or host IPs:
;   1. Update environments/production/hosts.yml
;   2. Run: scripts/render-inventory-templates.py
;   3. Verify: dig prod.internal @127.0.0.1
;   4. Restart CoreDNS: docker-compose restart coredns
;
; Testing:
;   dig prod.internal @127.0.0.1          ; Should return 192.168.168.30 (VIP)
;   dig primary.prod.internal @127.0.0.1  ; Should return 192.168.168.31
;   dig replica.prod.internal @127.0.0.1  ; Should return 192.168.168.42
;   dig db.prod.internal @127.0.0.1       ; Should return 192.168.168.31 (primary)
;
