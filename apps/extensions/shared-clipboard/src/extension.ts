// @file apps/extensions/shared-clipboard/src/extension.ts
// @module ide/shared-clipboard
// @description P3-1080 Phase 3: VS Code extension implementation
// @governance GOV-002: All clipboard actions logged and traceable

import * as vscode from 'vscode';
import * as path from 'path';
import { ClipboardManager } from './clipboard-manager';
import { HistoryPanel } from './history-panel';

let clipboardManager: ClipboardManager;
let historyPanel: HistoryPanel | undefined;

export async function activate(context: vscode.ExtensionContext) {
    console.log('[Shared Clipboard] Activating extension');
    
    const dbPath = path.join(context.globalStoragePath, 'clipboard.db');
    clipboardManager = new ClipboardManager(dbPath);
    
    // Initialize storage directory
    await vscode.workspace.fs.createDirectory(
        vscode.Uri.file(context.globalStoragePath)
    ).then(
        () => console.log('[Shared Clipboard] Storage initialized'),
        (err) => console.error('[Shared Clipboard] Storage init failed:', err)
    );
    
    // Command: Open History Panel
    const openHistoryCmd = vscode.commands.registerCommand(
        'sharedClipboard.openHistory',
        async () => {
            console.log('[Shared Clipboard] Opening history panel');
            historyPanel = new HistoryPanel(
                context.extensionUri,
                clipboardManager,
                historyPanel
            );
            historyPanel.show();
        }
    );
    
    // Command: Record Current Selection
    const recordClipCmd = vscode.commands.registerCommand(
        'sharedClipboard.recordClip',
        async () => {
            const editor = vscode.window.activeTextEditor;
            if (!editor) {
                vscode.window.showWarningMessage('No active editor');
                return;
            }
            
            const selection = editor.selection;
            const selectedText = editor.document.getText(selection);
            
            if (!selectedText) {
                vscode.window.showWarningMessage('No text selected');
                return;
            }
            
            const fileName = path.basename(editor.document.fileName);
            const language = editor.document.languageId;
            
            try {
                const clipId = await clipboardManager.addEntry({
                    content: selectedText,
                    fileName,
                    language,
                    tags: [`from:${fileName}`, `lang:${language}`]
                });
                
                vscode.window.showInformationMessage(
                    `Recorded to clipboard history`,
                    'View History'
                ).then((choice) => {
                    if (choice === 'View History') {
                        vscode.commands.executeCommand('sharedClipboard.openHistory');
                    }
                });
                
                console.log(`[Shared Clipboard] Recorded: ${clipId}`);
            } catch (err) {
                vscode.window.showErrorMessage(`Failed to record: ${err}`);
            }
        }
    );
    
    // Command: Clear History
    const clearHistoryCmd = vscode.commands.registerCommand(
        'sharedClipboard.clearHistory',
        async () => {
            const confirm = await vscode.window.showWarningMessage(
                'Clear all clipboard history?',
                { modal: true },
                'Clear'
            );
            
            if (confirm === 'Clear') {
                await clipboardManager.clearHistory();
                vscode.window.showInformationMessage('Clipboard history cleared');
                console.log('[Shared Clipboard] History cleared');
            }
        }
    );
    
    // Command: Share Clip with Team
    const shareClipCmd = vscode.commands.registerCommand(
        'sharedClipboard.shareClip',
        async () => {
            const clipId = await vscode.window.showInputBox({
                prompt: 'Enter clip ID to share',
                ignoreFocusOut: true
            });
            
            if (!clipId) return;
            
            const teamMembers = await vscode.window.showQuickPick(
                ['user-456', 'user-789', 'user-101'],  // Would fetch from API
                {
                    canPickMany: true,
                    placeHolder: 'Select team members to share with'
                }
            );
            
            if (teamMembers && teamMembers.length > 0) {
                await clipboardManager.shareEntry(clipId, teamMembers);
                vscode.window.showInformationMessage(
                    `Shared with ${teamMembers.length} team members`
                );
            }
        }
    );
    
    // Status bar item to show clipboard stats
    const statusBar = vscode.window.createStatusBarItem(
        vscode.StatusBarAlignment.Right,
        100
    );
    statusBar.command = 'sharedClipboard.openHistory';
    statusBar.text = '$(clipboard) 0';
    statusBar.tooltip = 'Clipboard history (Ctrl+Shift+V)';
    statusBar.show();
    
    // Update status bar periodically
    const updateStatus = async () => {
        try {
            const count = await clipboardManager.getEntryCount();
            statusBar.text = `$(clipboard) ${count}`;
        } catch (err) {
            console.error('[Shared Clipboard] Status update failed:', err);
        }
    };
    
    setInterval(updateStatus, 5000);
    updateStatus();
    
    // Auto-record clipboard changes if enabled
    const config = vscode.workspace.getConfiguration('sharedClipboard');
    if (config.get('autoRecord')) {
        let lastClipContent = '';
        
        const monitorClipboard = setInterval(async () => {
            try {
                const clipContent = await vscode.env.clipboard.readText();
                if (clipContent !== lastClipContent && clipContent.length < 10000) {
                    lastClipContent = clipContent;
                    // Auto-record without showing message
                    await clipboardManager.addEntry({
                        content: clipContent,
                        tags: ['auto-recorded']
                    });
                    console.log('[Shared Clipboard] Auto-recorded clipboard change');
                }
            } catch (err) {
                console.error('[Shared Clipboard] Clipboard monitor error:', err);
            }
        }, 2000);
        
        context.subscriptions.push(
            new vscode.Disposable(() => clearInterval(monitorClipboard))
        );
    }
    
    // Subscribe to settings changes
    vscode.workspace.onDidChangeConfiguration((event) => {
        if (event.affectsConfiguration('sharedClipboard')) {
            console.log('[Shared Clipboard] Settings changed, reloading config');
            clipboardManager.reloadConfig();
        }
    });
    
    context.subscriptions.push(
        openHistoryCmd,
        recordClipCmd,
        clearHistoryCmd,
        shareClipCmd,
        statusBar
    );
    
    console.log('[Shared Clipboard] Extension activated successfully');
}

export function deactivate() {
    console.log('[Shared Clipboard] Deactivating extension');
    if (clipboardManager) {
        clipboardManager.dispose();
    }
}
