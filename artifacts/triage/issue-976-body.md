## Severity: HIGH (alerting is completely non-functional — 2 findings)

---

## Finding 1 — alertmanager.yml in repo root is NOT the file mounted by docker-compose (docker-compose.yml:824)

### Evidence
```yaml
# docker-compose.yml line ~824
alertmanager:
  volumes:
    - ./config/alertmanager.yml:/etc/alertmanager/alertmanager.yml
```

But the repository has `./alertmanager.yml` at the root which is the file all developers edit.

`./config/alertmanager.yml` either does not exist or is a stale copy.

### Impact
Every change to routing, receivers, or inhibition rules made in `./alertmanager.yml` has **zero effect** on the running AlertManager. Operators believe they're changing alert routing when they're not.

### Fix
```yaml
# docker-compose.yml — change mount to:
volumes:
  - ./alertmanager.yml:/etc/alertmanager/alertmanager.yml
```
OR consolidate to `./config/alertmanager.yml` and delete the root copy. Either way, one file, one mount.

---

## Finding 2 — Alertmanager contains placeholder stubs — no alerts are delivered (alertmanager.yml:3, 58)

### Evidence
```yaml
# alertmanager.yml line 3
receivers:
  - name: 'slack-notifications'
    slack_configs:
      - api_url: 'https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK'
        channel: '#alerts'

# alertmanager.yml line 58
  - name: 'pagerduty'
    pagerduty_configs:
      - service_key: 'YOUR_PAGERDUTY_SERVICE_KEY'
```

These are literal placeholder strings. AlertManager will fail to send notifications on every alert.

### Impact
Zero operational alerts are delivered for any incident. The April 19 CSRF incident, the Redis SPOF, and every production failure since deployment has gone unnotified. The monitoring stack gives a false sense of security.

### Fix
1. Replace stubs with environment variable substitution:
   ```yaml
   receivers:
     - name: 'slack-notifications'
       slack_configs:
         - api_url: '${SLACK_WEBHOOK_URL}'
   ```
2. Provision secrets via GSM:
   ```bash
   gcloud secrets create slack-webhook-url --replication-policy=automatic
   gcloud secrets create pagerduty-service-key --replication-policy=automatic
   ```
3. Add to `scripts/fetch-gsm-secrets.sh` and `.env.schema.json`
4. Add CI check that alertmanager config doesn't contain placeholder strings:
   ```bash
   if grep -q 'YOUR/SLACK/WEBHOOK\|YOUR_PAGERDUTY_SERVICE_KEY' alertmanager.yml; then
     echo "ERROR: Placeholder values found in alertmanager.yml" >&2
     exit 1
   fi
   ```

### Also: Grafana dashboards not provisioned as code
Grafana dashboards are configured manually via UI and will be lost on volume recreation or failover to .42. Add dashboard JSON files to `config/grafana-dashboards/` and provision via the Grafana provisioning API (`provisioning/dashboards/*.yaml`).

---

## Definition of Done
- [ ] `docker compose config` shows correct alertmanager.yml mount path
- [ ] `./alertmanager.yml` and `./config/alertmanager.yml` consolidated to one file
- [ ] Placeholder strings replaced with env var substitution
- [ ] `SLACK_WEBHOOK_URL` and `PAGERDUTY_SERVICE_KEY` provisioned from GSM
- [ ] CI guard: `check-alertmanager-stubs.sh` fails on placeholder strings
- [ ] Test alert fires and is received in Slack (verified manually)
- [ ] At least one Grafana dashboard provisioned as code (auth path overview)
- [ ] Parent #967 updated with evidence

Fixes #967 (EPIC)
