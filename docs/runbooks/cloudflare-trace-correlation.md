# Runbook: Cloudflare-to-Container Trace Correlation

## Purpose
Map an end-user Cloudflare request (identified by `CF-Ray` header) through the full
stack to the originating container span in Jaeger. Enables on-call to move from
edge alert → container root cause in under 5 minutes.

## Architecture

```
Browser → Cloudflare Edge → CF-Ray: 8abc1234def567ab-IAD
                        ↓
          Caddy (port 80) — forwards as X-Cf-Ray-Id header
                        ↓
         oauth2-proxy → code-server
                        ↓
          OTel Collector — enriches span with cf.ray.id attribute
                        ↓
               Jaeger — searchable by cf.ray.id
                        ↓
                  Loki — cf_ray_id index label on caddy logs
```

## Step 1 — Get the CF-Ray ID

From Cloudflare dashboard → Traffic → Logs, or from the user's browser:
- Chrome DevTools → Network → Request Headers → `CF-Ray`
- Example: `CF-Ray: 8abc1234def567ab-IAD`
- Extract just the hex part: `8abc1234def567ab`

## Step 2 — Find the Trace in Jaeger

Open: http://192.168.168.31:16686

**Option A — Tag Search**:
1. Service: `caddy` or `code-server`
2. Tags: `cf.ray.id=8abc1234def567ab`
3. Click Search → select the matching trace

**Option B — Loki LogQL query** (Grafana → Explore → Loki):
```logql
{container_name="caddy"} | json | cf_ray_id="8abc1234def567ab"
```

## Step 3 — Navigate to Container Logs

From the Jaeger trace view, note the `traceId` (e.g., `f3a1b2c4d5e6...`). Then in Grafana:
```logql
{container_name=~"code-server|oauth2-proxy"} |= "f3a1b2c4d5e6"
```

## Reference

- CF-Ray format: `<16-hex-chars>-<3-letter-datacenter>` (IAD = Ashburn, etc.)
- OTel span attribute name: `cf.ray.id`
- Loki label: `cf_ray_id`
- Jaeger URL: http://192.168.168.31:16686
- Grafana URL: http://192.168.168.31:3000

## Related Issues
- #375 epic(governance): Elite Enterprise Environment Program
