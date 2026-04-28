# Monitoring & Alert Configuration Consolidation Strategy

**Status**: Phase 2 (In Progress)  
**Current State**: Alert/monitoring configs scattered in 5+ locations  
**Target State**: Unified `config/monitoring/` directory  
**Risk Level**: LOW (read-only config files)

---

## Current Inventory

### Alert Configuration Files (SCATTERED)
```
monitoring/alertmanager.yml              (Main alertmanager config)
monitoring/alerts/alert-rules.yml        (Alert rules - YAML format)
monitoring/alerts/prometheus-rules.yaml  (Alert rules - alternate format)
monitoring/alerts/grafana-alerts.json    (Grafana alerts - JSON format)
```

### Prometheus Configuration Files
```
config/prometheus.yml                    (Prometheus scrape config)
config/activity-feed-prometheus.yaml     (Service-specific scrape)
```

### Grafana Dashboards (DUPLICATED)
```
dashboards/kafka-event-bus-monitoring.json
dashboards/memory-engine-monitoring.json
grafana/kafka-event-bus-monitoring.json    (DUPLICATE)
grafana/memory-engine-monitoring.json      (DUPLICATE)
grafana/opa-policy-monitoring.json
```

### Otel Configuration (SCATTERED)
```
config/otel-collector.yaml                (AUTHORITATIVE?)
config/otel-collector.config.yaml         (DUPLICATE?)
```

### Tempo Configuration (SCATTERED)
```
config/tempo.yaml                         (AUTHORITATIVE?)
config/tempo.config.yaml                  (DUPLICATE?)
```

---

## Proposed Consolidated Structure

```
config/monitoring/
├── README.md                    (Overview)
├── alertmanager.yml             (Alert routing and grouping)
├── alerts/
│   ├── prometheus-rules.yml     (ALL prometheus alert rules)
│   ├── grafana-rules.yml        (Grafana alert definitions)
│   └── contact-points.yml       (Notification channels)
├── prometheus/
│   ├── prometheus.yml           (Main scrape config)
│   ├── service-scrapes/
│   │   ├── activity-feed.yml
│   │   ├── postgres.yml
│   │   └── *.yml
│   └── recording-rules.yml      (Pre-computed metrics)
├── dashboards/
│   ├── kafka-event-bus.json
│   ├── memory-engine.json
│   ├── opa-policy.json
│   └── *.json
├── otel/
│   ├── collector-config.yaml    (CANONICAL otel config)
│   └── receivers.yaml           (Receiver definitions)
├── tempo/
│   ├── tempo-config.yaml        (CANONICAL tempo config)
│   └── storage.yaml             (Storage backend config)
└── loki/
    ├── loki-config.yaml         (Log aggregation)
    └── scrape-rules.yml         (Log scrape patterns)
```

---

## Consolidation Plan

### Phase 2A: Analysis (1 day)

**Step 1: Identify Duplicates**
```bash
# Find identical files
find config monitoring dashboards grafana -name "*.json" -o -name "*.yml" -o -name "*.yaml" | \
  xargs -I {} sh -c 'echo "=== {} ===" && md5sum {} ' | sort -k2
```

**Step 2: Trace Dependencies**
```bash
# Find all references to each config file
grep -r "alertmanager.yml\|prometheus.yml\|otel-collector" \
  docker-compose*.yml terraform/ scripts/ .github/ --include="*.yml" --include="*.sh"
```

**Step 3: Document Service Bindings**
- Which service uses which config?
- What volume mounts reference these files?
- Any environment-specific overrides?

### Phase 2B: Consolidation (2 days)

**Step 1: Create Directory Structure**
```bash
mkdir -p config/monitoring/{alerts,prometheus/service-scrapes,dashboards,otel,tempo,loki}
```

**Step 2: Move and Consolidate**
- Move `monitoring/alertmanager.yml` → `config/monitoring/alertmanager.yml`
- Merge alert rules: `monitoring/alerts/{alert-rules.yml,prometheus-rules.yaml}` → `config/monitoring/alerts/prometheus-rules.yml`
- Remove duplicate dashboards (keep original, delete copy)
- Delete duplicate otel/tempo configs (keep authoritative, remove .config.yaml)

**Step 3: Update References**
```bash
# Update docker-compose volume mounts
# FROM: volumes: [./monitoring/alertmanager.yml:/etc/alertmanager/alertmanager.yml]
# TO:   volumes: [./config/monitoring/alertmanager.yml:/etc/alertmanager/alertmanager.yml]

# Update terraform provisioner commands
# FROM: execute via: config/prometheus.yml
# TO:   execute via: config/monitoring/prometheus/prometheus.yml
```

**Step 4: Update Documentation**
- Update DEPLOYMENT_MANIFEST.md with new paths
- Update service README files with monitoring config locations
- Create config/monitoring/README.md with full mapping

### Phase 2C: Validation (1 day)

