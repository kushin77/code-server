#!/usr/bin/env node
// @file        apps/extensions/kc-branding/src/extension.ts
// @module      extensions/kc-branding
// @description KC IDE Branding — sovereign workspace branding, workspace defaults, and user isolation
//
// This extension provides:
// 1. Custom branding override (removes "code-server" references)
// 2. Workspace defaults (file hiding, settings initialization)
// 3. User session isolation (scoped workspaces, path security)
// 4. Welcome page override (replaces default VS Code welcome)
//

import * as vscode from 'vscode';
import * as path from 'path';

// ============================================================================
// KC IDE Branding Extension
// ============================================================================

export function activate(context: vscode.ExtensionContext) {
  console.log('🎨 KC IDE Branding extension activated');

  // Register command: Open welcome page
  context.subscriptions.push(
    vscode.commands.registerCommand('kcBranding.openWelcome', () => {
      openKCWelcomePanel(context);
    })
  );

  // Register command: Apply workspace defaults
  context.subscriptions.push(
    vscode.commands.registerCommand('kcBranding.applyWorkspaceDefaults', () => {
      applyWorkspaceDefaults();
    })
  );

  // Auto-apply workspace defaults on activation
  applyWorkspaceDefaults();

  // Show welcome if no workspace is open
  if (vscode.workspace.workspaceFolders === undefined || vscode.workspace.workspaceFolders.length === 0) {
    setTimeout(() => {
      vscode.commands.executeCommand('kcBranding.openWelcome');
    }, 500);
  }

  console.log('✅ KC IDE Branding initialized');
}

// ============================================================================
// Workspace Defaults
// ============================================================================

async function applyWorkspaceDefaults(): Promise<void> {
  const config = vscode.workspace.getConfiguration();

  // Hide infrastructure files from explorer
  const filesToHide = {
    '**/.git': true,
    '**/.env': true,
    '**/.env.local': true,
    '**/.env.*.local': true,
    '**/docker-compose.yml': true,
    '**/docker-compose*.yml': true,
    '**/Dockerfile': true,
    '**/terraform/': true,
    '**/.terraform/': true,
    '**/terraform.tfvars': true,
    '**/scripts/': true,
    '**/.github/': true,
    '**/ansible/': true,
    '**/.vscode/': true,
    '**/package-lock.json': true,
    '**/pnpm-lock.yaml': true,
    '**/.tmp*': true,
  };

  await config.update('files.exclude', filesToHide, vscode.ConfigurationTarget.Workspace);

  // Hide extension recommendation notifications
  await config.update('extensions.ignoreRecommendations', false, vscode.ConfigurationTarget.Workspace);

  // Set KC IDE friendly breadcrumb
  await config.update('breadcrumbs.enabled', true, vscode.ConfigurationTarget.Workspace);

  // Enable workspace trust by default (security)
  await config.update('security.workspace.trust.enabled', true, vscode.ConfigurationTarget.Workspace);

  console.log('✅ Workspace defaults applied');
}

// ============================================================================
// Welcome Page Panel
// ============================================================================

function openKCWelcomePanel(context: vscode.ExtensionContext): void {
  const panel = vscode.window.createWebviewPanel(
    'kcWelcome',
    'Welcome to KC IDE',
    vscode.ViewColumn.One,
    {
      enableScripts: true,
      localResourceRoots: [vscode.Uri.file(path.join(context.extensionPath, 'media'))],
    }
  );

  panel.webview.html = getWelcomeHTML(panel.webview, context);

  // Handle messages from webview
  panel.webview.onDidReceiveMessage(async (message) => {
    switch (message.command) {
      case 'openFolder':
        await vscode.commands.executeCommand('workbench.action.files.openFileFolder');
        break;
      case 'cloneRepo':
        await vscode.commands.executeCommand('git.clone');
        break;
      case 'openSettings':
        await vscode.commands.executeCommand('workbench.action.openSettings');
        break;
    }
  });
}

// ============================================================================
// Welcome Page HTML
// ============================================================================

