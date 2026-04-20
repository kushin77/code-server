## P1: Replace AlertManager Placeholder Webhooks with GSM-Sourced Secrets

### Problem

**File**: `alertmanager.yml`, lines 2-3 and throughout

AlertManager configuration contains **placeholder secrets** that won't work in production:

```yaml
global:
  slack_api_url: 'https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK'
...
pagerduty_configs:
  - service_key: 'YOUR_PAGERDUTY_SERVICE_KEY'
```

### Impact

1. **Production alerts won't reach on-call team**: Critical alerts like `PostgresDown` silently fail
2. **Incident response delayed**: No notification means no response
3. **Security implications**: Failed alerts could mask security incidents

### Current State

```yaml
# alertmanager.yml:

global:
  slack_api_url: 'https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK'  # ← PLACEHOLDER
  
receivers:
  - name: 'slack-notifications'
    slack_configs:
      - channel: '#alerts'
        send_resolved: true
        
  - name: 'pagerduty-critical'
    pagerduty_configs:
      - service_key: 'YOUR_PAGERDUTY_SERVICE_KEY'  # ← PLACEHOLDER
```

### Required Changes

#### 1. Store Secrets in GSM

```bash
# Create secrets in Google Secret Manager
gcloud secrets create alertmanager-slack-webhook --replication-policy=automatic
echo -n "https://hooks.slack.com/services/REAL/WEBHOOK/URL" | \
  gcloud secrets versions add alertmanager-slack-webhook --data-file=-

gcloud secrets create alertmanager-pagerduty-key --replication-policy=automatic
echo -n "real-pagerduty-service-key" | \
  gcloud secrets versions add alertmanager-pagerduty-key --data-file=-
```

#### 2. Parameterize alertmanager.yml

```yaml
# alertmanager.yml:
global:
  slack_api_url: '${SLACK_WEBHOOK_URL}'
  
receivers:
  - name: 'pagerduty-critical'
    pagerduty_configs:
      - service_key: '${PAGERDUTY_SERVICE_KEY}'
```

#### 3. Fetch Secrets at Deploy Time

```bash
# scripts/ops/fetch-alertmanager-secrets.sh
source scripts/fetch-gsm-secrets.sh

export SLACK_WEBHOOK_URL=$(gcloud secrets versions access latest --secret=alertmanager-slack-webhook)
export PAGERDUTY_SERVICE_KEY=$(gcloud secrets versions access latest --secret=alertmanager-pagerduty-key)

envsubst < alertmanager.yml.tpl > alertmanager.yml
```

#### 4. Add to docker-compose.yml

```yaml
alertmanager:
  environment:
    SLACK_WEBHOOK_URL: ${SLACK_WEBHOOK_URL}
    PAGERDUTY_SERVICE_KEY: ${PAGERDUTY_SERVICE_KEY}
```

### Validation

```bash
# Test Slack webhook
curl -X POST -H 'Content-type: application/json' \
  --data '{"text":"AlertManager test from code-server"}' \
  "$SLACK_WEBHOOK_URL"

# Verify AlertManager loaded secrets
docker-compose exec alertmanager amtool config show | grep -v YOUR
# Should NOT contain 'YOUR' placeholders

# Fire test alert
curl -X POST http://localhost:9093/api/v1/alerts \
  -d '[{"labels":{"alertname":"TestAlert","severity":"warning"}}]'
# Verify Slack notification received
```

### CI Guard

```yaml
# .github/workflows/validate-config.yml:
- name: Check for placeholder secrets in AlertManager
  run: |
    if grep -qE 'YOUR_|PLACEHOLDER|hooks.slack.com/services/T' alertmanager.yml; then
      echo "ERROR: Placeholder secrets found in alertmanager.yml"
      exit 1
    fi
```

### Definition of Done

- [ ] Slack webhook stored in GSM
- [ ] PagerDuty service key stored in GSM
- [ ] alertmanager.yml.tpl created with env var placeholders
- [ ] Secret fetch script updated
- [ ] CI guard added
- [ ] Test alert sent successfully to Slack

### Cross-References

- Related: #977 (Grafana placeholder config)
- Related: #965 (Observability)
