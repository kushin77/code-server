# Deployment Evidence Report

Date: 2026-04-22
Scope: Primary host deployment and PagerDuty routing verification

## Verified Outcomes

- Public edge burst against https://ide.kushnir.cloud completed successfully.
- Root path returned 403 for all 10 requests.
- /oauth2/start?rd=/ returned 302 for all 10 requests.
- Live Alertmanager container is healthy.
- Live Alertmanager config is loaded from /etc/alertmanager/alertmanager.yml.
- PagerDuty service key is present in the live host .env and rendered into the Alertmanager config on the host.

## Live Host Checks

- Alertmanager container: healthy
- Alertmanager config: rendered from the host deployment copy in /home/akushnir/code-server-enterprise-ops/config/alertmanager.yml
- PagerDuty routing: critical-alerts receiver configured with pagerduty_configs

## Validation Notes

- The Alertmanager logs show normal startup and readiness.
- The container also logs webhook retries to the local notification endpoint, which is expected for the existing default webhook receiver and does not block Alertmanager readiness.
- The public edge burst evidence was previously captured in artifacts/triage/public-edge-burst-evidence.md.

## Evidence References

- artifacts/triage/public-edge-burst-evidence.md
- /home/akushnir/code-server-enterprise-ops/config/alertmanager.yml on the primary host
- Alertmanager container status on the primary host
