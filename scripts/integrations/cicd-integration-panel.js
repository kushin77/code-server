#!/usr/bin/env node
/**
 * @file        scripts/integrations/cicd-integration-panel.js
 * @module      integrations/cicd
 * @description VS Code WebView panel for GitHub Actions workflow monitoring and control
 */

const vscode = require('vscode');

class CICDIntegrationPanel {
    constructor(context, apiEndpoint = 'http://localhost:9096') {
        this.context = context;
        this.apiEndpoint = apiEndpoint;
        this.panel = null;
        this.webviewApi = null;
        this.currentRun = null;
        this.workflows = [];
        this.isLoading = false;
        this.pollTimer = null;
    }
    
    /**
     * Show the CI/CD integration panel
     */
    show() {
        if (this.panel) {
            this.panel.reveal(vscode.ViewColumn.Beside);
            return;
        }
        
        // Create panel
        this.panel = vscode.window.createWebviewPanel(
            'cicdIntegration',
            'CI/CD Pipelines',
            vscode.ViewColumn.Beside,
            {
                enableScripts: true,
                enableForms: true,
                retainContextWhenHidden: true,
                localResourceRoots: [vscode.Uri.file(this.context.extensionPath)]
            }
        );
        
        // Set icon
        this.panel.iconPath = {
            light: vscode.Uri.file(this.context.asAbsolutePath('media/cicd-light.svg')),
            dark: vscode.Uri.file(this.context.asAbsolutePath('media/cicd-dark.svg'))
        };
        
        // Set initial content
        this.panel.webview.html = this._getWebviewContent();
        
        // Handle messages from webview
        this.panel.webview.onDidReceiveMessage(async (message) => {
            await this._handleWebviewMessage(message);
        }, undefined, this.context.subscriptions);
        
        // Handle panel disposal
        this.panel.onDidDispose(() => {
            this.panel = null;
            this._stopPolling();
        });
        
        // Load initial workflows
        this._refreshWorkflows();
        this._startPolling();
    }
    
    /**
     * Refresh workflow list
     */
    async _refreshWorkflows() {
        try {
            this.isLoading = true;
            this._postMessage({ command: 'setLoading', loading: true });
            
            const response = await fetch(`${this.apiEndpoint}/api/cicd/workflows?status=all&limit=20`);
            const data = await response.json();
            
            if (data.success) {
                this.workflows = data.workflows;
                this._postMessage({
                    command: 'updateWorkflows',
                    workflows: data.workflows
                });
            }
        } catch (error) {
            vscode.window.showErrorMessage(`Failed to fetch workflows: ${error.message}`);
            this._postMessage({
                command: 'error',
                message: `Failed to fetch workflows: ${error.message}`
            });
        } finally {
            this.isLoading = false;
            this._postMessage({ command: 'setLoading', loading: false });
        }
    }
    
    /**
     * Load jobs for a workflow run
     */
    async _loadWorkflowJobs(runId) {
        try {
            this._postMessage({ command: 'setLoading', loading: true });
            
            const jobsResponse = await fetch(`${this.apiEndpoint}/api/cicd/runs/${runId}/jobs`);
            const jobsData = await jobsResponse.json();
            
            const dagResponse = await fetch(`${this.apiEndpoint}/api/cicd/runs/${runId}/dag`);
            const dagData = await dagResponse.json();
            
            if (jobsData.success && dagData.success) {
                this.currentRun = { id: runId, jobs: jobsData.jobs, dag: dagData.dag };
                this._postMessage({
                    command: 'showJobs',
                    runId,
                    jobs: jobsData.jobs,
                    dag: dagData.dag
                });
            }
        } catch (error) {
            vscode.window.showErrorMessage(`Failed to load jobs: ${error.message}`);
        } finally {
            this._postMessage({ command: 'setLoading', loading: false });
        }
    }
    
    /**
     * Fetch and tail job logs
     */
    async _tailJobLogs(jobId) {
        try {
            this._postMessage({ command: 'setLoading', loading: true });
            
            const response = await fetch(`${this.apiEndpoint}/api/cicd/jobs/${jobId}/logs?lines=500`);
            const data = await response.json();
            
            if (data.success) {
                this._postMessage({
                    command: 'showLogs',
                    jobId,
                    logs: data.logs
                });
                
                // Show logs in output channel
                this._showLogsInOutputChannel(jobId, data.logs);
            }
        } catch (error) {
            vscode.window.showErrorMessage(`Failed to fetch logs: ${error.message}`);
        } finally {
            this._postMessage({ command: 'setLoading', loading: false });
        }
    }
    
