# AlertManager Configuration Consolidation

**Date**: 2026-04-18  
**Phase**: Elite Master Enhancement Phase 1 - SSOT Consolidation

## Overview

Three AlertManager configuration variants have been consolidated into a single `alertmanager.tpl` Terraform template to establish a Single Source Of Truth (SSOT) for alert routing and notification management.

## Files Consolidated

### Source Files (Deprecated - Archived Here)
1. **alertmanager-base.yml** 
   - Shared route structure
   - Severity-based alert grouping
   - Inhibit rules to prevent cascading notifications
   - Status: Kept as reference only (non-functional after consolidation)

2. **alertmanager.default.yml**
   - Development/default channel routing
   - Slack-only notifications
   - Basic PagerDuty integration
   - Status: Replaced by template

3. **alertmanager-production.yml**
   - Production multi-channel routing
   - Vault-based secret integration
   - Email digest capability
   - PagerDuty + Slack multi-channel
   - Status: Replaced by template

### Target File (New SSOT)
- **alertmanager.tpl** - Terraform template with environment-specific variable substitution
  - Consolidates all three variants
  - Supports dev/staging/production via template variables
  - Generated at Terraform apply: `config/alertmanager.yml`
  - Maintains all routing, receivers, and inhibit rules

## Key Improvements

### Before Consolidation
- 3+ configuration files causing maintenance overhead
- Unclear which config applied to which environment
- Risk of inconsistent alert routing
- Manual updates required to multiple files

### After Consolidation
- Single template (alertmanager.tpl) as SSOT
- Environment-specific values via Terraform variables
- Automatic generation at deploy time
- Version control for all variants in template structure
- Consistent alert routing across all environments

## Template Variables

Terraform substitutes these at apply time:

**Required:**
- `alertmanager_slack_webhook` - Slack API webhook URL (from Vault)
- `pagerduty_service_key` - PagerDuty integration key (from Vault/GSM)
- `slack_channel_critical`, `slack_channel_incidents`, `slack_channel_warnings`, `slack_channel_default`
- `email_recipient_low`, `email_smtp_host`, `email_smtp_port`, `email_smtp_user`, `email_smtp_password`

**Optional (Defaults Provided):**
- `default_receiver` - Default fallback receiver
- `group_wait_default` - Initial grouping timeout (seconds)
- `group_interval_default` - Grouping interval (minutes)
- `repeat_interval_default` - Repeat interval (hours)

## Usage

```bash
# Apply with dev variables
terraform apply -var-file=terraform.dev.tfvars

# Apply with production variables
terraform apply -var-file=terraform.prod.tfvars

# Generated output
# → config/alertmanager.yml
```

## Verification

Run validation script to verify consolidation completeness:

```bash
bash scripts/validate-config-ssot.sh
```

Expected output:
```
✅ alertmanager.tpl: Valid YAML template
✅ alertmanager-base.yml: Present (reference only)
✅ No orphaned AlertManager configs
✅ All Terraform variables documented
✅ Consolidation SSOT Status: OK
```

## Rollback (If Needed)

If issues arise with the template, restore individual configs:
```bash
git checkout alertmanager-production.yml alertmanager.default.yml
git checkout HEAD -- alertmanager.tpl
```

## Related Documentation

- ADR-002: Configuration Composition Pattern - `/ADR-002-CONFIGURATION-COMPOSITION-PATTERN.md`
- IaC SSOT Policy - `/ELITE-INFRASTRUCTURE-COMPLETION.md`
- Alert Rules - `/alert-rules.yml` (consolidated, non-templated)
