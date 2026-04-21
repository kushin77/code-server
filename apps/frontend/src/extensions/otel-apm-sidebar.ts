// @file        apps/frontend/src/extensions/otel-apm-sidebar.ts
// @module      extensions/otel-apm-sidebar
// @description VS Code sidebar for OpenTelemetry APM monitoring

import * as vscode from 'vscode';
import OtelApmClient, { ApmOverview, TraceSummary } from '../../../backend/src/services/observability/otel-apm-client';

interface ApmTreeData {
  kind: 'root' | 'service' | 'trace' | 'metric';
  label: string;
  service?: string;
  trace?: TraceSummary;
  overview?: ApmOverview;
  description?: string;
}

export class OtelApmSidebarProvider implements vscode.TreeDataProvider<ApmTreeItem> {
  private readonly onDidChangeTreeDataEmitter = new vscode.EventEmitter<ApmTreeItem | undefined>();
  readonly onDidChangeTreeData = this.onDidChangeTreeDataEmitter.event;

  private client: OtelApmClient;
  private services: string[] = [];
  private overview: ApmOverview | null = null;
  private tracesByService = new Map<string, TraceSummary[]>();
  private refreshHandle: ReturnType<typeof setInterval> | null = null;

  constructor(private readonly context: vscode.ExtensionContext) {
    const config = vscode.workspace.getConfiguration('otelApm')
    this.client = new OtelApmClient(
      (config.get('jaegerBaseUrl') as string | undefined) || 'http://localhost:16686',
      (config.get('prometheusBaseUrl') as string | undefined) || 'http://localhost:9090'
    )

    void this.refresh()
    this.refreshHandle = setInterval(() => {
      void this.refresh()
    }, ((config.get('refreshInterval') as number | undefined) || 30000))
  }

  async refresh(): Promise<void> {
    try {
      this.services = await this.client.listServices();
      this.overview = await this.client.getOverview(this.services[0]);
      this.tracesByService.clear();

      for (const service of this.services.slice(0, 5)) {
        this.tracesByService.set(service, await this.client.getTraces(service, '1h', 10));
      }

      this.onDidChangeTreeDataEmitter.fire(undefined);
    } catch (error) {
      vscode.window.showWarningMessage(
        `Failed to load OpenTelemetry data: ${error instanceof Error ? error.message : 'Unknown error'}`
      );
    }
  }

  getTreeItem(element: ApmTreeItem): vscode.TreeItem {
    return element;
  }

  async getChildren(element?: ApmTreeItem): Promise<ApmTreeItem[]> {
    if (!element) {
      const items: ApmTreeItem[] = [];

      if (this.overview) {
        items.push(
          new ApmTreeItem(
            `Services: ${this.overview.services}`,
            vscode.TreeItemCollapsibleState.None,
            { kind: 'metric', label: 'services', description: `${this.overview.services} active services` }
          ),
          new ApmTreeItem(
            `Active Traces: ${this.overview.activeTraces}`,
            vscode.TreeItemCollapsibleState.None,
            { kind: 'metric', label: 'traces', description: `${this.overview.activeTraces} recent traces` }
          ),
          new ApmTreeItem(
            `Error Rate: ${(this.overview.errorRate * 100).toFixed(1)}%`,
            vscode.TreeItemCollapsibleState.None,
            { kind: 'metric', label: 'errors', description: 'Current error rate' }
          ),
          new ApmTreeItem(
            `p95 Latency: ${this.overview.p95LatencyMs.toFixed(0)}ms`,
            vscode.TreeItemCollapsibleState.None,
            { kind: 'metric', label: 'latency', description: '95th percentile latency' }
          )
        );
      }

      if (this.services.length === 0) {
        items.push(
          new ApmTreeItem('No services discovered', vscode.TreeItemCollapsibleState.None, {
            kind: 'root',
            label: 'empty',
            description: 'Check Jaeger/Prometheus connectivity',
          })
        );
        return items;
      }

      return [
        ...items,
        ...this.services.map((service) =>
          new ApmTreeItem(service, vscode.TreeItemCollapsibleState.Collapsed, {
            kind: 'service',
            label: service,
            service,
            description: `${(this.tracesByService.get(service)?.length ?? 0)} recent traces`,
          })
        ),
      ];
    }

    if (element.data?.kind === 'service' && element.data.service) {
      const serviceTraces = this.tracesByService.get(element.data.service) || [];
      if (serviceTraces.length === 0) {
        return [
          new ApmTreeItem('No recent traces', vscode.TreeItemCollapsibleState.None, {
            kind: 'trace',
            label: 'none',
          }),
        ];
      }

      return serviceTraces.map((trace) =>
        new ApmTreeItem(
          `${trace.durationMs}ms ${trace.operation}`,
          vscode.TreeItemCollapsibleState.None,
          { kind: 'trace', label: trace.traceId, trace, service: element.data.service }
        )
      );
    }

    return [];
  }

  dispose(): void {
    if (this.refreshHandle) {
      clearInterval(this.refreshHandle);
    }
    this.client.clearCache();
  }
}

class ApmTreeItem extends vscode.TreeItem {
  constructor(label: string, collapsibleState: vscode.TreeItemCollapsibleState, public readonly data: ApmTreeData) {
    super(label, collapsibleState);

    if (data.kind === 'metric') {
      this.iconPath = new vscode.ThemeIcon('graph');
      this.tooltip = data.description;
      this.contextValue = 'apmMetric';
    }

    if (data.kind === 'service') {
      this.iconPath = new vscode.ThemeIcon('server');
      this.tooltip = data.description;
      this.contextValue = 'apmService';
      this.command = {
        title: 'Refresh Service Traces',
        command: 'otelApm.refreshService',
        arguments: [data.service],
      };
    }

    if (data.kind === 'trace' && data.trace) {
      this.iconPath = new vscode.ThemeIcon(data.trace.errorCount > 0 ? 'error' : 'pulse');
      this.tooltip = `${data.trace.durationMs}ms · ${data.trace.spanCount} spans`;
      this.contextValue = 'apmTrace';
      this.command = {
        title: 'Open Trace',
        command: 'otelApm.openTrace',
        arguments: [data.trace],
      };
    }
  }
}

export { ApmTreeItem };
