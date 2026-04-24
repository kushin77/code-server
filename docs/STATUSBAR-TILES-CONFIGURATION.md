#!/bin/bash
# @file docs/STATUSBAR-TILES-CONFIGURATION.md
# @module documentation/extensions
# @description Configuration guide for status bar tiles extension

# Status Bar Tiles Configuration Guide

## Installation

```bash
cd apps/extensions/statusbar-tiles
npm install
npm run build
```

## Configuration

Edit VS Code settings (`settings.json`) or use the Settings UI:

```json
{
  "statusbar-tiles.enabled": true,
  "statusbar-tiles.refreshInterval": 60,
  "statusbar-tiles.tileOrder": ["pr", "ci", "incidents", "team-online"],
  "statusbar-tiles.githubToken": "ghp_xxxxxxxxxxxx",
  "statusbar-tiles.ciEndpoint": "https://github.com/kushin77/code-server/actions",
  "statusbar-tiles.pagerdutyToken": "u+xxxxxxxxxxxx"
}
```

## Tile Types

### PR Tile
- Shows count of open PRs assigned to you
- Badge shows unread review requests
- Click to open GitHub PR list
- Green: no PRs, Yellow: review requests pending, Red: unreviewed

### CI Tile
- Shows current branch CI status (passing/failing)
- Updates every 60 seconds
- Click to open CI logs in IDE panel
- Green: all tests passing, Red: failed tests

### Incidents Tile
- Shows active PagerDuty incidents
- Color codes by severity
- Click to open incident browser
- Red: critical/high, Yellow: medium, Green: low/none

### Team Online Tile
- Shows team members currently online
- Format: X/Y online
- Click to see detailed online status
- Green: >75% team online, Yellow: 50-75%, Red: <50%

## Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | boolean | true | Enable/disable tiles |
| `refreshInterval` | number | 60 | Refresh interval in seconds (min 10) |
| `tileOrder` | array | ["pr", "ci", "incidents", "team-online"] | Tile display order |
| `githubToken` | string | "" | GitHub API token for PR data |
| `ciEndpoint` | string | "" | CI system endpoint |
| `pagerdutyToken` | string | "" | PagerDuty API token |

## Performance Tuning

### Caching
All API responses are cached for 60 seconds to minimize API calls.

### Refresh Interval
- Minimum 10 seconds to prevent API rate limiting
- Default 60 seconds balances freshness and performance
- Increase for slower networks

### Tile Selection
Disable unused tiles in `tileOrder` to reduce API calls:

```json
"statusbar-tiles.tileOrder": ["pr", "ci"]
```

## Troubleshooting

### Tiles not updating
1. Check API tokens are configured correctly
2. Verify endpoints are accessible
3. Check VS Code output for errors: `View → Output → Status Bar Tiles`

### High API usage
1. Increase refresh interval
2. Disable unused tiles
3. Check for rate limiting errors

### CI logs won't open
1. Verify CI endpoint configuration
2. Check browser can access CI system
3. Review VS Code webview security settings

## Development

### Building
```bash
npm run dev      # Watch mode
npm run build    # Production build
npm run lint     # Run linter
```

### Testing
```bash
npm test
```

### Debugging
1. Open extension debug terminal: F5
2. Set breakpoints in source
3. Check Console output in VS Code
