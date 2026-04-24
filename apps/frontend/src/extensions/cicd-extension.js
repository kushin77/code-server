// @file        apps/frontend/src/extensions/cicd-extension.ts
// @module      extensions/cicd-extension
// @description VS Code extension for CI/CD status sidebar
import * as vscode from 'vscode';
import { CICDStatusSidebarProvider } from './cicd-status-sidebar';
/**
 * Activate CI/CD Status Sidebar extension
 */
export function activateCICDStatusSidebar(context) {
    const provider = new CICDStatusSidebarProvider(context);
    // Register tree view
    const treeView = vscode.window.createTreeView('cicdStatus', {
        treeDataProvider: provider,
        showCollapseAll: true,
    });
    // Register commands
    registerCommands(provider, context);
    // Watch for configuration changes
    vscode.workspace.onDidChangeConfiguration((event) => {
        if (event.affectsConfiguration('cicd')) {
            provider.refresh();
        }
    });
    // Store provider in context for cleanup
    context.subscriptions.push(treeView, provider);
}
/**
 * Register CI/CD commands
 */
function registerCommands(provider, context) {
    // Open pipeline in browser
    context.subscriptions.push(vscode.commands.registerCommand('cicdStatus.openPipeline', (pipeline) => {
        vscode.env.openExternal(vscode.Uri.parse(pipeline.webUrl));
    }));
    // Refresh pipelines
    context.subscriptions.push(vscode.commands.registerCommand('cicdStatus.refresh', () => {
        provider.refresh();
        vscode.window.showInformationMessage('CI/CD pipelines refreshed');
    }));
    // View pipeline details
    context.subscriptions.push(vscode.commands.registerCommand('cicdStatus.viewDetails', async (pipeline) => {
        const json = JSON.stringify(pipeline, null, 2);
        const document = await vscode.workspace.openUntitledDocument({
            language: 'json',
            content: json,
        });
        await vscode.window.showTextDocument(document);
    }));
    // Configure CI/CD
    context.subscriptions.push(vscode.commands.registerCommand('cicdStatus.configure', () => {
        vscode.commands.executeCommand('workbench.action.openSettings', 'cicd');
    }));
}
/**
 * Deactivate extension
 */
export function deactivateCICDStatusSidebar() {
    // Cleanup handled by context subscriptions
}
//# sourceMappingURL=cicd-extension.js.map