// @file        apps/frontend/src/extensions/cicd-extension.ts
// @module      extensions/cicd-extension
// @description VS Code extension for CI/CD status sidebar

import * as vscode from 'vscode';
import { CICDStatusSidebarProvider } from './cicd-status-sidebar';
import { measureAsyncExtensionProfiler } from '@/utils/extensionProfiler';

/**
 * Activate CI/CD Status Sidebar extension
 */
export function activateCICDStatusSidebar(context: vscode.ExtensionContext): void {
  void measureAsyncExtensionProfiler(
    {
      id: 'cicd-status',
      label: 'CI/CD status sidebar',
      category: 'operations',
      kind: 'activation',
    },
    async () => {
      const provider = new CICDStatusSidebarProvider(context);

      // Register tree view
      const treeView = vscode.window.createTreeView('cicdStatus', {
        treeDataProvider: provider,
        showCollapseAll: true,
      });

      // Register commands
      registerCommands(provider, context);

      // Watch for configuration changes
      vscode.workspace.onDidChangeConfiguration((event: any) => {
        if (event.affectsConfiguration('cicd')) {
          provider.refresh();
        }
      });

      // Store provider in context for cleanup
      context.subscriptions.push(treeView, provider as any);
    }
  );
}

/**
 * Register CI/CD commands
 */
function registerCommands(provider: CICDStatusSidebarProvider, context: vscode.ExtensionContext): void {
  // Open pipeline in browser
  context.subscriptions.push(
    vscode.commands.registerCommand('cicdStatus.openPipeline', (pipeline: any) => {
      vscode.env.openExternal(vscode.Uri.parse(pipeline.webUrl));
    })
  );

  // Refresh pipelines
  context.subscriptions.push(
    vscode.commands.registerCommand('cicdStatus.refresh', () => {
      provider.refresh();
      vscode.window.showInformationMessage('CI/CD pipelines refreshed');
    })
  );

  // View pipeline details
  context.subscriptions.push(
    vscode.commands.registerCommand('cicdStatus.viewDetails', async (pipeline: any) => {
      const json = JSON.stringify(pipeline, null, 2);
      const document = await vscode.workspace.openUntitledDocument({
        language: 'json',
        content: json,
      });

      await vscode.window.showTextDocument(document);
    })
  );

  // Configure CI/CD
  context.subscriptions.push(
    vscode.commands.registerCommand('cicdStatus.configure', () => {
      vscode.commands.executeCommand('workbench.action.openSettings', 'cicd');
    })
  );
}

/**
 * Deactivate extension
 */
export function deactivateCICDStatusSidebar(): void {
  // Cleanup handled by context subscriptions
}
