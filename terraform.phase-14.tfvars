# terraform.tfvars — Phase 14 Production Deployment Configuration
# 
# Usage: terraform apply -var-file=terraform.phase-14.tfvars
# Or inline: terraform apply -var='phase_14_enabled=true'
#
# WARNING: This file controls PRODUCTION DEPLOYMENT
# Only modify with explicit approval from DevOps lead

# ──────────────────────────────────────────────────────────────────────────────
# PHASE 14: CANARY DEPLOYMENT PROGRESSION
# ──────────────────────────────────────────────────────────────────────────────

# Stage 1: Initial canary (10% of traffic)
# Once SLOs validated for 60 min → Proceed to Stage 2
phase_14_enabled           = true
phase_14_canary_percentage = 10

# ──────────────────────────────────────────────────────────────────────────────
# PRODUCTION INFRASTRUCTURE TARGETS
# ──────────────────────────────────────────────────────────────────────────────

production_primary_host = "192.168.168.31" # New primary (code-server-31)
production_standby_host = "192.168.168.30" # Rollback target (code-server-30)

# ──────────────────────────────────────────────────────────────────────────────
# SERVICE LEVEL OBJECTIVE TARGETS (Phase 13 Baseline + Buffer)
# ──────────────────────────────────────────────────────────────────────────────

slo_target_p99_latency_ms   = 100  # Phase 13 baseline: 42-89ms
slo_target_error_rate_pct   = 0.1  # Phase 13 baseline: 0.0%
slo_target_availability_pct = 99.9 # Phase 13 baseline: 99.98%

# ──────────────────────────────────────────────────────────────────────────────
# SAFETY MECHANISMS
# ──────────────────────────────────────────────────────────────────────────────

enable_auto_rollback = true # Automatic rollback on SLO breach

# ──────────────────────────────────────────────────────────────────────────────
# VALIDATION
# ──────────────────────────────────────────────────────────────────────────────
#
# Before applying, verify:
#   1. Phase 13 Day 2 load test PASSING (all SLOs met for 24h)
#   2. Standby host (192.168.168.30) healthy and in sync
#   3. Team sign-offs complete (PO, DevOps, Performance, Ops)
#   4. Rollback procedures tested and verified
#   5. On-call engineer monitoring capacity confirmed
#
# Deployment timeline:
#   - Stage 1 (10%):  Commit this tfvars, run terraform apply
#   - Wait 60 min:    Monitor metrics, logs, user feedback
#   - Stage 2 (50%):  Update phase_14_canary_percentage = 50, terraform apply
#   - Wait 60 min:    Monitor metrics, logs, user feedback
#   - Stage 3 (100%): Update phase_14_canary_percentage = 100, terraform apply
#   - Observe 24h:    Monitor production metrics
#
# Total Duration: ~3-4 hours active + 24-hour observation = ~1.5 days

oauth2_proxy_cookie_secret = "72ZO5wAvWDtiygXQYZEu5WlUEjvjrilD"
