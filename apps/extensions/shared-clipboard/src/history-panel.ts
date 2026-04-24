// @file apps/extensions/shared-clipboard/src/history-panel.ts
// @module ide/shared-clipboard
// @description P3-1080 Phase 3c: Webview UI for clipboard history
// @governance GOV-002: All user interactions logged

import * as vscode from 'vscode';
import { ClipboardManager, ClipboardEntry } from './clipboard-manager';

export class HistoryPanel {
    public static readonly viewType = 'sharedClipboard.history';
    private panel: vscode.WebviewPanel;
    private manager: ClipboardManager;
    private entries: ClipboardEntry[] = [];
    private searchQuery: string = '';
    
    constructor(
        extensionUri: vscode.Uri,
        manager: ClipboardManager,
        oldPanel?: HistoryPanel
    ) {
        this.manager = manager;
        
        // Reuse existing panel if available
        if (oldPanel?.panel) {
            this.panel = oldPanel.panel;
        } else {
            this.panel = vscode.window.createWebviewPanel(
                HistoryPanel.viewType,
                'Clipboard History',
                vscode.ViewColumn.Beside,
                { enableScripts: true, retainContextWhenHidden: true }
            );
        }
        
        this.panel.webview.onDidReceiveMessage(
            (message) => this.handleMessage(message),
            undefined
        );
        
        this.panel.onDidDispose(() => {
            console.log('[Shared Clipboard] History panel closed');
        });
        
        this.refresh();
    }
    
    public show() {
        this.panel.reveal();
    }
    
    private async refresh() {
        try {
            if (this.searchQuery) {
                this.entries = await this.manager.search(this.searchQuery, 50);
            } else {
                this.entries = await this.manager.getEntries(50, 0);
            }
            this.updatePanel();
        } catch (err) {
            console.error('[Shared Clipboard] Refresh failed:', err);
        }
    }
    
    private async handleMessage(message: any) {
        console.log('[Shared Clipboard] Message received:', message.command);
        
        switch (message.command) {
            case 'paste':
                await this.pasteEntry(message.clipId);
                break;
            case 'copy':
                await this.copyEntryId(message.clipId);
                break;
            case 'delete':
                await this.deleteEntry(message.clipId);
                break;
            case 'share':
                await this.shareEntry(message.clipId, message.users);
                break;
            case 'tag':
                await this.addTag(message.clipId, message.tag);
                break;
            case 'search':
                this.searchQuery = message.query;
                await this.refresh();
                break;
            case 'audit':
                await this.showAuditLog(message.clipId);
                break;
        }
    }
    
    private async pasteEntry(clipId: string) {
        const entry = await this.manager.getEntryById(clipId);
        if (!entry) return;
        
        const editor = vscode.window.activeTextEditor;
        if (!editor) {
            vscode.window.showWarningMessage('No active editor');
            return;
        }
        
        // Insert at cursor position
        await editor.edit((editBuilder) => {
            editBuilder.insert(editor.selection.active, entry.content);
        });
        
        vscode.window.showInformationMessage('Pasted from clipboard history');
        console.log(`[Shared Clipboard] Pasted: ${clipId}`);
    }
    
    private async copyEntryId(clipId: string) {
        const entry = await this.manager.getEntryById(clipId);
        if (!entry) return;
        
        await vscode.env.clipboard.writeText(entry.content);
        vscode.window.showInformationMessage('Copied to clipboard');
    }
    
    private async deleteEntry(clipId: string) {
        const confirm = await vscode.window.showWarningMessage(
            'Delete this clipboard entry?',
            'Delete'
        );
        
        if (confirm === 'Delete') {
            await this.manager.deleteEntry(clipId);
            await this.refresh();
            vscode.window.showInformationMessage('Entry deleted');
        }
    }
    
    private async shareEntry(clipId: string, userIds: string[]) {
        if (userIds.length === 0) return;
        
        await this.manager.shareEntry(clipId, userIds);
        await this.refresh();
        vscode.window.showInformationMessage(`Shared with ${userIds.length} users`);
    }
    
