#!/usr/bin/env node
// @file        apps/extensions/team-hub/src/github-task-panel.ts
// @module      extensions/team-hub/github-task-panel
// @description GitHub issue task panel for IDE
// @owner       collab-9
// @status      active

import * as vscode from 'vscode';
import axios, { AxiosInstance } from 'axios';

export interface TaskItem {
  id: string;
  issueNumber: number;
  title: string;
  description: string;
  state: 'open' | 'closed';
  assignees: string[];
  labels: string[];
  lastSyncAt: Date;
  gitHubUrl: string;
}

export interface TaskPanelOptions {
  apiBaseUrl: string;
  pollingIntervalMs?: number;
}

/**
 * GitHub Task Panel Provider
 * Displays GitHub issues as a task list in the IDE activity bar
 */
export class GitHubTaskPanelProvider implements vscode.TreeDataProvider<TaskItem> {
  private _onDidChangeTreeData: vscode.EventEmitter<TaskItem | undefined | null | void> =
    new vscode.EventEmitter<TaskItem | undefined | null | void>();

  readonly onDidChangeTreeData: vscode.Event<TaskItem | undefined | null | void> =
    this._onDidChangeTreeData.event;

  private tasks: Map<number, TaskItem> = new Map();
  private apiClient: AxiosInstance;
  private pollingInterval: NodeJS.Timeout | null = null;

  constructor(private options: TaskPanelOptions) {
    this.apiClient = axios.create({
      baseURL: options.apiBaseUrl,
      timeout: 10000,
    });

    // Start polling for changes
    this.startPolling();
  }

  /**
   * Tree data provider: Get children
   */
  getChildren(element?: TaskItem): Thenable<TaskItem[]> {
    if (element) {
      return Promise.resolve([]);
    }

    return this.getTaskList();
  }

  /**
   * Tree data provider: Get tree item
   */
  getTreeItem(element: TaskItem): vscode.TreeItem | Thenable<vscode.TreeItem> {
    const item = new vscode.TreeItem(
      element.title,
      vscode.TreeItemCollapsibleState.None
    );

    item.iconPath = this.getIconForState(element.state);
    item.tooltip = this.getTooltip(element);
    item.command = {
      command: 'github-task-panel.openIssue',
      title: 'Open Issue',
      arguments: [element],
    };

    // Add description showing issue number and labels
    const labelStr = element.labels.length > 0 ? ` [${element.labels.join(', ')}]` : '';
    item.description = `#${element.issueNumber}${labelStr}`;

    return item;
  }

  /**
   * Fetch task list from backend
   */
  async getTaskList(state?: 'open' | 'closed' | 'all'): Promise<TaskItem[]> {
    try {
      const response = await this.apiClient.get('/github-task-sync/issues', {
        params: { state: state || 'open' },
      });

      const tasks = response.data.data || [];

      // Update local cache
      tasks.forEach((task: TaskItem) => {
        this.tasks.set(task.issueNumber, task);
      });

      return tasks;
    } catch (error) {
      console.error('Error fetching task list:', error);
      vscode.window.showErrorMessage('Failed to fetch GitHub issues');
      return [];
    }
  }

  /**
   * Create new issue from IDE
   */
  async createIssue(title: string, description?: string, labels?: string[]): Promise<void> {
    try {
      const response = await this.apiClient.post('/github-task-sync/issues', {
        title,
        description: description || '',
        labels: labels || [],
      });

      const newTask = response.data.data;
      this.tasks.set(newTask.issueNumber, newTask);

      // Refresh tree
      this.refresh();

      vscode.window.showInformationMessage(
        `Created issue #${newTask.issueNumber}: ${newTask.title}`,
        'Open'
      ).then((selection) => {
        if (selection === 'Open') {
          vscode.env.openExternal(vscode.Uri.parse(newTask.gitHubUrl));
        }
      });
    } catch (error: any) {
      vscode.window.showErrorMessage(`Failed to create issue: ${error.message}`);
    }
  }

  /**
   * Update issue from IDE
   */
  async updateIssue(
    issueNumber: number,
    updates: {
      title?: string;
      description?: string;
      labels?: string[];
      state?: 'open' | 'closed';
    }
  ): Promise<void> {
    try {
      const response = await this.apiClient.patch(
        `/github-task-sync/issues/${issueNumber}`,
        updates
      );

      const updatedTask = response.data.data;
      this.tasks.set(updatedTask.issueNumber, updatedTask);

      // Refresh tree
      this.refresh();

      vscode.window.showInformationMessage(
        `Updated issue #${issueNumber}`
      );
    } catch (error: any) {
      vscode.window.showErrorMessage(`Failed to update issue: ${error.message}`);
    }
  }

  /**
   * Close issue from IDE
   */
  async closeIssue(issueNumber: number, reason?: string): Promise<void> {
    try {
      const response = await this.apiClient.post(
        `/github-task-sync/issues/${issueNumber}/close`,
        { reason: reason || '' }
      );

      const closedTask = response.data.data;
      this.tasks.set(closedTask.issueNumber, closedTask);

      // Refresh tree
      this.refresh();

      vscode.window.showInformationMessage(
        `Closed issue #${issueNumber}`
      );
    } catch (error: any) {
      vscode.window.showErrorMessage(`Failed to close issue: ${error.message}`);
    }
  }

