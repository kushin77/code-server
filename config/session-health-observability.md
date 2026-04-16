# Session Health Observability & Metrics
# =======================================
# Issue #344: Prove session self-healing system is working in production
# This file defines the comprehensive observability contract for all session enhancements

---

# METRICS: All session lifecycle events
# ====================================

session_created_total{method="new_login|silent_refresh|grace_extension"}
  Description: Session creation counter
  Method:
    new_login: User authenticated via Google OAuth
    silent_refresh: Background refresh via proactive scheduler
    grace_extension: IdP unavailable, extended via grace window
  Example: session_created_total{method="silent_refresh"} == 1523

session_expired_total{cause="natural|invalidated|generation_mismatch|fp_mismatch"}
  Description: Session expiration counter
  Cause:
    natural: Normal expiry (24h TTL reached)
    invalidated: Logout or revocation
    generation_mismatch: New session schema deployed, old version rejected
    fp_mismatch: Device fingerprint mismatch (strict mode)
  Example: session_expired_total{cause="fp_mismatch"} == 3

session_replaced_total{reason="migration|refresh|forced"}
  Description: Session replacement counter
  Reason:
    migration: Schema upgrade (v1 → v3)
    refresh: Cookie rotated by proactive scheduler or silent refresh
    forced: Re-authentication required
  Example: session_replaced_total{reason="migration"} == 45

# Version distribution (gauge — point-in-time snapshot)
session_version_distribution{version="1|2|3"} gauge
  Description: Number of active sessions per schema version
  Usage: Track migration progress (want 0 v1/v2 sessions)
  Example: session_version_distribution{version="3"} == 8901

# Migration metrics
session_migration_total{from_version,to_version,result="success|error"}
  Description: Migration attempt counter
  Usage: Measure success rate and errors during schema upgrades
  Example: session_migration_total{from_version="1",to_version="3",result="success"} == 1200

session_migration_duration_seconds histogram
  Description: Latency of session migration in-place (should be <100ms)
  Percentiles: p50, p95, p99

# Grace window usage
session_stale_grace_active gauge
  Description: Number of sessions currently in grace window (IdP unreachable)
  Alert: If > 0 for > 5 minutes → check IdP health

session_stale_grace_used_total counter
  Description: How many times grace window was needed (IdP temporarily unavailable)

session_idp_health_check_result{provider,result="healthy|unreachable"} gauge
  Description: IdP health check result (Google OAuth endpoint)
  Usage: Track IdP availability independent of user impact