    private async addTag(clipId: string, tag: string) {
        if (!tag) return;
        
        await this.manager.addTags(clipId, [tag]);
        await this.refresh();
    }
    
    private async showAuditLog(clipId: string) {
        const events = await this.manager.getAuditLog(clipId);
        
        const items = events.map((e) => ({
            label: `${e.action} by ${e.user_id}`,
            description: e.timestamp,
            detail: e.changes ? JSON.stringify(e.changes) : ''
        }));
        
        vscode.window.showQuickPick(items, {
            placeHolder: 'Audit events for this clip'
        });
    }
    
    private updatePanel() {
        this.panel.webview.html = this.getHtml();
    }
    
    private getHtml(): string {
        const entries = this.entries.map((e) => `
            <div class="entry" data-clip-id="${e.id}">
                <div class="header">
                    <div class="meta">
                        <span class="file">${e.fileName || 'unnamed'}</span>
                        <span class="lang">${e.language || 'text'}</span>
                        <span class="date">${new Date(e.timestamp).toLocaleString()}</span>
                    </div>
                    ${e.shared ? '<span class="badge">Shared</span>' : ''}
                </div>
                <div class="content">${this.escapeHtml(e.content.substring(0, 200))}</div>
                <div class="tags">
                    ${e.tags.map((t) => `<span class="tag">${t}</span>`).join('')}
                </div>
                <div class="actions">
                    <button onclick="vscode.postMessage({command: 'paste', clipId: '${e.id}'})" class="btn btn-primary">Paste</button>
                    <button onclick="vscode.postMessage({command: 'copy', clipId: '${e.id}'})" class="btn">Copy</button>
                    <button onclick="vscode.postMessage({command: 'share', clipId: '${e.id}', users: ['user-456']})" class="btn">Share</button>
                    <button onclick="vscode.postMessage({command: 'audit', clipId: '${e.id}'})" class="btn">Audit</button>
                    <button onclick="vscode.postMessage({command: 'delete', clipId: '${e.id}'})" class="btn btn-danger">Delete</button>
                </div>
            </div>
        `).join('');
        
        return `
            <!DOCTYPE html>
            <html>
            <head>
                <style>
                    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; }
                    .search { margin-bottom: 15px; }
                    .search input { width: 100%; padding: 8px; border: 1px solid #ddd; border-radius: 4px; }
                    .entry { border: 1px solid #e0e0e0; margin-bottom: 10px; border-radius: 4px; padding: 12px; }
                    .entry:hover { background: #f5f5f5; }
                    .header { display: flex; justify-content: space-between; margin-bottom: 8px; font-size: 12px; }
                    .meta span { margin-right: 8px; }
                    .content { font-family: monospace; font-size: 11px; background: #f8f8f8; padding: 8px; border-radius: 3px; max-height: 60px; overflow: hidden; margin-bottom: 8px; }
                    .tags { margin-bottom: 8px; }
                    .tag { display: inline-block; background: #e8e8ff; color: #0066cc; padding: 2px 6px; border-radius: 3px; margin-right: 4px; font-size: 11px; }
                    .badge { background: #90EE90; padding: 2px 6px; border-radius: 3px; font-size: 11px; }
                    .actions { display: flex; gap: 4px; flex-wrap: wrap; }
                    .btn { padding: 4px 8px; border: 1px solid #ddd; background: #f0f0f0; border-radius: 3px; cursor: pointer; font-size: 11px; }
                    .btn:hover { background: #e0e0e0; }
                    .btn-primary { background: #0066cc; color: white; border-color: #0066cc; }
                    .btn-danger { background: #cc0000; color: white; border-color: #cc0000; }
                </style>
            </head>
            <body>
                <div class="search">
                    <input type="text" id="searchInput" placeholder="Search clipboard history..." />
                </div>
                <div id="entries">${entries}</div>
                <script>
                    const vscode = acquireVsCodeApi();
                    document.getElementById('searchInput').addEventListener('change', (e) => {
                        vscode.postMessage({command: 'search', query: e.target.value});
                    });
                </script>
            </body>
            </html>
        `;
    }
    
    private escapeHtml(text: string): string {
        return text
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
    }
}