  /**
   * Reopen issue from IDE
   */
  async reopenIssue(issueNumber: number): Promise<void> {
    try {
      const response = await this.apiClient.post(
        `/github-task-sync/issues/${issueNumber}/reopen`
      );

      const reopenedTask = response.data.data;
      this.tasks.set(reopenedTask.issueNumber, reopenedTask);

      // Refresh tree
      this.refresh();

      vscode.window.showInformationMessage(
        `Reopened issue #${issueNumber}`
      );
    } catch (error: any) {
      vscode.window.showErrorMessage(`Failed to reopen issue: ${error.message}`);
    }
  }

  /**
   * Manually trigger sync from GitHub
   */
  async manualSync(): Promise<void> {
    try {
      vscode.window.withProgress(
        {
          location: vscode.ProgressLocation.Notification,
          title: 'Syncing GitHub issues...',
          cancellable: false,
        },
        async () => {
          const response = await this.apiClient.post('/github-task-sync/sync');

          const result = response.data.data;

          vscode.window.showInformationMessage(
            `Sync complete: ${result.synced} issues (${result.created} new, ${result.updated} updated)`
          );

          // Refresh tree
          this.refresh();
        }
      );
    } catch (error: any) {
      vscode.window.showErrorMessage(`Sync failed: ${error.message}`);
    }
  }

  /**
   * Get sync status
   */
  async getSyncStatus(): Promise<any> {
    try {
      const response = await this.apiClient.get('/github-task-sync/status');
      return response.data.data;
    } catch (error) {
      console.error('Failed to get sync status:', error);
      return null;
    }
  }

  /**
   * Start polling for changes
   */
  private startPolling(): void {
    const interval = this.options.pollingIntervalMs || 30000;

    this.pollingInterval = setInterval(async () => {
      try {
        const tasks = await this.getTaskList();

        // Check for changes
        if (tasks.length !== this.tasks.size) {
          this.refresh();
        }
      } catch (error) {
        console.error('Polling error:', error);
      }
    }, interval);
  }

  /**
   * Stop polling
   */
  stopPolling(): void {
    if (this.pollingInterval) {
      clearInterval(this.pollingInterval);
      this.pollingInterval = null;
    }
  }

  /**
   * Refresh tree view
   */
  refresh(): void {
    this._onDidChangeTreeData.fire();
  }

  /**
   * Get icon for task state
   */
  private getIconForState(state: 'open' | 'closed'): vscode.ThemeIcon | string {
    if (state === 'closed') {
      return new vscode.ThemeIcon('check', new vscode.ThemeColor('testing.runAction'));
    } else {
      return new vscode.ThemeIcon('github-action', new vscode.ThemeColor('notebookStatusRunning'));
    }
  }

  /**
   * Get tooltip for task
   */
  private getTooltip(task: TaskItem): vscode.MarkdownString {
    const md = new vscode.MarkdownString();

    md.appendMarkdown(`**${task.title}**\n\n`);
    md.appendMarkdown(`Issue #${task.issueNumber}\n\n`);
    md.appendMarkdown(`State: \`${task.state}\`\n\n`);

    if (task.labels.length > 0) {
      md.appendMarkdown(`Labels: ${task.labels.map((l) => `\`${l}\``).join(', ')}\n\n`);
    }

    if (task.assignees.length > 0) {
      md.appendMarkdown(`Assignees: ${task.assignees.join(', ')}\n\n`);
    }

    md.appendMarkdown(`[Open on GitHub](${task.gitHubUrl})`);

    return md;
  }

  /**
   * Dispose resources
   */
  dispose(): void {
    this.stopPolling();
  }
}

/**
 * Register GitHub task panel in VS Code
 */
export function registerGitHubTaskPanel(context: vscode.ExtensionContext): GitHubTaskPanelProvider {
  const apiBaseUrl = vscode.workspace
    .getConfiguration('github-task-sync')
    .get('apiBaseUrl') || 'http://localhost:3000/api';

  const provider = new GitHubTaskPanelProvider({
    apiBaseUrl,
    pollingIntervalMs: 30000,
  });

  const view = vscode.window.createTreeView('github-task-panel', {
    treeDataProvider: provider,
    showCollapseAll: true,
  });

  context.subscriptions.push(view);

  // Register commands
  context.subscriptions.push(
    vscode.commands.registerCommand('github-task-panel.refresh', () => {
      provider.refresh();
    }),

    vscode.commands.registerCommand('github-task-panel.createIssue', async () => {
      const title = await vscode.window.showInputBox({
        prompt: 'Issue title',
        placeHolder: 'Enter issue title',
      });

      if (!title) return;

      const description = await vscode.window.showInputBox({
        prompt: 'Issue description (optional)',
        placeHolder: 'Enter issue description',
      });

      await provider.createIssue(title, description);
    }),

    vscode.commands.registerCommand('github-task-panel.manualSync', async () => {
      await provider.manualSync();
    }),

    vscode.commands.registerCommand('github-task-panel.openIssue', (task: TaskItem) => {
      vscode.env.openExternal(vscode.Uri.parse(task.gitHubUrl));
    })
  );

  console.log('GitHub Task Panel registered');

  return provider;
}

export default registerGitHubTaskPanel;
