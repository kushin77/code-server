"""
@file apps/ide-extension/memory-search-provider.ts
@description VS Code IDE integration for organizational memory search
@governance GOV-002
"""

import * as vscode from 'vscode';
import * as fetch from 'node-fetch';

/**
 * Memory Search Provider for organizational memory integration
 */
export class MemorySearchProvider implements vscode.TreeDataProvider<MemoryItem> {
    private _onDidChangeTreeData: vscode.EventEmitter<MemoryItem | undefined | null | void> =
        new vscode.EventEmitter<MemoryItem | undefined | null | void>();
    readonly onDidChangeTreeData: vscode.Event<MemoryItem | undefined | null | void> =
        this._onDidChangeTreeData.event;

    private memoryEngineUrl: string;
    private lastResults: any[] = [];

    constructor(memoryEngineUrl: string = 'http://localhost:8001') {
        this.memoryEngineUrl = memoryEngineUrl;
    }

    /**
     * Execute semantic search in organizational memory
     */
    async searchMemory(
        query: string,
        collection: string = 'incidents',
        limit: number = 10
    ): Promise<MemoryItem[]> {
        try {
            const response = await fetch(
                `${this.memoryEngineUrl}/search?q=${encodeURIComponent(query)}&collection=${collection}&limit=${limit}`,
                { method: 'GET' }
            );

            if (!response.ok) {
                throw new Error(`Search failed: ${response.statusText}`);
            }

            const data = await response.json();
            this.lastResults = data.results || [];
            this._onDidChangeTreeData.fire();

            return this.lastResults.map(
                (result: any) =>
                    new MemoryItem(
                        result.title,
                        vscode.TreeItemCollapsibleState.Collapsed,
                        result
                    )
            );
        } catch (error) {
            vscode.window.showErrorMessage(`Memory search failed: ${error}`);
            return [];
        }
    }

    /**
     * Show memory search input box
     */
    async showSearchInput(): Promise<void> {
        const query = await vscode.window.showInputBox({
            placeHolder: 'Enter your search query (e.g., "502 error after restart")',
            prompt: 'Search organizational memory',
        });

        if (!query) return;

        const collection = await vscode.window.showQuickPick(
            ['incidents', 'runbooks', 'pr_descriptions', 'retrospectives', 'agent_learnings'],
            { placeHolder: 'Select collection' }
        );

        if (!collection) return;

        const results = await this.searchMemory(query, collection);

        if (results.length === 0) {
            vscode.window.showInformationMessage('No results found');
            return;
        }

        vscode.window.showInformationMessage(
            `Found ${results.length} results. Check the Explorer panel.`
        );
    }

    /**
     * Auto-search on error (when file with error is opened)
     */
    async autoSearchOnError(errorText: string): Promise<void> {
        // Extract relevant error info
        const errorMatch = errorText.match(/error:?\s*(.+)/i);
        if (!errorMatch) return;

        const errorMessage = errorMatch[1].substring(0, 100);

        try {
            const response = await fetch(
                `${this.memoryEngineUrl}/search?q=${encodeURIComponent(errorMessage)}&collection=incidents&limit=5`
            );

            if (!response.ok) return;

            const data = await response.json();

            if (data.results && data.results.length > 0) {
                const result = data.results[0];
                const message = `Related incident found: "${result.title}" (${(result.relevance_score * 100).toFixed(0)}% match)`;

                vscode.window.showInformationMessage(
                    message,
                    'View',
                    'Dismiss'
                );
            }
        } catch (error) {
            // Silently fail for auto-search
        }
    }

    getTreeItem(element: MemoryItem): vscode.TreeItem {
        return element;
    }

    getChildren(element?: MemoryItem): Thenable<MemoryItem[]> {
        if (!element) {
            // Root level
            return Promise.resolve(
                this.lastResults.map(
                    (result: any) =>
                        new MemoryItem(
                            result.title,
                            vscode.TreeItemCollapsibleState.Collapsed,
                            result
                        )
                )
            );
        } else {
            // Expand to show details
            const result = element.metadata;
            const items = [
                new MemoryItem(`Score: ${(result.relevance_score * 100).toFixed(0)}%`, vscode.TreeItemCollapsibleState.None),
                new MemoryItem(`Confidence: ${(result.confidence_score * 100).toFixed(0)}%`, vscode.TreeItemCollapsibleState.None),
                new MemoryItem(`Collection: ${result.source}`, vscode.TreeItemCollapsibleState.None),
            ];

            if (result.url) {
                items.push(
                    new MemoryItem(
                        `URL: ${result.url}`,
                        vscode.TreeItemCollapsibleState.None,
                        result,
                        true
                    )
                );
            }

            items.push(
                new MemoryItem(
                    `Summary: ${result.summary}`,
                    vscode.TreeItemCollapsibleState.None
                )
            );

            return Promise.resolve(items);
        }
    }
}

/**
 * Tree item representing a memory result
 */
class MemoryItem extends vscode.TreeItem {
    constructor(
        public readonly label: string,
        public readonly collapsibleState: vscode.TreeItemCollapsibleState,
        public metadata?: any,
        public isLink: boolean = false
    ) {
        super(label, collapsibleState);

        if (isLink && metadata?.url) {
            this.command = {
                command: 'vscode.open',
                title: 'Open URL',
                arguments: [vscode.Uri.parse(metadata.url)],
            };
            this.iconPath = new vscode.ThemeIcon('link-external');
        } else {
            this.iconPath = new vscode.ThemeIcon('book');
        }
    }
}

/**
 * Command to integrate with extension
 */
export function registerMemorySearchCommands(
    context: vscode.ExtensionContext,
    provider: MemorySearchProvider
): void {
    // Search command
    context.subscriptions.push(
        vscode.commands.registerCommand(
            'elevatediq.searchMemory',
            () => provider.showSearchInput()
        )
    );

    // Auto-search on error in active editor
    context.subscriptions.push(
        vscode.window.onDidChangeActiveTextEditor(async (editor) => {
            if (!editor) return;

            const text = editor.document.getText();
            const errorMatch = text.match(/error|Error|ERROR|Exception|FATAL/);

            if (errorMatch) {
                await provider.autoSearchOnError(text.substring(0, 500));
            }
        })
    );
}