**Test Checklist**:
- [ ] All alert rules load without syntax errors
- [ ] Prometheus scrape config valid
- [ ] Grafana dashboards import without errors
- [ ] Otel collector starts with consolidated config
- [ ] Tempo traces work with new config
- [ ] Loki log scraping continues working
- [ ] Docker-compose services mount configs correctly
- [ ] Terraform provisioning still works

**Validation Commands**:
```bash
# Prometheus rule syntax
promtool check rules config/monitoring/alerts/prometheus-rules.yml

# Docker-compose references
docker-compose -f docker-compose.yml config | grep -A 2 "volumes:"

# Terraform validation
terraform validate terraform/environments/private/
```

---

## Detailed Migration Steps

### Alert Manager Configuration
```yaml
# BEFORE: monitoring/alertmanager.yml
# AFTER:  config/monitoring/alertmanager.yml

# Update docker-compose.yml
# FROM:
  alertmanager:
    volumes:
      - ./monitoring/alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro

# TO:
  alertmanager:
    volumes:
      - ./config/monitoring/alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro
```

### Prometheus Rules Consolidation
```bash
# Merge prometheus alert rules
cat monitoring/alerts/alert-rules.yml monitoring/alerts/prometheus-rules.yaml > \
  config/monitoring/alerts/prometheus-rules.yml.merged

# Review for duplicates
diff <(sort monitoring/alerts/alert-rules.yml) <(sort monitoring/alerts/prometheus-rules.yaml)

# Keep merged version, delete originals
rm monitoring/alerts/alert-rules.yml monitoring/alerts/prometheus-rules.yaml
```

### Grafana Dashboards
```bash
# Identify duplicates
diff dashboards/kafka-event-bus-monitoring.json grafana/kafka-event-bus-monitoring.json
# If identical:
  - Keep dashboards/ version (closer to config/monitoring/)
  - Delete grafana/ version
  - Update references in docker-compose
```

### Otel Collector Configuration
```yaml
# Verify which is authoritative:
# Option A: config/otel-collector.yaml (more likely, config/ is standard)
# Option B: config/otel-collector.config.yaml (verify in use)

# After verification:
# - Keep authoritative version
# - Delete duplicate
# - Move to: config/monitoring/otel/collector-config.yaml
```

---

## Docker Compose Updates

```yaml
# BEFORE
volumes:
  - ./monitoring/alertmanager.yml:/etc/alertmanager/alertmanager.yml
  - ./config/prometheus.yml:/etc/prometheus/prometheus.yml
  - ./monitoring/alerts/prometheus-rules.yaml:/etc/prometheus/rules/alert.rules

# AFTER
volumes:
  - ./config/monitoring/alertmanager.yml:/etc/alertmanager/alertmanager.yml
  - ./config/monitoring/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml
  - ./config/monitoring/alerts/prometheus-rules.yml:/etc/prometheus/rules/alert.rules
```

---

## Terraform Updates

If terraform provisioning references these files:
```hcl
# BEFORE
provisioner "file" {
  source      = "${local.repo_root}/monitoring/alertmanager.yml"
  destination = "/tmp/alertmanager.yml"
}

# AFTER
provisioner "file" {
  source      = "${local.repo_root}/config/monitoring/alertmanager.yml"
  destination = "/tmp/alertmanager.yml"
}
```

---

## GitHub Actions Updates

If workflows reference monitoring configs:
```yaml
# BEFORE
- name: Validate prometheus rules
  run: promtool check rules monitoring/alerts/prometheus-rules.yaml

# AFTER
- name: Validate prometheus rules
  run: promtool check rules config/monitoring/alerts/prometheus-rules.yml
```

---

## Rollback Plan

If consolidation breaks monitoring:
```bash
# Keep git history for easy rollback
git log --oneline | grep "monitoring consolidation"

# Rollback to previous commit
git revert <commit-hash>
```

---

## Success Metrics

| Metric | Before | After | Success Criteria |
|--------|--------|-------|------------------|
| Config file locations | 5+ | 1 (config/monitoring/) | ✅ Centralized |
| Alert rule files | 3 | 1 | ✅ No duplication |
| Grafana dashboards | 2 (copies) | 1 | ✅ Single source |
| Otel configs | 2 | 1 | ✅ Clear SSOT |
| Deployment clarity | High scatter | Obvious structure | ✅ DRY |

---

## Related Documents

- [SSOT_GOVERNANCE_INDEX.md](../../SSOT_GOVERNANCE_INDEX.md) - Governance reference
- [DEPLOYMENT_MANIFEST.md](../../DEPLOYMENT_MANIFEST.md) - Deployment procedures
- [docker-compose.yml](../../docker-compose.yml) - Service definitions

---

**Status**: READY FOR PHASE 2B IMPLEMENTATION  
**Owner**: Infrastructure Audit Phase 2  
**Next Review**: After consolidation complete  
**Risk**: LOW (config-only, reversible with git)
