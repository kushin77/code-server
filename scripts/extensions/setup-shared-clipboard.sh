#!/usr/bin/env bash
# @file scripts/extensions/setup-shared-clipboard.sh
# @module ide/shared-clipboard
# @description P3-1080 Phase 1: Shared clipboard extension setup
# @governance GOV-002: All clipboard state immutable and auditable

set -euo pipefail

echo "=== Shared Clipboard Extension Setup ==="

EXT_DIR="apps/extensions/shared-clipboard"
mkdir -p "$EXT_DIR/src" "$EXT_DIR/tests"

# Create package.json
cat > "$EXT_DIR/package.json" << 'EOF'
{
  "name": "shared-clipboard",
  "displayName": "Shared Clipboard",
  "description": "Cross-user paste history with search and organization",
  "version": "1.0.0",
  "engines": {
    "vscode": "^1.85.0"
  },
  "publisher": "elevated-iq",
  "categories": [
    "Other"
  ],
  "activationEvents": [
    "onCommand:sharedClipboard.openHistory",
    "onCommand:sharedClipboard.recordClip",
    "onStartupFinished"
  ],
  "main": "./dist/extension.js",
  "contributes": {
    "commands": [
      {
        "command": "sharedClipboard.openHistory",
        "title": "Open Shared Clipboard History",
        "category": "Clipboard"
      },
      {
        "command": "sharedClipboard.recordClip",
        "title": "Record Current Selection to Clipboard",
        "category": "Clipboard"
      },
      {
        "command": "sharedClipboard.clearHistory",
        "title": "Clear Clipboard History",
        "category": "Clipboard"
      },
      {
        "command": "sharedClipboard.shareClip",
        "title": "Share Clip with Team",
        "category": "Clipboard"
      }
    ],
    "keybindings": [
      {
        "command": "sharedClipboard.openHistory",
        "key": "ctrl+shift+v",
        "mac": "cmd+shift+v",
        "when": "editorFocus"
      },
      {
        "command": "sharedClipboard.recordClip",
        "key": "ctrl+shift+c",
        "mac": "cmd+shift+c",
        "when": "editorFocus"
      }
    ],
    "configuration": {
      "title": "Shared Clipboard",
      "properties": {
        "sharedClipboard.enabled": {
          "type": "boolean",
          "default": true,
          "description": "Enable/disable shared clipboard"
        },
        "sharedClipboard.historySize": {
          "type": "number",
          "default": 100,
          "minimum": 10,
          "maximum": 1000,
          "description": "Maximum number of clipboard entries to keep"
        },
        "sharedClipboard.autoRecord": {
          "type": "boolean",
          "default": true,
          "description": "Automatically record all clipboard changes"
        },
        "sharedClipboard.syncInterval": {
          "type": "number",
          "default": 5,
          "minimum": 1,
          "maximum": 60,
          "description": "Sync interval in seconds"
        }
      }
    }
  },
  "scripts": {
    "vscode:prepublish": "npm run esbuild-base -- --minify",
    "esbuild-base": "esbuild ./src/extension.ts --bundle --outfile=dist/extension.js --external:vscode --format=cjs --platform=node",
    "esbuild": "npm run esbuild-base -- --sourcemap",
    "esbuild-watch": "npm run esbuild-base -- --sourcemap --watch",
    "compile": "tsc -p ./",
    "test": "jest --coverage"
  },
  "devDependencies": {
    "@types/node": "^20.10.0",
    "@types/vscode": "^1.85.0",
    "@typescript-eslint/eslint-plugin": "^6.13.0",
    "@typescript-eslint/parser": "^6.13.0",
    "esbuild": "^0.19.11",
    "jest": "^29.7.0",
    "ts-jest": "^29.1.1",
    "typescript": "^5.3.3"
  },
  "dependencies": {
    "axios": "^1.6.0",
    "sqlite3": "^5.1.6"
  }
}
EOF

# Create tsconfig.json
cat > "$EXT_DIR/tsconfig.json" << 'EOF'
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
  "include": ["src"],
  "exclude": ["node_modules", "dist"]
}
EOF

# Create types
cat > "$EXT_DIR/src/types.ts" << 'EOF'
export interface ClipboardEntry {
  id: string;
  content: string;
  timestamp: string;
  userId: string;
  fileName?: string;
  language?: string;
  tags: string[];
  shared: boolean;
}

export interface ClipboardConfig {
  enabled: boolean;
  historySize: number;
  autoRecord: boolean;
  syncInterval: number;
}

export interface SharedClipboardEvent {
  type: "clip_added" | "clip_deleted" | "clip_shared" | "clip_unshared";
  clipId: string;
  timestamp: string;
  userId: string;
  data?: ClipboardEntry;
}
EOF

echo "✅ Extension structure created:"
echo "   - $EXT_DIR/package.json"
echo "   - $EXT_DIR/tsconfig.json"
echo "   - $EXT_DIR/src/types.ts"
echo ""
echo "Next: Implement storage layer (Phase 2)"
