// @file        apps/frontend/src/extensions/otel-apm-extension.ts
// @module      extensions/otel-apm-extension
// @description VS Code extension entry point for OpenTelemetry APM monitoring
import * as vscode from 'vscode';
import { OtelApmSidebarProvider } from './otel-apm-sidebar';
let provider;
export function activateOtelApm(context) {
    provider = new OtelApmSidebarProvider(context);
    const treeView = vscode.window.createTreeView('otelApm', {
        treeDataProvider: provider,
        showCollapseAll: true,
    });
    context.subscriptions.push(treeView, provider);
    context.subscriptions.push(vscode.commands.registerCommand('otelApm.refresh', async () => {
        await provider?.refresh();
        vscode.window.showInformationMessage('OpenTelemetry APM refreshed');
    }), vscode.commands.registerCommand('otelApm.refreshService', async (_service) => {
        await provider?.refresh();
    }), vscode.commands.registerCommand('otelApm.openTrace', async (trace) => {
        const config = vscode.workspace.getConfiguration('otelApm');
        const jaegerBaseUrl = config.get('jaegerBaseUrl', 'http://localhost:16686');
        const traceUrl = `${jaegerBaseUrl.replace(/\/$/, '')}/trace/${trace.traceId}`;
        await vscode.env.openExternal(vscode.Uri.parse(traceUrl));
    }), vscode.commands.registerCommand('otelApm.configure', () => {
        void vscode.commands.executeCommand('workbench.action.openSettings', 'otelApm');
    }));
    vscode.workspace.onDidChangeConfiguration((event) => {
        if (event.affectsConfiguration('otelApm')) {
            void provider?.refresh();
        }
    });
}
export function deactivateOtelApm() {
    provider?.dispose();
}
//# sourceMappingURL=otel-apm-extension.js.map