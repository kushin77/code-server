#!/usr/bin/env node
// @file        apps/extensions/kc-extension-pack/src/extension.ts
// @module      extensions/kc-extension-pack
// @description KC IDE Extension Pack — meta-extension for essential development tools
//
// This extension pack bundles 18+ pre-selected extensions for immediate productivity:
// - Git & GitHub integration (GitLens, GitHub PRs, Copilot)
// - Remote development (SSH, Live Share)
// - Code quality (ESLint, Prettier)
// - Infrastructure (Docker, Terraform)
// - Productivity tools
//

import * as vscode from 'vscode';

export function activate(context: vscode.ExtensionContext) {
  console.log('📦 KC IDE Extension Pack activated');

  // Register onboarding command
  context.subscriptions.push(
    vscode.commands.registerCommand('kcExtensionPack.openDocumentation', () => {
      showExtensionPackInfo(context);
    })
  );

  // Show welcome message on first activation
  const hasShownWelcome = context.globalState.get<boolean>('kcExtensionPack.welcomeShown', false);
  if (!hasShownWelcome) {
    showFirstTimeWelcome(context);
  }

  console.log('✅ KC IDE Extension Pack initialized');
}

async function showFirstTimeWelcome(context: vscode.ExtensionContext): Promise<void> {
  const message =
    '✅ KC IDE Extension Pack installed! 18 essential extensions are now available for your development workflow.';

  const action = await vscode.window.showInformationMessage(message, 'Learn More', 'Dismiss');

  if (action === 'Learn More') {
    await vscode.commands.executeCommand('kcExtensionPack.openDocumentation');
  }

  await context.globalState.update('kcExtensionPack.welcomeShown', true);
}

async function showExtensionPackInfo(context: vscode.ExtensionContext): Promise<void> {
  const panel = vscode.window.createWebviewPanel(
    'kcExtensionPack',
    'KC IDE Extension Pack',
    vscode.ViewColumn.One,
    { enableScripts: true }
  );

  panel.webview.html = `
    <!DOCTYPE html>
    <html>
    <head>
      <style>
        body { 
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
          padding: 20px;
          line-height: 1.6;
          color: #fff;
          background: #1e1e1e;
        }
        h1 { color: #667eea; margin-bottom: 20px; }
        h2 { color: #764ba2; margin-top: 30px; margin-bottom: 15px; }
        .category { margin-bottom: 25px; }
        .extension { margin: 8px 0; padding: 8px 12px; background: #2d2d2d; border-radius: 4px; }
        ul { margin: 10px 0; padding-left: 20px; }
        li { margin: 5px 0; }
        code { background: #2d2d2d; padding: 2px 6px; border-radius: 3px; font-family: monospace; }
      </style>
    </head>
    <body>
      <h1>📦 KC IDE Extension Pack</h1>
      <p>Essential extensions for KC IDE development, collaboration, and productivity.</p>

      <h2>🔍 Version Control & Git</h2>
      <div class="category">
        <div class="extension">• <strong>GitLens</strong> — Git supercharged in VS Code</div>
        <div class="extension">• <strong>GitHub Pull Requests</strong> — PR/issue integration</div>
        <div class="extension">• <strong>GitHub Theme</strong> — Official GitHub branding</div>
      </div>

      <h2>🤖 AI & Copilot</h2>
      <div class="category">
        <div class="extension">• <strong>GitHub Copilot</strong> — AI code generation</div>
        <div class="extension">• <strong>Copilot Chat</strong> — Conversational AI assistance</div>
      </div>

      <h2>👥 Remote Development & Collaboration</h2>
      <div class="category">
        <div class="extension">• <strong>Remote - SSH</strong> — Connect to remote machines</div>
        <div class="extension">• <strong>Remote - SSH: Editing Config Files</strong> — SSH config support</div>
        <div class="extension">• <strong>Live Share</strong> — Real-time collaboration</div>
        <div class="extension">• <strong>Live Share Audio</strong> — Voice during sessions</div>
        <div class="extension">• <strong>Live Share Extension Pack</strong> — Enhanced collaboration</div>
      </div>

      <h2>🎨 Code Quality & Formatting</h2>
      <div class="category">
        <div class="extension">• <strong>Prettier</strong> — Code formatter (JavaScript, TypeScript, CSS)</div>
        <div class="extension">• <strong>ESLint</strong> — JavaScript/TypeScript linting</div>
      </div>

      <h2>🔧 Infrastructure & DevOps</h2>
      <div class="category">
        <div class="extension">• <strong>Docker</strong> — Docker management and debugging</div>
        <div class="extension">• <strong>Terraform</strong> — Infrastructure as Code support</div>
        <div class="extension">• <strong>Makefile Tools</strong> — Makefile integration</div>
      </div>

      <h2>📝 Data & Configuration</h2>
      <div class="category">
        <div class="extension">• <strong>JSON Editor</strong> — Advanced JSON editing</div>
        <div class="extension">• <strong>Even Better TOML</strong> — TOML language support</div>
        <div class="extension">• <strong>Object Viewer</strong> — Visual object inspection</div>
      </div>

      <h2>🔌 Utilities</h2>
      <div class="category">
        <div class="extension">• <strong>Serial Port Monitor</strong> — Serial communication</div>
      </div>

      <h2>✨ Getting Started</h2>
      <ul>
        <li>All 18+ extensions are now installed and ready to use</li>
        <li>Check Extensions view (Ctrl+Shift+X) to see them all</li>
        <li>Some extensions may require sign-in (GitHub Copilot, etc.)</li>
        <li>Configure settings in <code>.vscode/settings.json</code></li>
      </ul>

      <h2>📚 Documentation</h2>
      <ul>
        <li><a href="https://github.com/kushin77/code-server">Code Server Repository</a></li>
        <li><a href="https://code.visualstudio.com/docs/editor/extension-marketplace">VS Code Extensions Marketplace</a></li>
      </ul>
    </body>
    </html>
  `;
}

export function deactivate() {
  console.log('KC IDE Extension Pack deactivated');
}
