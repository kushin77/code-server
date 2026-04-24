// @file        apps/frontend/src/extensions/sentry-errors-sidebar.ts
// @module      extensions/sentry-errors-sidebar
// @description VS Code sidebar for Sentry error monitoring
import * as vscode from 'vscode';
import axios from 'axios';
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
export class SentryErrorsSidebarProvider {
    constructor(context) {
        this.context = context;
        this._onDidChangeTreeData = new vscode.EventEmitter();
        this.onDidChangeTreeData = this._onDidChangeTreeData.event;
        this.apiClient = null;
        this.errors = [];
        this.refreshInterval = null;
        this.loadConfig();
        this.setupRefreshInterval();
    }
    loadConfig() {
        const config = vscode.workspace.getConfiguration('sentry');
        const token = config.get('token') || '';
        const organization = config.get('organization') || '';
        const project = config.get('project') || '';
        if (!token) {
            void vscode.window.showWarningMessage('Sentry Error Monitor: Configure SENTRY_TOKEN in settings', 'Settings').then((selected) => {
                if (selected === 'Settings') {
                    void vscode.commands.executeCommand('workbench.action.openSettings', 'sentry');
                }
            });
            return;
        }
        this.apiClient = axios.create({
            baseURL: 'https://sentry.io/api/0',
            headers: { Authorization: `Bearer ${token}` },
            timeout: 5000,
        });
        void this.loadErrors();
    }
    async loadErrors() {
        if (!this.apiClient)
            return;
        try {
            const config = vscode.workspace.getConfiguration('sentry');
            const organization = config.get('organization') || '';
            const project = config.get('project') || '';
            const response = await this.apiClient.get(`/projects/${organization}/${project}/issues/`, { params: { query: 'is:unresolved', limit: 20 } });
            this.errors = response.data;
            this._onDidChangeTreeData.fire(undefined);
        }
        catch (error) {
            vscode.window.showErrorMessage(`Failed to load Sentry errors: ${error instanceof Error ? error.message : 'Unknown error'}`);
        }
    }
    setupRefreshInterval() {
        const interval = (vscode.workspace.getConfiguration('sentry').get('refreshInterval') || 60000);
        this.refreshInterval = setInterval(() => {
            void this.loadErrors();
        }, interval);
    }
    getTreeItem(element) {
        return element;
    }
    async getChildren(element) {
        if (!element) {
            if (this.errors.length === 0) {
                return [new SentryTreeItem('No errors', vscode.TreeItemCollapsibleState.None)];
            }
            return this.errors.map((error) => new SentryTreeItem(`${this.getSeverityIcon(error.level)} ${error.title}`, vscode.TreeItemCollapsibleState.Collapsed, error));
        }
        else if (element.error) {
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
    getSeverityIcon(level) {
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
    refresh() {
        this.loadErrors();
    }
    dispose() {
        if (this.refreshInterval) {
            clearInterval(this.refreshInterval);
        }
    }
}
class SentryTreeItem extends vscode.TreeItem {
    constructor(label, collapsibleState, error) {
        super(label, collapsibleState);
        this.label = label;
        this.collapsibleState = collapsibleState;
        this.error = error;
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
export { SentryTreeItem };
//# sourceMappingURL=sentry-errors-sidebar.js.map