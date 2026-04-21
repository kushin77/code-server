// @file        apps/frontend/src/extensions/otel-apm-extension.ts
// @module      extensions/otel-apm-extension
// @description VS Code extension entry point for OpenTelemetry APM monitoring

import * as vscode from 'vscode';
import { OtelApmSidebarProvider } from './otel-apm-sidebar';
import type { TraceSummary } from '../../../backend/src/services/observability/otel-apm-client';
import { measureAsyncExtensionProfiler } from '@/utils/extensionProfiler';

let provider: OtelApmSidebarProvider | undefined;

export function activateOtelApm(context: vscode.ExtensionContext): void {
  void measureAsyncExtensionProfiler(
    {
      id: 'otel-apm',
      label: 'OpenTelemetry APM',
      category: 'observability',
      kind: 'activation',
    },
    async () => {
      provider = new OtelApmSidebarProvider(context);

      const treeView = vscode.window.createTreeView('otelApm', {
        treeDataProvider: provider,
        showCollapseAll: true,
      });

      context.subscriptions.push(treeView, provider as unknown as vscode.Disposable);

      context.subscriptions.push(
        vscode.commands.registerCommand('otelApm.refresh', async () => {
          await provider?.refresh();
          vscode.window.showInformationMessage('OpenTelemetry APM refreshed');
        }),
        vscode.commands.registerCommand('otelApm.refreshService', async (_service: string) => {
          await provider?.refresh();
        }),
        vscode.commands.registerCommand('otelApm.openTrace', async (trace: TraceSummary) => {
          const config = vscode.workspace.getConfiguration('otelApm');
          const jaegerBaseUrl = (config.get('jaegerBaseUrl') as string) || 'http://localhost:16686';
          const traceUrl = `${jaegerBaseUrl.replace(/\/$/, '')}/trace/${trace.traceId}`;
          await vscode.env.openExternal(vscode.Uri.parse(traceUrl));
        }),
        vscode.commands.registerCommand('otelApm.configure', () => {
          void vscode.commands.executeCommand('workbench.action.openSettings', 'otelApm');
        })
      );

      vscode.workspace.onDidChangeConfiguration((event: any) => {
        if (event.affectsConfiguration('otelApm')) {
          void provider?.refresh();
        }
      });
    }
  );
}

export function deactivateOtelApm(): void {
  provider?.dispose();
}
