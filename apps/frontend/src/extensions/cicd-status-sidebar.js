// @file        apps/frontend/src/extensions/cicd-status-sidebar.ts
// @module      extensions/cicd-status-sidebar
// @description VS Code sidebar for live CI/CD pipeline visualization
import * as vscode from 'vscode';
import axios from 'axios';
/**
 * CI/CD Status Sidebar Provider
 *
 * Displays live pipeline status with:
 * - Overall status indicator (color-coded)
 * - Stage breakdown with job details
 * - Log streaming for running jobs
 * - One-click access to pipeline URL
 * - Auto-refresh (configurable interval)
 */
export class CICDStatusSidebarProvider {
    constructor(_context) {
        this._context = _context;
        this._onDidChangeTreeData = new vscode.EventEmitter();
        this.onDidChangeTreeData = this._onDidChangeTreeData.event;
        this.config = null;
        this.apiClient = null;
        this.pipelines = [];
        this.refreshInterval = null;
        this.currentBranch = 'main';
        // Reserved for future use (workspace state, storage, etc.)
        this.loadConfig();
        this.initializeApiClient();
        this.setupRefreshInterval();
        this.watchBranchChanges();
    }
    /**
     * Load CI/CD configuration from workspace settings
     */
    loadConfig() {
        const config = vscode.workspace.getConfiguration('cicd');
        this.config = {
            provider: config.get('provider') || 'github',
            token: config.get('token') || '',
            owner: config.get('owner') || '',
            repo: config.get('repo') || '',
            baseUrl: config.get('baseUrl'),
        };
        if (!this.config.token) {
            void vscode.window.showWarningMessage('CI/CD Status: Configure CICD_TOKEN in settings', 'Settings').then((selected) => {
                if (selected === 'Settings') {
                    void vscode.commands.executeCommand('workbench.action.openSettings', 'cicd');
                }
            });
        }
    }
    /**
     * Initialize API client based on provider
     */
    initializeApiClient() {
        if (!this.config)
            return;
        const baseURL = this.config.baseUrl || this.getProviderBaseUrl();
        this.apiClient = axios.create({
            baseURL,
            headers: {
                'Authorization': `Bearer ${this.config.token}`,
                'Content-Type': 'application/json',
            },
            timeout: 5000,
        });
    }
    /**
     * Get provider-specific base URL
     */
    getProviderBaseUrl() {
        switch (this.config?.provider) {
            case 'github':
                return 'https://api.github.com';
            case 'gitlab':
                return 'https://gitlab.com/api/v4';
            case 'circleci':
                return 'https://circleci.com/api/v2';
            case 'buildkite':
                return 'https://api.buildkite.com/v2';
            default:
                return '';
        }
    }
    /**
     * Setup auto-refresh interval
     */
    setupRefreshInterval() {
        const interval = vscode.workspace.getConfiguration('cicd').get('refreshInterval') || 30000;
        this.refreshInterval = setInterval(() => {
            void this.refresh();
        }, interval);
    }
    /**
     * Watch for branch changes
     */
    watchBranchChanges() {
        vscode.window.onDidChangeActiveTextEditor(() => {
            this.updateBranch();
        });
    }
    /**
     * Update current branch from Git
     */
    async updateBranch() {
        const gitExtension = vscode.extensions.getExtension('vscode.git');
        if (!gitExtension?.isActive)
            return;
        const git = gitExtension.exports.getAPI(1);
        const repo = git.repositories[0];
        if (repo?.state.HEAD?.name) {
            this.currentBranch = repo.state.HEAD.name;
            this.refresh();
        }
    }
    /**
     * Fetch pipelines from CI provider
     */
    async fetchPipelines() {
        if (!this.apiClient || !this.config)
            return [];
        try {
            const pipelines = await this.fetchProviderPipelines();
            this.pipelines = pipelines.sort((a, b) => b.createdAt - a.createdAt);
            return this.pipelines;
        }
        catch (error) {
            vscode.window.showErrorMessage(`Failed to fetch CI/CD pipelines: ${error instanceof Error ? error.message : 'Unknown error'}`);
            return [];
        }
    }
    /**
     * Fetch pipelines based on provider
     */
    async fetchProviderPipelines() {
        if (!this.apiClient || !this.config)
            return [];
        switch (this.config.provider) {
            case 'github':
                return this.fetchGitHubWorkflows();
            case 'gitlab':
                return this.fetchGitLabPipelines();
            case 'circleci':
                return this.fetchCircleCIPipelines();
            case 'buildkite':
                return this.fetchBuildkitePipelines();
            default:
                return [];
        }
    }
    /**
     * Fetch GitHub Actions workflows
     */
    async fetchGitHubWorkflows() {
        if (!this.apiClient || !this.config)
            return [];
        const response = await this.apiClient.get(`/repos/${this.config.owner}/${this.config.repo}/actions/runs`, { params: { branch: this.currentBranch, per_page: 10 } });
        return response.data.workflow_runs.map((run) => ({
            id: run.id,
            name: run.name,
            status: this.normalizeGitHubStatus(run.status),
            branch: run.head_branch,
            commit: run.head_sha.substring(0, 7),
            author: run.actor.login,
            createdAt: new Date(run.created_at).getTime(),
            updatedAt: new Date(run.updated_at).getTime(),
            webUrl: run.html_url,
            stages: [], // Populated later
        }));
    }
    /**
     * Normalize GitHub status to standard format
     */
    normalizeGitHubStatus(status) {
        switch (status) {
            case 'completed':
                return 'success';
            case 'queued':
                return 'pending';
            default:
                return status;
        }
    }
    /**
     * Fetch GitLab CI pipelines
     */
    async fetchGitLabPipelines() {
        if (!this.apiClient || !this.config)
            return [];
        const projectId = `${this.config.owner}%2F${this.config.repo}`;
        const response = await this.apiClient.get(`/projects/${projectId}/pipelines`, { params: { ref: this.currentBranch, per_page: 10 } });
        return response.data.map((pipeline) => ({
            id: pipeline.id,
            name: `Pipeline #${pipeline.id}`,
            status: pipeline.status,
            branch: pipeline.ref,
            commit: pipeline.sha.substring(0, 7),
            author: pipeline.user.username,
            createdAt: new Date(pipeline.created_at).getTime(),
            updatedAt: new Date(pipeline.updated_at).getTime(),
            webUrl: pipeline.web_url,
            stages: pipeline.stages || [],
        }));
    }
    /**
     * Fetch CircleCI pipelines
     */
    async fetchCircleCIPipelines() {
        if (!this.apiClient || !this.config)
            return [];
        const response = await this.apiClient.get(`/project/github/${this.config.owner}/${this.config.repo}/pipeline`, { params: { branch: this.currentBranch } });
        return (response.data.items || []).map((item) => ({
            id: item.id,
            name: `Pipeline ${item.number}`,
            status: item.state,
            branch: item.vcs.branch,
            commit: item.vcs.revision.substring(0, 7),
            author: item.actor.login,
            createdAt: item.created_at,
            updatedAt: item.updated_at,
            webUrl: item.project_slug,
            stages: [],
        }));
    }
    /**
     * Fetch Buildkite pipelines
     */
    async fetchBuildkitePipelines() {
        if (!this.apiClient || !this.config)
            return [];
        const response = await this.apiClient.get(`/organizations/${this.config.owner}/pipelines/${this.config.repo}/builds`, {
            params: { branch: this.currentBranch, per_page: 10 },
        });
        return response.data.map((build) => ({
            id: build.id,
            name: build.message,
            status: build.state,
            branch: build.branch,
            commit: build.commit.substring(0, 7),
            author: build.creator.name,
            createdAt: new Date(build.created_at).getTime(),
            updatedAt: new Date(build.updated_at).getTime(),
            webUrl: build.web_url,
            stages: build.jobs || [],
        }));
    }
    /**
     * Get tree data
     */
    getTreeItem(element) {
        return element;
    }
    /**
     * Get children
     */
    async getChildren(element) {
        if (!element) {
            // Root: show pipelines
            const pipelines = await this.fetchPipelines();
            if (pipelines.length === 0) {
                return [new CICDTreeItem('No pipelines found', vscode.TreeItemCollapsibleState.None)];
            }
            return pipelines.map((pipeline) => new CICDTreeItem(`${this.getStatusIcon(pipeline.status)} ${pipeline.name}`, vscode.TreeItemCollapsibleState.Collapsed, pipeline));
        }
        else if (element.pipeline) {
            // Pipeline children: show stages/jobs
            const pipeline = element.pipeline;
            if (!pipeline.stages || pipeline.stages.length === 0) {
                return [
                    new CICDTreeItem(`Branch: ${pipeline.branch}`, vscode.TreeItemCollapsibleState.None),
                    new CICDTreeItem(`Commit: ${pipeline.commit}`, vscode.TreeItemCollapsibleState.None),
                    new CICDTreeItem(`Author: ${pipeline.author}`, vscode.TreeItemCollapsibleState.None),
                    new CICDTreeItem(`Status: ${pipeline.status}`, vscode.TreeItemCollapsibleState.None),
                ];
            }
            return pipeline.stages.map((stage) => new CICDTreeItem(`${this.getStatusIcon(stage.status)} ${stage.name}`, vscode.TreeItemCollapsibleState.Collapsed, undefined, stage));
        }
        else if (element.stage) {
            // Stage children: show jobs
            return element.stage.jobs.map((job) => new CICDTreeItem(`${this.getStatusIcon(job.status)} ${job.name}`, vscode.TreeItemCollapsibleState.None, undefined, undefined, job));
        }
        return [];
    }
    /**
     * Get status emoji
     */
    getStatusIcon(status) {
        switch (status) {
            case 'success':
                return '✅';
            case 'failed':
                return '❌';
            case 'running':
                return '⏳';
            case 'pending':
                return '⏱️';
            case 'canceled':
                return '🚫';
            case 'skipped':
                return '⊘';
            default:
                return '❓';
        }
    }
    /**
     * Refresh tree
     */
    refresh() {
        this._onDidChangeTreeData.fire(undefined);
    }
    /**
     * Dispose
     */
    dispose() {
        if (this.refreshInterval) {
            clearInterval(this.refreshInterval);
        }
    }
}
/**
 * Tree item for CI/CD status
 */
class CICDTreeItem extends vscode.TreeItem {
    constructor(label, collapsibleState, pipeline, stage, job) {
        super(label, collapsibleState);
        this.label = label;
        this.collapsibleState = collapsibleState;
        this.pipeline = pipeline;
        this.stage = stage;
        this.job = job;
        this.setupContextMenu();
        this.setupCommand();
    }
    setupContextMenu() {
        if (this.pipeline) {
            this.contextValue = 'pipeline';
            this.tooltip = `${this.pipeline.status} - ${this.pipeline.author}`;
        }
        else if (this.stage) {
            this.contextValue = 'stage';
            this.tooltip = `Stage: ${this.stage.name} (${this.stage.status})`;
        }
        else if (this.job) {
            this.contextValue = 'job';
            this.tooltip = `Job: ${this.job.name} (${this.job.status}) - ${this.job.duration}ms`;
        }
    }
    setupCommand() {
        if (this.pipeline) {
            this.command = {
                title: 'Open Pipeline',
                command: 'cicdStatus.openPipeline',
                arguments: [this.pipeline],
            };
        }
    }
}
export { CICDTreeItem };
//# sourceMappingURL=cicd-status-sidebar.js.map