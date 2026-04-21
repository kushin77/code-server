// @file        apps/frontend/src/extensions/sentry-errors-sidebar.ts
// @module      extensions/sentry-errors-sidebar
// @description VS Code sidebar for Sentry error monitoring

import * as vscode from 'vscode';
import axios, { AxiosInstance } from 'axios';

interface SentryError {
  id: string;
  title: string;
  level: 'fatal' | 'error' | 'warning' | 'info' | 'debug';
  status: 'unresolved' | 'resolved' | 'ignored';
  count: number;
  userCount: number;
  lastSeen: string;
  environment: string;
}

/**
 * Sentry Errors Sidebar Provider
 *
 * Displays live error tracking with:
 * - Unresolved error list
 * - Error severity indicators
 * - Affected users count
 * - Quick status updates (resolve/ignore)
 * - Direct links to Sentry
 */
export class SentryErrorsSidebarProvider implements vscode.TreeDataProvider<SentryTreeItem> {
  private _onDidChangeTreeData = new vscode.EventEmitter<SentryTreeItem | undefined>()
  readonly onDidChangeTreeData = this._onDidChangeTreeData.event

  private apiClient: AxiosInstance | null = null
  private errors: SentryError[] = []
  private refreshInterval: NodeJS.Timeout | null = null

  constructor(private context: vscode.ExtensionContext) {
    this.loadConfig()
    this.setupRefreshInterval()
  }

  private loadConfig(): void {
    const config = vscode.workspace.getConfiguration('sentry')
    const token = (config.get('token') as string | undefined) || ''
    const organization = (config.get('organization') as string | undefined) || ''
    const project = (config.get('project') as string | undefined) || ''

    if (!token) {
      void vscode.window.showWarningMessage(
        'Sentry Error Monitor: Configure SENTRY_TOKEN in settings',
        'Settings'
      ).then((selected: string | undefined) => {
        if (selected === 'Settings') {
          void vscode.commands.executeCommand('workbench.action.openSettings', 'sentry')
        }
      })
      return
    }

    this.apiClient = axios.create({
      baseURL: 'https://sentry.io/api/0',
      headers: { Authorization: `Bearer ${token}` },
      timeout: 5000,
    })

    void this.loadErrors()
  }

  private async loadErrors(): Promise<void> {
    if (!this.apiClient) return

    try {
      const config = vscode.workspace.getConfiguration('sentry')
      const organization = (config.get('organization') as string | undefined) || ''
      const project = (config.get('project') as string | undefined) || ''

      const response = await this.apiClient.get(
        `/projects/${organization}/${project}/issues/`,
        { params: { query: 'is:unresolved', limit: 20 } }
      )

      this.errors = response.data
      this._onDidChangeTreeData.fire(undefined)
    } catch (error) {
      vscode.window.showErrorMessage(
        `Failed to load Sentry errors: ${error instanceof Error ? error.message : 'Unknown error'}`
      )
    }
  }

  private setupRefreshInterval(): void {
    const interval = ((vscode.workspace.getConfiguration('sentry').get('refreshInterval') as number | undefined) || 60000)

    this.refreshInterval = setInterval(() => {
      void this.loadErrors()
    }, interval)
  }

  getTreeItem(element: SentryTreeItem): vscode.TreeItem {
    return element;
  }

  async getChildren(element?: SentryTreeItem): Promise<SentryTreeItem[]> {
    if (!element) {
      if (this.errors.length === 0) {
        return [new SentryTreeItem('No errors', vscode.TreeItemCollapsibleState.None)];
      }

      return this.errors.map((error) =>
        new SentryTreeItem(
          `${this.getSeverityIcon(error.level)} ${error.title}`,
          vscode.TreeItemCollapsibleState.Collapsed,
          error
        )
      );
    } else if (element.error) {
      const error = element.error;

      return [
        new SentryTreeItem(`Status: ${error.status}`, vscode.TreeItemCollapsibleState.None),
        new SentryTreeItem(`Count: ${error.count}`, vscode.TreeItemCollapsibleState.None),
        new SentryTreeItem(`Affected Users: ${error.userCount}`, vscode.TreeItemCollapsibleState.None),
        new SentryTreeItem(`Environment: ${error.environment}`, vscode.TreeItemCollapsibleState.None),
        new SentryTreeItem(`Last Seen: ${error.lastSeen}`, vscode.TreeItemCollapsibleState.None),
      ];
    }

    return [];
  }

  private getSeverityIcon(level: string): string {
    switch (level) {
      case 'fatal':
        return '🔴';
      case 'error':
        return '❌';
      case 'warning':
        return '⚠️';
      case 'info':
        return 'ℹ️';
      default:
        return '●';
    }
  }

  public refresh(): void {
    this.loadErrors();
  }

  public dispose(): void {
    if (this.refreshInterval) {
      clearInterval(this.refreshInterval);
    }
  }
}

class SentryTreeItem extends vscode.TreeItem {
  constructor(
    public readonly label: string,
    public readonly collapsibleState: vscode.TreeItemCollapsibleState,
    public readonly error?: SentryError
  ) {
    super(label, collapsibleState);

    if (error) {
      this.tooltip = `${error.title} - ${error.count} occurrences`;
      this.contextValue = 'error';
      this.command = {
        title: 'Open in Sentry',
        command: 'sentryErrors.openInSentry',
        arguments: [error],
      };
    }
  }
}

export { SentryErrorsSidebarProvider, SentryTreeItem };
