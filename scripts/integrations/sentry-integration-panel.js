#!/usr/bin/env node
/**
 * @file        scripts/integrations/sentry-integration-panel.js
 * @module      integrations/sentry
 * @description VS Code WebView panel for browsing and fixing Sentry errors
 */

const vscode = require('vscode');

class SentryIntegrationPanel {
    constructor(context, apiEndpoint = 'http://localhost:9095') {
        this.context = context;
        this.apiEndpoint = apiEndpoint;
        this.panel = null;
        this.webviewApi = null;
        this.currentError = null;
        this.errorList = [];
        this.isLoading = false;
    }
    
    /**
     * Show the Sentry integration panel
     */
    show() {
        if (this.panel) {
            this.panel.reveal(vscode.ViewColumn.Beside);
            return;
        }
        
        // Create panel
        this.panel = vscode.window.createWebviewPanel(
            'sentryIntegration',
            'Sentry Errors',
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
            light: vscode.Uri.file(this.context.asAbsolutePath('media/sentry-light.svg')),
            dark: vscode.Uri.file(this.context.asAbsolutePath('media/sentry-dark.svg'))
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
        });
        
        // Load initial errors
        this._refreshErrorList();
    }
    
    /**
     * Refresh error list from API
     */
    async _refreshErrorList() {
        try {
            this.isLoading = true;
            this._postMessage({ command: 'setLoading', loading: true });
            
            const response = await fetch(`${this.apiEndpoint}/api/sentry/errors?limit=50`);
            const data = await response.json();
            
            if (data.success) {
                this.errorList = data.errors;
                this._postMessage({
                    command: 'updateErrorList',
                    errors: data.errors,
                    total: data.total
                });
            }
        } catch (error) {
            vscode.window.showErrorMessage(`Failed to fetch errors: ${error.message}`);
            this._postMessage({
                command: 'error',
                message: `Failed to fetch errors: ${error.message}`
            });
        } finally {
            this.isLoading = false;
            this._postMessage({ command: 'setLoading', loading: false });
        }
    }
    
    /**
     * Load detailed error information
     */
    async _loadErrorDetails(errorId) {
        try {
            this._postMessage({ command: 'setLoading', loading: true });
            
            const response = await fetch(`${this.apiEndpoint}/api/sentry/errors/${errorId}`);
            const data = await response.json();
            
            if (data.success) {
                this.currentError = data.error;
                this._postMessage({
                    command: 'showErrorDetails',
                    error: data.error
                });
            }
        } catch (error) {
            vscode.window.showErrorMessage(`Failed to load error details: ${error.message}`);
        } finally {
            this._postMessage({ command: 'setLoading', loading: false });
        }
    }
    
    /**
     * Navigate to source location from stack frame
     */
    async _goToStackFrame(frame) {
        try {
            // Parse the filename
            const filename = frame.filename;
            const lineNumber = frame.lineNo || 1;
            
            // Try to find the file in workspace
            const files = await vscode.workspace.findFiles(`**/${filename}`);
            
            if (files.length === 0) {
                vscode.window.showWarningMessage(`Could not find file: ${filename}`);
                return;
            }
            
            // Open the file
            const document = await vscode.workspace.openTextDocument(files[0]);
            const editor = await vscode.window.showTextDocument(document);
            
            // Scroll to line
            const position = new vscode.Position(lineNumber - 1, 0);
            editor.selection = new vscode.Selection(position, position);
            editor.revealRange(
                new vscode.Range(position, position),
                vscode.TextEditorRevealType.InCenter
            );
            
            // Highlight the line temporarily
            const decoration = vscode.window.createTextEditorDecorationType({
                backgroundColor: new vscode.ThemeColor('editor.findMatchHighlightBackground'),
                isWholeLine: true
            });
            
            editor.setDecorations(decoration, [
                new vscode.Range(position, position.translate(0, Number.MAX_VALUE))
            ]);
            
            // Clear highlight after 2 seconds
            setTimeout(() => {
                editor.setDecorations(decoration, []);
                decoration.dispose();
            }, 2000);
            
            // Show blame for this line
            this._showLineBlame(document, lineNumber);
            
        } catch (error) {
            vscode.window.showErrorMessage(`Failed to navigate to line: ${error.message}`);
        }
    }
    
    /**
     * Show git blame for a line
     */
    async _showLineBlame(document, lineNumber) {
        try {
            const gitExtension = vscode.extensions.getExtension('vscode.git');
            if (!gitExtension) {
                console.log('[Sentry] Git extension not available for blame');
                return;
            }
            
            // Get git API
            const git = gitExtension.isActive ? gitExtension.exports.getAPI(1) : null;
            if (!git) {
                console.log('[Sentry] Git API not available');
                return;
            }
            
            // Try to get blame information
            const repo = git.repositories[0];
            if (!repo) {
                console.log('[Sentry] No git repository found');
                return;
            }
            
            this._postMessage({
                command: 'showBlame',
                lineNumber,
                blame: {
                    author: 'Unknown',
                    date: new Date().toISOString(),
                    message: 'Blame information loading...'
                }
            });
            
        } catch (error) {
            console.log(`[Sentry] Could not fetch blame: ${error.message}`);
        }
    }
    
    /**
     * Generate AI fix suggestion
     */
    async _generateAIFix(errorId) {
        try {
            this._postMessage({ command: 'setLoading', loading: true });
            
            const response = await fetch(`${this.apiEndpoint}/api/sentry/ai-fix`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({
                    errorId,
                    stackTrace: this.currentError?.stackTrace || [],
                    errorMessage: this.currentError?.title,
                    errorType: this.currentError?.type
                })
            });
            
            const data = await response.json();
            
            if (data.success) {
                this._postMessage({
                    command: 'showFixSuggestion',
                    suggestion: data.suggestion
                });
                
                // Show notification
                vscode.window.showInformationMessage(
                    `Fix suggestion generated (Confidence: ${Math.round(data.suggestion.confidence * 100)}%)`,
                    'View', 'Apply'
                ).then(async (selection) => {
                    if (selection === 'Apply' && data.suggestion.codeSnippet) {
                        this._applyFixSuggestion(data.suggestion);
                    }
                });
            }
        } catch (error) {
            vscode.window.showErrorMessage(`Failed to generate fix: ${error.message}`);
        } finally {
            this._postMessage({ command: 'setLoading', loading: false });
        }
    }
    
    /**
     * Apply a fix suggestion to the editor
     */
    async _applyFixSuggestion(suggestion) {
        const editor = vscode.window.activeTextEditor;
        if (!editor) {
            vscode.window.showWarningMessage('No active editor');
            return;
        }
        
        // Insert code snippet at cursor
        await editor.edit((editBuilder) => {
            editBuilder.insert(editor.selection.active, `\n// Fix suggestion (confidence: ${suggestion.confidence})\n${suggestion.codeSnippet}`);
        });
        
        vscode.window.showInformationMessage('Fix suggestion applied. Please review and test.');
    }
    
    /**
     * Resolve error in Sentry
     */
    async _resolveError(groupId, resolution = 'fixed') {
        try {
            const response = await fetch(`${this.apiEndpoint}/api/sentry/errors/${groupId}/resolve`, {
                method: 'PUT',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({ resolution })
            });
            
            const data = await response.json();
            
            if (data.success) {
                vscode.window.showInformationMessage(`Error resolved as "${resolution}"`);
                this._refreshErrorList();
            }
        } catch (error) {
            vscode.window.showErrorMessage(`Failed to resolve error: ${error.message}`);
        }
    }
    
    /**
     * Handle messages from webview
     */
    async _handleWebviewMessage(message) {
        switch (message.command) {
            case 'refresh':
                await this._refreshErrorList();
                break;
                
            case 'loadError':
                await this._loadErrorDetails(message.errorId);
                break;
                
            case 'goToFrame':
                await this._goToStackFrame(message.frame);
                break;
                
            case 'generateFix':
                await this._generateAIFix(message.errorId);
                break;
                
            case 'resolveError':
                await this._resolveError(message.groupId, message.resolution);
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
    <title>Sentry Integration</title>
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
        }
        .btn:hover { background-color: var(--vscode-button-hoverBackground); }
        .loading { text-align: center; padding: 20px; color: var(--vscode-descriptionForeground); }
        .error-list { list-style: none; }
        .error-item {
            padding: 12px;
            margin-bottom: 8px;
            background-color: var(--vscode-input-background);
            border: 1px solid var(--vscode-input-border);
            border-radius: 4px;
            cursor: pointer;
            transition: background-color 0.2s;
        }
        .error-item:hover { background-color: var(--vscode-list-hoverBackground); }
        .error-level-error { border-left: 4px solid #f48771; }
        .error-level-warning { border-left: 4px solid #dcdcaa; }
        .error-level-info { border-left: 4px solid #4ec9b0; }
        .error-title { font-weight: 600; margin-bottom: 4px; }
        .error-meta { font-size: 12px; color: var(--vscode-descriptionForeground); }
        .error-details {
            margin-top: 16px;
            padding: 12px;
            background-color: var(--vscode-input-background);
            border-radius: 4px;
        }
        .stack-frame {
            margin: 8px 0;
            padding: 8px;
            background-color: var(--vscode-editor-background);
            border-left: 2px solid var(--vscode-focus-border);
            font-family: 'Courier New', monospace;
            font-size: 11px;
            cursor: pointer;
        }
        .stack-frame:hover { background-color: var(--vscode-list-hoverBackground); }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h2>🔴 Sentry Errors</h2>
            <button class="btn" onclick="refresh()">↻ Refresh</button>
        </div>
        <div id="content">
            <div class="loading">Loading errors...</div>
        </div>
    </div>

    <script>
        const vscode = acquireVsCodeApi();

        function refresh() {
            vscode.postMessage({ command: 'refresh' });
        }

        function loadError(errorId) {
            vscode.postMessage({ command: 'loadError', errorId });
        }

        function goToFrame(frameIndex) {
            const error = window.currentError;
            if (error && error.stackTrace[frameIndex]) {
                vscode.postMessage({ command: 'goToFrame', frame: error.stackTrace[frameIndex] });
            }
        }

        function generateFix(errorId) {
            vscode.postMessage({ command: 'generateFix', errorId });
        }

        function resolveError(groupId) {
            vscode.postMessage({ command: 'resolveError', groupId, resolution: 'fixed' });
        }

        window.addEventListener('message', (event) => {
            const message = event.data;
            const content = document.getElementById('content');

            switch (message.command) {
                case 'setLoading':
                    if (message.loading) {
                        content.innerHTML = '<div class="loading">⏳ Loading...</div>';
                    }
                    break;

                case 'updateErrorList':
                    const errorHTML = message.errors.map(error => \`
                        <li class="error-item error-level-\${error.level}" onclick="loadError('\${error.id}')">
                            <div class="error-title">\${error.title}</div>
                            <div class="error-meta">\${error.culprit} • \${error.count} occurrences</div>
                            <div class="error-meta">\${new Date(error.timestamp).toLocaleString()}</div>
                        </li>
                    \`).join('');
                    content.innerHTML = \`
                        <ul class="error-list">
                            \${errorHTML}
                        </ul>
                    \`;
                    break;

                case 'showErrorDetails':
                    window.currentError = message.error;
                    const stackHTML = message.error.stackTrace.slice(0, 5).map((frame, i) => \`
                        <div class="stack-frame" onclick="goToFrame(\${i})">
                            \${frame.function} → \${frame.filename}:\${frame.lineNo}
                        </div>
                    \`).join('');
                    content.innerHTML = \`
                        <div class="error-details">
                            <h3>\${message.error.title}</h3>
                            <p>\${message.error.message}</p>
                            <div style="margin-top: 12px;">
                                <button class="btn" onclick="generateFix('\${message.error.id}')" style="margin-right: 8px;">🔧 Fix with AI</button>
                                <button class="btn" onclick="resolveError('\${message.error.id}')">✓ Resolve</button>
                            </div>
                            <h4 style="margin-top: 16px;">Stack Trace:</h4>
                            \${stackHTML}
                        </div>
                    \`;
                    break;

                case 'showFixSuggestion':
                    content.innerHTML += \`
                        <div style="margin-top: 12px; padding: 12px; background: var(--vscode-statusBar-debuggingBackground); border-radius: 4px;">
                            <strong>Fix Suggestion (Confidence: \${Math.round(message.suggestion.confidence * 100)}%)</strong>
                            <p style="margin-top: 8px;">\${message.suggestion.explanation}</p>
                            <pre style="margin-top: 8px; padding: 8px; background: var(--vscode-input-background); border-radius: 4px; overflow-x: auto;">\${message.suggestion.codeSnippet || 'No code snippet'}</pre>
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

module.exports = SentryIntegrationPanel;
