#!/bin/bash
# @file scripts/extensions/setup-statusbar-tiles.sh
# @module ide/vscode-extensions
# @description P3-1055 Phase 1: Setup VS Code status bar tiles extension
# @governance GOV-002: Extension provides team context visibility in IDE
# @usage setup-statusbar-tiles.sh [--install]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source canonical configuration (SSOT)
source "${SCRIPT_DIR}/../_common/init.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
EXTENSION_DIR="${REPO_ROOT}/apps/extensions/statusbar-tiles"

log_info() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [INFO] $*"
}

log_success() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [SUCCESS] $*"
}

# Create extension directory structure
setup_extension_structure() {
  log_info "Setting up extension directory structure..."
  
  mkdir -p "${EXTENSION_DIR}"/{src,dist,test,media}
  mkdir -p "${EXTENSION_DIR}/.vscode-test"
  
  log_success "Extension structure created"
}

# Generate package.json
generate_package_json() {
  log_info "Generating package.json..."
  
  cat > "${EXTENSION_DIR}/package.json" <<'EOF'
{
  "name": "statusbar-tiles",
  "displayName": "Team Status Bar Tiles",
  "description": "Real-time team metrics in VS Code status bar",
  "version": "1.0.0",
  "publisher": "elevatediq",
  "license": "MIT",
  "engines": {
    "vscode": "^1.85.0"
  },
  "categories": [
    "Other"
  ],
  "activationEvents": [
    "onStartupFinished"
  ],
  "main": "./dist/extension.js",
  "contributes": {
    "commands": [
      {
        "command": "statusbar-tiles.refreshTiles",
        "title": "Refresh Team Status Tiles"
      },
      {
        "command": "statusbar-tiles.openSettings",
        "title": "Configure Status Tiles"
      }
    ],
    "configuration": {
      "title": "Status Bar Tiles",
      "properties": {
        "statusbar-tiles.enabled": {
          "type": "boolean",
          "default": true,
          "description": "Enable status bar tiles"
        },
        "statusbar-tiles.refreshInterval": {
          "type": "number",
          "default": 60,
          "minimum": 10,
          "description": "Refresh interval in seconds"
        },
        "statusbar-tiles.tileOrder": {
          "type": "array",
          "default": ["pr", "ci", "incidents", "team-online"],
          "description": "Order of tiles in status bar",
          "items": {
            "type": "string",
            "enum": ["pr", "ci", "incidents", "team-online"]
          }
        },
        "statusbar-tiles.githubToken": {
          "type": "string",
          "default": "",
          "description": "GitHub API token for fetching PRs",
          "markdownDescription": "GitHub API token (stored securely in VS Code keyring)"
        },
        "statusbar-tiles.ciEndpoint": {
          "type": "string",
          "default": "",
          "description": "CI system endpoint (e.g., GitHub Actions, CircleCI)"
        },
        "statusbar-tiles.pagerdutyToken": {
          "type": "string",
          "default": "",
          "description": "PagerDuty API token for incidents"
        }
      }
    }
  },
  "scripts": {
    "build": "esbuild src/extension.ts --bundle --outfile=dist/extension.js --external:vscode",
    "dev": "npm run build -- --watch",
    "lint": "eslint src --fix",
    "test": "node --loader tsx ./test/runTest.ts"
  },
  "dependencies": {
    "axios": "^1.6.0"
  },
  "devDependencies": {
    "@types/vscode": "^1.85.0",
    "@types/node": "^20.0.0",
    "esbuild": "^0.20.0",
    "typescript": "^5.3.0",
    "eslint": "^8.0.0"
  }
}
EOF
  
  log_success "package.json created"
}

# Generate tsconfig.json
generate_tsconfig() {
  log_info "Generating tsconfig.json..."
  
  cat > "${EXTENSION_DIR}/tsconfig.json" <<'EOF'
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "commonjs",
    "lib": ["ES2020"],
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
EOF
  
  log_success "tsconfig.json created"
}

# Generate main extension file structure
generate_extension_types() {
  log_info "Generating extension types..."
  
  cat > "${EXTENSION_DIR}/src/types.ts" <<'EOF'
// Status bar tile configuration and types

export interface TileConfig {
  type: "pr" | "ci" | "incidents" | "team-online";
  enabled: boolean;
  refreshInterval: number;
}

export interface StatusTileData {
  icon: string;
  label: string;
  tooltip: string;
  color?: "green" | "yellow" | "red";
  count?: number;
  command?: string;
}

export interface PRTile extends StatusTileData {
  type: "pr";
  unreadReviews: number;
  assignedPRs: number;
}

export interface CITile extends StatusTileData {
  type: "ci";
  status: "passing" | "failing" | "pending";
  branch: string;
  failureCount: number;
}

export interface IncidentTile extends StatusTileData {
  type: "incidents";
  activeIncidents: number;
  severity: "critical" | "high" | "medium" | "low";
}

export interface TeamOnlineTile extends StatusTileData {
  type: "team-online";
  onlineCount: number;
  totalTeamSize: number;
}
EOF
  
  log_success "Extension types created"
}

main() {
  local install=false
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --install)
        install=true
        shift
        ;;
      *)
        shift
        ;;
    esac
  done
  
  log_info "Setting up Status Bar Tiles extension for VS Code..."
  
  setup_extension_structure
  generate_package_json
  generate_tsconfig
  generate_extension_types
  
  if [[ "${install}" == "true" ]]; then
    log_info "Installing dependencies..."
    cd "${EXTENSION_DIR}"
    npm install
    npm run build
    log_success "Extension built successfully"
  fi
  
  log_success "Status bar tiles extension setup complete"
  log_info "To develop: cd ${EXTENSION_DIR} && npm run dev"
}

main "$@"