# Client-side refresh behavior
session_proactive_refresh_total{source="js_scheduler|service_worker",result="success|failure|rate_limited"}
  Description: Proactive refresh attempt counter
  Source:
    js_scheduler: Main thread JS scheduler (issue #333)
    service_worker: Background Service Worker (issue #336)
  Result:
    success: Cookie refreshed successfully
    failure: HTTP request failed (5xx, timeout, etc.)
    rate_limited: Rejected by rate limit (too many refreshes)
  Example: session_proactive_refresh_total{source="js_scheduler",result="success"} == 5840

session_forced_relogin_total{cause="expired|invalid|fp_mismatch|generation_mismatch"}
  Description: CRITICAL KPI — forced re-login count (should be near-zero)
  Cause:
    expired: Session naturally expired without refresh
    invalid: Session rejected as malformed/tampered
    fp_mismatch: Device fingerprint mismatch in strict mode
    generation_mismatch: Session from old schema version rejected
  Usage: Primary KPI for session self-healing system
  Alert: If > 0.1% of active sessions/hour → P2 incident
  Example: session_forced_relogin_total{cause="expired"} == 2

# Multi-tab coordination
session_broadcast_events_total{type="refreshed|expired|query"}
  Description: BroadcastChannel event counter (multi-tab sync)
  Type:
    refreshed: Tab A refreshed, broadcast to others
    expired: Tab detected expiry, signaled all tabs
    query: New tab querying existing tabs for state
  Example: session_broadcast_events_total{type="refreshed"} == 120

session_leader_elections_total{result="won|lost"}
  Description: Leader election outcomes in multi-tab scenario
  Usage: Verify only 1 tab refreshes per cycle (thundering herd prevention)
  Example: session_leader_elections_total{result="won"} == 45

# WebSocket session handoff
ws_session_handoff_total{result="success|failure|timeout"}
  Description: WebSocket graceful handoff during cookie rotation
  Result:
    success: Reconnected without visible interruption
    failure: Reconnect failed after retries
    timeout: Reconnect took > 500ms
  Example: ws_session_handoff_total{result="success"} == 892

ws_reconnect_latency_seconds histogram
  Description: WebSocket reconnection latency (should be <500ms)
  Percentiles: p50, p95, p99
  Alert: If p99 > 1s → session handoff is degrading

# Rate limiting
session_refresh_rate_limited_total{layer="caddy|oauth2_proxy|client"}
  Description: Rate limit hits on session refresh endpoints
  Layer:
    caddy: Reverse proxy rate limit
    oauth2_proxy: OAuth2-proxy middleware rate limit
    client: Client-side scheduler minimum interval
  Example: session_refresh_rate_limited_total{layer="client"} == 5

---

# ALERTS: Production session health
# ==================================

CRITICAL ALERTS:
- Session self-healing broken: Forced relogins > 0.1% per hour
- OAuth circuit breaker open: All token refresh attempts failing
- WebSocket reconnect degraded: p99 latency > 1 second
- Session grace window exceeded: Users approaching 2h grace limit without IdP recovery

WARNING ALERTS:
- Proactive refresh failure rate > 5% for 5 minutes
- Cookie version staleness > 30 minutes (old versions still active)
- Grace window active > 5 minutes (IdP unavailable)

---

# DASHBOARD: Session Health
# =========================
# Panels to create in Grafana:

1. Session Lifecycle Rate (time series)
   - Stacked area: session_created_total / session_expired_total / session_replaced_total
   - Usage: Detect anomalies in session churn

2. Forced Relogin Rate (gauge + sparkline)
   - Query: rate(session_forced_relogin_total[5m])
   - Target: < 0.001 (0.1% of active sessions per minute)
   - Color: Green (<0.1%), Yellow (0.1%-0.5%), Red (>0.5%)

3. Cookie Version Distribution (pie chart)
   - Query: session_version_distribution (by version label)
   - Usage: Track migration progress (want 100% on v3)

4. Proactive Refresh Success Rate (gauge)
   - Query: rate(session_proactive_refresh_total{result="success"}[5m]) / rate(session_proactive_refresh_total[5m])
   - Target: > 0.99 (99% success rate)

5. Grace Window Usage (time series)
   - Query: session_stale_grace_active (active users in grace window)
   - Context: Indicates IdP availability issues

6. IdP Health (status panel)
   - Query: session_idp_health_check_result{provider="google"}
   - Color: Green (healthy), Red (unreachable)

7. WebSocket Handoff Latency (histogram)
   - Query: ws_reconnect_latency_seconds
   - Percentiles: p50, p95, p99
   - Target: p99 < 500ms

8. Rate Limit Hits (time series)
   - Query: rate(session_refresh_rate_limited_total[5m]) by (layer)
   - Usage: Detect scheduler bugs causing thundering herd

---

# SLO: Session Self-Healing
# =========================

Service Level Objective (SLO):
  "99.9% of active sessions never experience forced re-login"

Service Level Indicator (SLI):
  session_forced_relogin_total / session_active_count (per hour)
  Target: < 0.1% per hour

Error Budget:
  Monthly: 99.9% uptime = ~43 minutes allowed forced relogins
  Weekly: 99.9% uptime = ~6 minutes allowed forced relogins
  Daily:  99.9% uptime = ~86 seconds allowed forced relogins

Burn Rate Alerts:
  - Fast burn (> 2x budget): Alert immediately (P1)
  - Slow burn (1-2x budget): Alert after 1 hour (P2)
  - Within budget: No alert needed

Recovery Procedures:
  1. If burn rate > 2x:
     - Disable session_migration_enabled immediately (kill-switch)
     - Restart all code-server containers with baseline config
     - Investigate root cause in logs
  2. If burn rate 1-2x:
     - Set session_fingerprint_mode to "monitor" (disable strict checking)
     - Increase stale_session_tolerance_hours to 4h temporarily
     - Monitor closely for next 30 minutes

---

# TESTING: Session Health Validation
# ==================================

Load Test Scenario:
  - 100 concurrent simulated users
  - Each user: login → idle 5min → perform action → idle 5min → logout
  - Measure: session_forced_relogin_total (should be 0)

Failure Scenario:
  - Simulate IdP unavailable (block Google OAuth API)
  - Verify: session_stale_grace_active increases, users continue working
  - Verify: session_idp_health_check_result = unreachable
  - After IdP recovery: sessions refresh to fresh state
  - Measure: No forced relogins during grace window

Multi-Tab Scenario:
  - Open 5 tabs simultaneously
  - Measure: session_leader_elections_total{result="won"} == 1 per refresh cycle
  - Verify: Only 1 tab makes refresh request (no thundering herd)

WebSocket Scenario:
  - Terminal running long-lived process
  - Trigger session refresh (wait for cookie rotation)
  - Measure: ws_session_handoff_total{result="success"}
  - Verify: Terminal output continues, no interruption

---

# IMPLEMENTATION CHECKLIST
# ========================

Infrastructure:
  [ ] Prometheus metrics endpoint for session middleware
  [ ] Structured logging: all session events emitted as JSON
  [ ] AlertManager rules for all critical alerts
  [ ] Grafana dashboards created and linked

Monitoring:
  [ ] Session health SLO dashboard added to main observability dashboard
  [ ] Daily report: forced_relogin_total for previous 24h
  [ ] Weekly trend: session version distribution graph
  [ ] On-call runbook: "Session Self-Healing Degradation"

Testing:
  [ ] Load test: 100 users, measure forced_relogin_total
  [ ] Failure test: IdP outage, verify grace window
  [ ] Multi-tab test: leader election working correctly
  [ ] WebSocket test: terminal survives session refresh

Education:
  [ ] On-call team trained on session health metrics
  [ ] Runbooks written for common alerts
  [ ] Post-mortems documented for any forced relogin incidents
