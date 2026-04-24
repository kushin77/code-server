# Feature Flag Management Panel - Implementation Guide

## Overview

This document describes the implementation of the **Feature Flag Management Panel** (Collab-9.6), which enables teams to manage feature flags directly within VS Code with support for LaunchDarkly, Unleash, and local flag definitions.

## Features

- ✅ **Local Flag Management**: Create, toggle, and delete flags
- ✅ **LaunchDarkly Integration**: Connect cloud-based feature flag service
- ✅ **Unleash Integration**: Connect self-hosted feature flag service
- ✅ **Multi-Environment Support**: Target different environments
- ✅ **Targeting Rules**: User segments, percentage rollouts, custom rules
- ✅ **Real-Time Updates**: Live flag status in sidebar
- ✅ **Import/Export**: Backup and restore flag configurations
- ✅ **Search & Filter**: Find flags by name or provider
- ✅ **Analytics**: Track flag evaluation metrics

## Setup

### Step 1: Local Flags Only (No External Providers)

This is the default setup. Flags are stored locally:

**VS Code Settings**:
```json
{
  "featureFlags.environment": "production"
}
```

**Environment Variables**:
```bash
FEATURE_FLAGS_JSON='{"new_dashboard": true, "beta_chat": false}'
```

### Step 2: Add LaunchDarkly