    /**
     * Show logs in output channel
     */
    _showLogsInOutputChannel(jobId, logs) {
        const outputChannel = vscode.window.createOutputChannel(`CI/CD - Job ${jobId}`);
        outputChannel.show(true);
        
        logs.forEach(log => {
            const icon = log.level === 'error' ? '❌' : log.level === 'success' ? '✅' : '📝';
            outputChannel.appendLine(`${icon} [${log.lineNumber}] ${log.content}`);
        });
    }
    
    /**
     * Re-run a workflow
     */
    async _reRunWorkflow(runId) {
        const confirmed = await vscode.window.showWarningMessage(
            'Are you sure you want to re-run this workflow?',
            'Yes',
            'No'
        );
        
        if (confirmed !== 'Yes') return;
        
        try {
            this._postMessage({ command: 'setLoading', loading: true });
            
            const response = await fetch(`${this.apiEndpoint}/api/cicd/runs/${runId}/rerun`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' }
            });
            
            const data = await response.json();
            
            if (data.success) {
                vscode.window.showInformationMessage('Workflow re-run initiated');
                await this._refreshWorkflows();
            }
        } catch (error) {
            vscode.window.showErrorMessage(`Failed to re-run workflow: ${error.message}`);
        } finally {
            this._postMessage({ command: 'setLoading', loading: false });
        }
    }
    
    /**
     * Start polling for updates
     */
    _startPolling() {
        if (this.pollTimer) return;
        
        this.pollTimer = setInterval(async () => {
            if (!this.isLoading) {
                await this._refreshWorkflows();
            }
        }, 30000); // Poll every 30 seconds
    }
    
    /**
     * Stop polling
     */
    _stopPolling() {
        if (this.pollTimer) {
            clearInterval(this.pollTimer);
            this.pollTimer = null;
        }
    }
    
    /**
     * Handle messages from webview
     */
    async _handleWebviewMessage(message) {
        switch (message.command) {
            case 'refresh':
                await this._refreshWorkflows();
                break;
                
            case 'loadJobs':
                await this._loadWorkflowJobs(message.runId);
                break;
                
            case 'tailLogs':
                await this._tailJobLogs(message.jobId);
                break;
                
            case 'reRun':
                await this._reRunWorkflow(message.runId);
                break;
                
            case 'openExternal':
                vscode.env.openExternal(vscode.Uri.parse(message.url));
                break;
        }
    }
    
    /**
     * Post message to webview
     */
    _postMessage(message) {
        if (this.panel) {
            this.panel.webview.postMessage(message);
        }
    }
    
    /**
     * Get webview HTML content
     */
    _getWebviewContent() {
        return `<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>CI/CD Pipeline Status</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell;
            color: var(--vscode-editor-foreground);
            background-color: var(--vscode-editor-background);
            padding: 16px;
        }
        .container { max-width: 100%; }
        .header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 16px;
            border-bottom: 1px solid var(--vscode-panel-border);
            padding-bottom: 12px;
        }
        .header h2 { font-size: 18px; font-weight: 600; }
        .btn {
            padding: 6px 12px;
            background-color: var(--vscode-button-background);
            color: var(--vscode-button-foreground);
            border: none;
            border-radius: 4px;
            cursor: pointer;
            font-size: 12px;
            margin-left: 6px;
        }
        .btn:hover { background-color: var(--vscode-button-hoverBackground); }
        .btn.danger { background-color: var(--vscode-errorForeground); }
        .loading { text-align: center; padding: 20px; color: var(--vscode-descriptionForeground); }
        .workflow-list { list-style: none; }
        .workflow-item {
            padding: 12px;
            margin-bottom: 8px;
            background-color: var(--vscode-input-background);
            border: 1px solid var(--vscode-input-border);
            border-radius: 4px;
            cursor: pointer;
            transition: background-color 0.2s;
        }
        .workflow-item:hover { background-color: var(--vscode-list-hoverBackground); }
        .status-badge {
            display: inline-block;
            padding: 3px 8px;
            border-radius: 3px;
            font-size: 11px;
            font-weight: 600;
            margin-right: 8px;
        }
        .status-success { background-color: #4ec9b0; color: #000; }
        .status-failure { background-color: #f48771; color: #fff; }
        .status-in_progress { background-color: #569cd6; color: #fff; }
        .status-queued { background-color: #dcdcaa; color: #000; }
        .workflow-title { font-weight: 600; margin-bottom: 4px; }
        .workflow-meta { font-size: 12px; color: var(--vscode-descriptionForeground); }
        .jobs-container {
            margin-top: 16px;
            padding: 12px;
            background-color: var(--vscode-input-background);
            border-radius: 4px;
        }
        .job-item {
            margin: 8px 0;
            padding: 8px;
            background-color: var(--vscode-editor-background);
            border-left: 3px solid var(--vscode-focus-border);
            font-size: 12px;
            cursor: pointer;
        }
        .job-item:hover { background-color: var(--vscode-list-hoverBackground); }
        .dag-container {
            margin-top: 12px;
            padding: 12px;
            background-color: var(--vscode-input-background);
            border-radius: 4px;
            font-size: 11px;
            max-height: 300px;
            overflow-y: auto;
        }
        .dag-node {
            padding: 6px;
            margin: 4px 0;
            background-color: var(--vscode-editor-background);
            border-left: 2px solid var(--vscode-focus-border);
            border-radius: 2px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h2>⚙️ CI/CD Pipelines</h2>
            <button class="btn" onclick="refresh()">↻ Refresh</button>
        </div>
        <div id="content">
            <div class="loading">Loading workflows...</div>
        </div>
    </div>

    <script>
        const vscode = acquireVsCodeApi();

        function refresh() {
            vscode.postMessage({ command: 'refresh' });
        }

        function loadJobs(runId) {
            vscode.postMessage({ command: 'loadJobs', runId });
        }

        function tailLogs(jobId) {
            vscode.postMessage({ command: 'tailLogs', jobId });
        }

        function reRun(runId) {
            vscode.postMessage({ command: 'reRun', runId });
        }

        function openExternal(url) {
            vscode.postMessage({ command: 'openExternal', url });
        }

        window.addEventListener('message', (event) => {
            const message = event.data;
            const content = document.getElementById('content');

            switch (message.command) {
                case 'setLoading':
                    if (message.loading && !content.innerHTML.includes('Loading')) {
                        content.innerHTML = '<div class="loading">⏳ Loading...</div>';
                    }
                    break;

                case 'updateWorkflows':
                    const workflowHTML = message.workflows.map(wf => \`
                        <li class="workflow-item" onclick="loadJobs('\${wf.id}')">
                            <div class="workflow-title">
                                <span class="status-badge status-\${wf.status}">\${wf.status}</span>
                                \${wf.name}
                            </div>
                            <div class="workflow-meta">
                                Branch: \${wf.headBranch} • Triggered by: \${wf.triggeredBy}
                            </div>
                            <div class="workflow-meta">
                                \${new Date(wf.createdAt).toLocaleString()}
                            </div>
                        </li>
                    \`).join('');
                    content.innerHTML = \`
                        <ul class="workflow-list">
                            \${workflowHTML}
                        </ul>
                    \`;
                    break;

                case 'showJobs':
                    const jobHTML = message.jobs.map(job => \`
                        <div class="job-item" onclick="tailLogs('\${job.id}')">
                            <strong>\${job.name}</strong> 
                            <span class="status-badge status-\${job.status}">\${job.status}</span>
                            <div style="margin-top: 4px; color: var(--vscode-descriptionForeground);">
                                Runner: \${job.runnerName || 'default'}
                            </div>
                        </div>
                    \`).join('');
                    content.innerHTML = \`
                        <div class="jobs-container">
                            <h3>Jobs for Run #\${message.runId}</h3>
                            <button class="btn" onclick="reRun('\${message.runId}')" style="background-color: var(--vscode-errorForeground);">🔄 Re-run</button>
                            <div style="margin-top: 12px;">
                                \${jobHTML}
                            </div>
                            <div class="dag-container">
                                <h4>Job DAG</h4>
                                \${message.dag.nodes.map(node => \`
                                    <div class="dag-node">📦 \${node.label} (\${node.status})</div>
                                \`).join('')}
                            </div>
                        </div>
                    \`;
                    break;

                case 'showLogs':
                    const logHTML = message.logs.slice(-50).map(log => \`
                        <div style="font-family: monospace; font-size: 11px; margin: 2px 0;">
                            <span style="color: var(--vscode-descriptionForeground);">\${log.lineNumber}:</span> \${log.content}
                        </div>
                    \`).join('');
                    content.innerHTML += \`
                        <div style="margin-top: 12px; padding: 12px; background: var(--vscode-input-background); border-radius: 4px; max-height: 400px; overflow-y: auto;">
                            <h4>Job Logs (last 50 lines)</h4>
                            \${logHTML}
                        </div>
                    \`;
                    break;

                case 'error':
                    content.innerHTML = \`<div style="color: var(--vscode-errorForeground); padding: 16px;">\${message.message}</div>\`;
                    break;
            }
        });

        // Initial refresh
        refresh();
    </script>
</body>
</html>`;
    }
}

module.exports = CICDIntegrationPanel;
