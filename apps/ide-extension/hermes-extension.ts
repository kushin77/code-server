import * as vscode from 'vscode';

/**
 * Hermes Agent Integration Extension for code-server
 * Provides IDE integration for phase generation, testing, and management
 */

export class HermesExtension {
    private context: vscode.ExtensionContext;
    private panel: vscode.WebviewPanel | undefined;
    private apiEndpoint: string;

    constructor(context: vscode.ExtensionContext) {
        this.context = context;
        this.apiEndpoint = vscode.workspace.getConfiguration('hermes').get('apiEndpoint') || 'http://localhost:8000';
    }

    /**
     * Activate the extension
     */
    async activate(): Promise<void> {
        console.log('Hermes Agent Integration activated');

        // Register commands
        this.registerCommands();

        // Create sidebar view
        this.createSidebarProvider();
    }

    /**
     * Register extension commands
     */
    private registerCommands(): void {
        // Open Hermes panel
        this.context.subscriptions.push(
            vscode.commands.registerCommand('hermes.openPanel', () => this.showPanel())
        );

        // Get metrics
        this.context.subscriptions.push(
            vscode.commands.registerCommand('hermes.getMetrics', () => this.getMetrics())
        );

        // Run tests for current phase
        this.context.subscriptions.push(
            vscode.commands.registerCommand('hermes.testPhase', () => this.testCurrentPhase())
        );

        // Quality check
        this.context.subscriptions.push(
            vscode.commands.registerCommand('hermes.qualityCheck', () => this.runQualityCheck())
        );

        // Commit phase
        this.context.subscriptions.push(
            vscode.commands.registerCommand('hermes.commitPhase', () => this.commitPhase())
        );

        // View git log
        this.context.subscriptions.push(
            vscode.commands.registerCommand('hermes.gitLog', () => this.showGitLog())
        );
    }

    /**
     * Show Hermes control panel
     */
    private showPanel(): void {
        if (this.panel) {
            this.panel.reveal(vscode.ViewColumn.Beside);
            return;
        }

        this.panel = vscode.window.createWebviewPanel(
            'hermesPanel',
            'Hermes Agent Control',
            vscode.ViewColumn.Beside,
            { enableScripts: true }
        );

        this.panel.webview.html = this.getWebviewContent();

        // Handle messages from webview
        this.panel.webview.onDidReceiveMessage((message) => this.handleWebviewMessage(message));

        this.panel.onDidDispose(() => {
            this.panel = undefined;
        });

        // Load initial data
        this.refreshPanelData();
    }

    /**
     * Create sidebar provider
     */
    private createSidebarProvider(): void {
        vscode.window.registerTreeDataProvider(
            'hermesExplorer',
            new HermesTreeDataProvider(this.apiEndpoint)
        );
    }

    /**
     * Get platform metrics
     */
    private async getMetrics(): Promise<void> {
        try {
            const response = await fetch(`${this.apiEndpoint}/metrics`);
            const metrics = await response.json();

            vscode.window.showInformationMessage(
                `Hermes Status: ${metrics.total_phases} phases, ${metrics.total_tests} tests, ` +
                `${metrics.avg_tests_per_phase.toFixed(1)} avg/phase`
            );
        } catch (error) {
            vscode.window.showErrorMessage(`Failed to get metrics: ${error}`);
        }
    }

    /**
     * Test current phase
     */
    private async testCurrentPhase(): Promise<void> {
        const editor = vscode.window.activeTextEditor;
        if (!editor) {
            vscode.window.showErrorMessage('No active editor');
            return;
        }

        const filename = editor.document.fileName;
        const match = filename.match(/test_phase_(\d+)/);
        if (!match) {
            vscode.window.showErrorMessage('Current file is not a phase test file');
            return;
        }

        const phaseNum = parseInt(match[1]);
        await vscode.window.withProgress(
            { location: vscode.ProgressLocation.Notification, title: `Testing Phase ${phaseNum}...` },
            async () => {
                try {
                    const response = await fetch(`${this.apiEndpoint}/phases/${phaseNum}/test`, {
                        method: 'POST'
                    });
                    const result = await response.json();

                    const message = `Phase ${phaseNum}: ${result.passed}/${result.total} tests passed`;
                    if (result.failed === 0) {
                        vscode.window.showInformationMessage(message);
                    } else {
                        vscode.window.showWarningMessage(message);
                    }
                } catch (error) {
                    vscode.window.showErrorMessage(`Test failed: ${error}`);
                }
            }
        );
    }