1. Go to [LaunchDarkly](https://launchdarkly.com)
2. Sign up and create project
3. Get API token from Account Settings
4. Configure in VS Code:

```json
{
  "featureFlags.launchDarklyToken": "api-XXX-XXX",
  "featureFlags.environment": "production"
}
```

### Step 3: Add Unleash

1. Deploy Unleash server:
```bash
docker run -p 4242:4242 unleashorg/unleash-server:latest
```

2. Get API token from Unleash UI

3. Configure in VS Code:
```json
{
  "featureFlags.unleashUrl": "http://localhost:4242",
  "featureFlags.environment": "production"
}
```

### Step 4: Multiple Providers

All providers can be active simultaneously:

```json
{
  "featureFlags.launchDarklyToken": "api-XXX",
  "featureFlags.unleashUrl": "http://localhost:4242",
  "featureFlags.environment": "production"
}
```

The client automatically merges flags from all providers.

## Usage

### Viewing Flags

1. Open **Feature Flags** panel in Explorer
2. See all flags (local + external)
3. Filtered by provider or search term

### Toggling Flags

- Click checkbox to enable/disable
- Green = enabled, Gray = disabled
- Changes apply immediately

### Creating New Flags

1. Enter flag name in input
2. Click "Create" or press Enter
3. New flag appears in list (disabled by default)
4. Exported to environment variables

### Deleting Flags

1. Click "Delete" button
2. Confirm in dialog
3. Flag removed from all scopes

### Searching Flags

- Type in search box
- Filters by name or key
- Results update in real-time

### Exporting Flags

1. Click "Export" button
2. JSON opens in VS Code editor
3. Copy to save or backup
4. Format:
```json
{
  "feature_name": true,
  "beta_feature": false
}
```

## API Reference

### Backend Methods

| Method | Description |
|--------|-------------|
| `evaluateFlag(key, userId, context)` | Check if flag is enabled |
| `listFlags()` | Get all flags |
| `toggleFlag(key, enabled)` | Enable/disable flag |
| `createFlag(key, name, description)` | Create new flag |
| `deleteFlag(key)` | Delete flag |
| `getFlagTargeting(key)` | Get targeting rules |
| `updateFlagTargeting(key, targeting)` | Update rules |
| `getFlagAnalytics(key)` | Get usage stats |
| `exportFlags()` | Export as JSON |
| `importFlags(flags)` | Import from JSON |

### Frontend API

```bash
GET  /api/flags                  # List all flags
POST /api/flags                  # Create new flag
PUT  /api/flags/{key}            # Update flag
DELETE /api/flags/{key}          # Delete flag
GET  /api/flags/{key}/targeting  # Get targeting rules
PUT  /api/flags/{key}/targeting  # Update targeting
GET  /api/flags/export           # Export flags
POST /api/flags/import           # Import flags
GET  /api/flags/{key}/analytics  # Get analytics
```

## Targeting Configuration

### User Targeting

```json
{
  "key": "new_feature",
  "targeting": {
    "users": ["user@example.com", "another@example.com"]
  }
}
```

### Segment Targeting

```json
{
  "targeting": {
    "segments": ["beta_testers", "employees"]
  }
}
```

### Percentage Rollout

```json
{
  "targeting": {
    "percentage": 25  // 25% of users
  }
}
```

### Combined Rules

```json
{
  "targeting": {
    "users": ["admin@example.com"],
    "segments": ["internal"],
    "percentage": 50
  }
}
```

## Provider Priority

When multiple providers are active, flags are merged in order:

1. **Local Flags** (highest priority)
2. **LaunchDarkly** 
3. **Unleash**

If a flag exists in multiple providers, local flag state is used.

## Analytics Dashboard

View flag performance:

```
Flag: new_dashboard
├─ Status: Enabled
├─ Provider: local
├─ Evaluations: 15,243
├─ Success Rate: 99.8%
├─ Last Evaluated: Just now
└─ Variation: on

Top Performers:
1. new_dashboard (15,243 evals)
2. beta_chat (8,921 evals)
3. experimental_api (4,532 evals)
```

## Environment Variables

### Configuration

| Variable | Description | Example |
|----------|-------------|---------|
| `FEATURE_FLAGS_JSON` | Local flags definition | `{"flag1": true}` |
| `FEATURE_FLAGS_ENVIRONMENT` | Target environment | `production` |
| `LAUNCHDARKLY_TOKEN` | LaunchDarkly API token | `api-XXX` |
| `UNLEASH_URL` | Unleash server URL | `http://localhost:4242` |
| `FEATURE_FLAGS_CACHE_TTL` | Cache duration (ms) | `30000` |

## Best Practices

### Flag Naming

- Use lowercase with underscores: `new_dashboard`
- Descriptive names: `enable_beta_chat` not `flag_1`
- Include feature area: `auth_social_login`

### Gradual Rollouts

1. Create flag (disabled)
2. Enable for specific users
3. Increase percentage
4. Enable for all
5. Monitor metrics
6. Clean up after deprecation

### Clean Up

- Archive flags after 30 days
- Remove feature flag code after 6 months
- Document flag lifetime in comments

### Security

- Don't store sensitive data in flag keys
- Use environment variables for tokens
- Restrict flag modification to admins
- Audit flag changes

## Troubleshooting

### Issue: "Failed to load flags"

**Solutions**:
1. Check network connectivity
2. Verify API tokens
3. Check environment configuration
4. Restart VS Code

### Issue: "Flag not toggling"

**Solutions**:
1. Check flag provider (local flags only for now)
2. Verify API permissions
3. Clear cache in settings
4. Check flag exists

### Issue: "LaunchDarkly/Unleash not connecting"

**Solutions**:
1. Verify API token/URL in settings
2. Check server is running
3. Verify network access
4. Check firewall rules

## Integration Points

### With Build Pipeline

Export flags before build:

```bash
npm run flags:export > flags.json
npm run build -- --flags=flags.json
```

### With Deployment

Sync flags to production:

```bash
npm run flags:export | upload-to-production
```

### With Monitoring

Track flag impact on metrics:

```bash
# Grafana dashboard
SELECT errors WHERE flag_enabled = true
```

## Performance

### Caching

- Flag lists: 30 seconds
- Individual flag: 30 seconds
- Targeting rules: 60 seconds

### Optimization

- Lazy load flag details
- Batch flag evaluations
- Debounce API calls
- Compress responses

## Related Issues

- **#1164**: EPIC [Collab-9] GitHub Integration Hub
- **#1165**: [Collab-9.1] Ticket Linking
- **#1166**: [Collab-9.2] Slack Slash Command
- **#1167**: [Collab-9.3] CI/CD Status Sidebar
- **#1168**: [Collab-9.4] Figma Design Embed
- **#1169**: [Collab-9.5] Sentry Error Tracking

---

**Implementation Status**: ✅ COMPLETE  
**Last Updated**: 2026-04-20  
**Owner**: Engineering Team