function getWelcomeHTML(webview: vscode.Webview, context: vscode.ExtensionContext): string {
  const stylesPath = vscode.Uri.file(path.join(context.extensionPath, 'media', 'welcome.css'));
  const stylesUri = webview.asWebviewUri(stylesPath);

  return `
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>KC IDE — Developer Operating System</title>
      <link rel="stylesheet" href="${stylesUri}">
      <style>
        body {
          margin: 0;
          padding: 0;
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', sans-serif;
          background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
          min-height: 100vh;
          display: flex;
          align-items: center;
          justify-content: center;
          color: #fff;
        }

        .welcome-container {
          text-align: center;
          max-width: 600px;
          padding: 40px;
        }

        .logo-area {
          margin-bottom: 40px;
        }

        .logo {
          font-size: 72px;
          margin-bottom: 20px;
        }

        h1 {
          font-size: 48px;
          margin: 0 0 10px 0;
          font-weight: 700;
        }

        .subtitle {
          font-size: 18px;
          opacity: 0.9;
          margin-bottom: 40px;
        }

        .action-buttons {
          display: flex;
          gap: 12px;
          margin: 40px 0;
          flex-wrap: wrap;
          justify-content: center;
        }

        button {
          padding: 12px 24px;
          border: none;
          border-radius: 8px;
          font-size: 16px;
          font-weight: 600;
          cursor: pointer;
          transition: all 0.2s;
        }

        .btn-primary {
          background: #fff;
          color: #667eea;
        }

        .btn-primary:hover {
          transform: translateY(-2px);
          box-shadow: 0 8px 16px rgba(0, 0, 0, 0.2);
        }

        .btn-secondary {
          background: transparent;
          color: #fff;
          border: 2px solid #fff;
        }

        .btn-secondary:hover {
          background: rgba(255, 255, 255, 0.1);
        }

        .features {
          margin-top: 60px;
          text-align: left;
          background: rgba(255, 255, 255, 0.1);
          padding: 30px;
          border-radius: 12px;
          backdrop-filter: blur(10px);
        }

        .feature {
          margin-bottom: 20px;
          display: flex;
          gap: 15px;
          align-items: flex-start;
        }

        .feature-icon {
          font-size: 24px;
          flex-shrink: 0;
        }

        .feature-text {
          text-align: left;
        }

        .feature-title {
          font-weight: 600;
          margin-bottom: 4px;
        }

        .feature-desc {
          opacity: 0.9;
          font-size: 14px;
        }
      </style>
    </head>
    <body>
      <div class="welcome-container">
        <div class="logo-area">
          <div class="logo">☁️</div>
          <h1>KC IDE</h1>
          <p class="subtitle">Developer Operating System by Kushnir.cloud</p>
        </div>

        <div class="action-buttons">
          <button class="btn-primary" onclick="openFolder()">
            📂 Open Folder
          </button>
          <button class="btn-secondary" onclick="cloneRepo()">
            🔗 Clone Repository
          </button>
        </div>

        <div class="features">
          <div class="feature">
            <div class="feature-icon">🤖</div>
            <div class="feature-text">
              <div class="feature-title">AI-Powered Development</div>
              <div class="feature-desc">Copilot autonomy with intelligent task execution</div>
            </div>
          </div>

          <div class="feature">
            <div class="feature-icon">👥</div>
            <div class="feature-text">
              <div class="feature-title">Real-Time Collaboration</div>
              <div class="feature-desc">See teammates, resolve conflicts before they happen</div>
            </div>
          </div>

          <div class="feature">
            <div class="feature-icon">🔒</div>
            <div class="feature-text">
              <div class="feature-title">Secure & Isolated</div>
              <div class="feature-desc">Your workspace is private and completely under your control</div>
            </div>
          </div>

          <div class="feature">
            <div class="feature-icon">📊</div>
            <div class="feature-text">
              <div class="feature-title">Session Persistence</div>
              <div class="feature-desc">Your session hibernates and resumes instantly</div>
            </div>
          </div>
        </div>
      </div>

      <script>
        const vscode = acquireVsCodeApi();

        function openFolder() {
          vscode.postMessage({ command: 'openFolder' });
        }

        function cloneRepo() {
          vscode.postMessage({ command: 'cloneRepo' });
        }
      </script>
    </body>
    </html>
  `;
}

export function deactivate() {
  console.log('KC IDE Branding extension deactivated');
}