    /**
     * Run quality checks
     */
    private async runQualityCheck(): Promise<void> {
        const editor = vscode.window.activeTextEditor;
        if (!editor) {
            vscode.window.showErrorMessage('No active editor');
            return;
        }

        const filename = editor.document.fileName;
        const match = filename.match(/test_phase_(\d+)/);
        if (!match) {
            vscode.window.showErrorMessage('Current file is not a phase test file');
            return;
        }

        const phaseNum = parseInt(match[1]);
        await vscode.window.withProgress(
            { location: vscode.ProgressLocation.Notification, title: `Running quality checks for Phase ${phaseNum}...` },
            async () => {
                try {
                    const response = await fetch(`${this.apiEndpoint}/phases/${phaseNum}/quality`, {
                        method: 'POST'
                    });
                    const result = await response.json();

                    const status = `pytest: ${result.pytest_passed ? '✓' : '✗'}, ` +
                        `mypy: ${result.mypy_passed ? '✓' : '✗'}, ` +
                        `ruff: ${result.ruff_passed ? '✓' : '✗'}`;

                    if (result.all_passed) {
                        vscode.window.showInformationMessage(`Phase ${phaseNum} Quality: ${status}`);
                    } else {
                        vscode.window.showWarningMessage(`Phase ${phaseNum} Quality: ${status}`);
                    }
                } catch (error) {
                    vscode.window.showErrorMessage(`Quality check failed: ${error}`);
                }
            }
        );
    }

    /**
     * Commit phase
     */
    private async commitPhase(): Promise<void> {
        const editor = vscode.window.activeTextEditor;
        if (!editor) {
            vscode.window.showErrorMessage('No active editor');
            return;
        }

        const filename = editor.document.fileName;
        const match = filename.match(/test_phase_(\d+)/);
        if (!match) {
            vscode.window.showErrorMessage('Current file is not a phase test file');
            return;
        }

        const phaseNum = parseInt(match[1]);
        const result = await vscode.window.showInputBox({
            prompt: 'Enter number of classes (default 6):',
            value: '6'
        });

        if (result === undefined) return;

        const classes = parseInt(result) || 6;
        const testResult = await vscode.window.showInputBox({
            prompt: 'Enter number of tests (default 21):',
            value: '21'
        });

        if (testResult === undefined) return;

        const tests = parseInt(testResult) || 21;

        await vscode.window.withProgress(
            { location: vscode.ProgressLocation.Notification, title: `Committing Phase ${phaseNum}...` },
            async () => {
                try {
                    const response = await fetch(`${this.apiEndpoint}/phases/${phaseNum}/commit`, {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ classes, tests })
                    });
                    const result = await response.json();

                    if (result.success) {
                        vscode.window.showInformationMessage(
                            `Phase ${phaseNum} committed: ${result.commit_hash}`
                        );
                    } else {
                        vscode.window.showErrorMessage(result.detail || 'Commit failed');
                    }
                } catch (error) {
                    vscode.window.showErrorMessage(`Commit failed: ${error}`);
                }
            }
        );
    }

    /**
     * Show git log
     */
    private async showGitLog(): Promise<void> {
        try {
            const response = await fetch(`${this.apiEndpoint}/git/log?limit=20`);
            const data = await response.json();

            const items = data.commits.map((c: any) => 
                `${c.hash} ${c.message}`
            );

            const selected = await vscode.window.showQuickPick(
                items,
                { placeHolder: 'Recent commits...' }
            );

            if (selected) {
                vscode.window.showInformationMessage(`Commit: ${selected}`);
            }
        } catch (error) {
            vscode.window.showErrorMessage(`Failed to fetch git log: ${error}`);
        }
    }

    /**
     * Handle webview messages
     */
    private handleWebviewMessage(message: any): void {
        switch (message.command) {
            case 'refresh':
                this.refreshPanelData();
                break;
        }
    }

    /**
     * Refresh panel data
     */
    private async refreshPanelData(): Promise<void> {
        if (!this.panel) return;

        try {
            const metricsResponse = await fetch(`${this.apiEndpoint}/metrics`);
            const metrics = await metricsResponse.json();

            this.panel.webview.postMessage({
                command: 'updateMetrics',
                data: metrics
            });
        } catch (error) {
            console.error('Failed to refresh data:', error);
        }
    }

    /**
     * Generate webview HTML content
     */
    private getWebviewContent(): string {
        return `
            <!DOCTYPE html>
            <html>
            <head>
                <style>
                    body { font-family: var(--vscode-font-family); padding: 20px; }
                    h2 { color: var(--vscode-foreground); margin-top: 0; }
                    .metric { margin: 10px 0; padding: 10px; background: var(--vscode-editor-background); }
                    .metric-label { color: var(--vscode-descriptionForeground); }
                    .metric-value { font-weight: bold; color: var(--vscode-terminal-ansiGreen); font-size: 1.2em; }
                    button { 
                        margin: 5px 5px 5px 0;
                        padding: 8px 16px;
                        background: var(--vscode-button-background);
                        color: var(--vscode-button-foreground);
                        border: none;
                        cursor: pointer;
                        border-radius: 2px;
                    }
                    button:hover { background: var(--vscode-button-hoverBackground); }
                    .section { margin-top: 20px; }
                </style>
            </head>
            <body>
                <h2>Hermes Agent Control</h2>
                
                <div class="section">
                    <h3>Platform Status</h3>
                    <div class="metric">
                        <div class="metric-label">Phases Complete:</div>
                        <div class="metric-value" id="phasesCount">-</div>
                    </div>
                    <div class="metric">
                        <div class="metric-label">Total Tests:</div>
                        <div class="metric-value" id="testsCount">-</div>
                    </div>
                    <div class="metric">
                        <div class="metric-label">Avg Tests/Phase:</div>
                        <div class="metric-value" id="avgTests">-</div>
                    </div>
                </div>

                <div class="section">
                    <h3>Actions</h3>
                    <button onclick="vscode.postMessage({command: 'testPhase'})">Test Phase</button>
                    <button onclick="vscode.postMessage({command: 'qualityCheck'})">Quality Check</button>
                    <button onclick="vscode.postMessage({command: 'commitPhase'})">Commit Phase</button>
                    <button onclick="vscode.postMessage({command: 'gitLog'})">Git Log</button>
                    <button onclick="vscode.postMessage({command: 'refresh'})">Refresh</button>
                </div>

                <script>
                    const vscode = acquireVsCodeApi();

                    window.addEventListener('message', event => {
                        const message = event.data;
                        if (message.command === 'updateMetrics') {
                            const data = message.data;
                            document.getElementById('phasesCount').textContent = data.total_phases || 0;
                            document.getElementById('testsCount').textContent = data.total_tests || 0;
                            document.getElementById('avgTests').textContent = 
                                (data.avg_tests_per_phase || 0).toFixed(1);
                        }
                    });

                    // Initial load
                    vscode.postMessage({command: 'refresh'});
                </script>
            </body>
            </html>
        `;
    }
}

/**
 * Tree data provider for Hermes explorer
 */
class HermesTreeDataProvider implements vscode.TreeDataProvider<HermesTreeItem> {
    private apiEndpoint: string;
    private _onDidChangeTreeData = new vscode.EventEmitter<HermesTreeItem | undefined>();
    readonly onDidChangeTreeData = this._onDidChangeTreeData.event;

    constructor(apiEndpoint: string) {
        this.apiEndpoint = apiEndpoint;
    }

    getTreeItem(element: HermesTreeItem): vscode.TreeItem {
        return element;
    }

    async getChildren(element?: HermesTreeItem): Promise<HermesTreeItem[]> {
        if (!element) {
            return [
                new HermesTreeItem('Metrics', vscode.TreeItemCollapsibleState.Collapsed),
                new HermesTreeItem('Phases', vscode.TreeItemCollapsibleState.Collapsed),
                new HermesTreeItem('Recent Commits', vscode.TreeItemCollapsibleState.Collapsed)
            ];
        }

        if (element.label === 'Metrics') {
            try {
                const response = await fetch(`${this.apiEndpoint}/metrics`);
                const metrics = await response.json();
                return [
                    new HermesTreeItem(`Total Phases: ${metrics.total_phases}`, vscode.TreeItemCollapsibleState.None),
                    new HermesTreeItem(`Total Tests: ${metrics.total_tests}`, vscode.TreeItemCollapsibleState.None),
                    new HermesTreeItem(`Avg/Phase: ${metrics.avg_tests_per_phase.toFixed(1)}`, vscode.TreeItemCollapsibleState.None)
                ];
            } catch (error) {
                return [new HermesTreeItem(`Error: ${error}`, vscode.TreeItemCollapsibleState.None)];
            }
        }

        return [];
    }
}

class HermesTreeItem extends vscode.TreeItem {
    constructor(label: string, collapsibleState: vscode.TreeItemCollapsibleState) {
        super(label, collapsibleState);
    }
}

export function activate(context: vscode.ExtensionContext) {
    const extension = new HermesExtension(context);
    extension.activate();
}

export function deactivate() {}
