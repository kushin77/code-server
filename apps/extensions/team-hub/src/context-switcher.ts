#!/usr/bin/env typescript
// @file        apps/extensions/team-hub/src/context-switcher.ts
// @module      ui/status-bar
// @description Local/Remote context switcher - switch between execution environments
// @owner       ui
// @status      production-ready
//
// Status bar item for switching between local dev, remote replicas, CI/CD pipeline

import * as vscode from 'vscode';

export interface ExecutionContext {
  id: string;
  name: string;
  type: 'local' | 'remote' | 'ci';
  url?: string;
  host?: string;
  description: string;
  envYaml?: Record<string, any>;
}

export class ContextSwitcher {
  private statusBarItem: vscode.StatusBarItem;
  private currentContext: ExecutionContext;
  private contexts: ExecutionContext[] = [];
  private stateKey = 'elevatediq.currentContext';

  constructor(private readonly context: vscode.ExtensionContext) {
    this.currentContext = { id: 'local', name: 'Local', type: 'local', description: 'Local development' };

    // Create status bar item
    this.statusBarItem = vscode.window.createStatusBarItem(
      vscode.StatusBarAlignment.Right,
      100
    );

    this.statusBarItem.command = 'elevatediq.switchContext';
    this.statusBarItem.tooltip = 'Click to switch execution context';

    this.initializeContexts();
    this.updateStatusBar();
    this.registerCommands();
  }

  /**
   * Initialize available execution contexts from config
   */
  private async initializeContexts(): Promise<void> {
    this.contexts = [
      {
        id: 'local',
        name: 'Local',
        type: 'local',
        description: 'Local development environment'
      }
    ];

    // Load remote contexts from config
    const config = vscode.workspace.getConfiguration('elevatediq.contexts');

    // Add configured replicas
    const primaryHost = config.get('primaryHost') as string | undefined;
    const replicaHost = config.get('replicaHost') as string | undefined;

    if (primaryHost) {
      this.contexts.push({
        id: 'remote-primary',
        name: 'Remote',
        type: 'remote',
        host: primaryHost,
        url: `ssh://user@${primaryHost}`,
        description: `Remote: ${primaryHost} (primary)`
      });
    }

    if (replicaHost) {
      this.contexts.push({
        id: 'remote-replica',
        name: 'Remote Replica',
        type: 'remote',
        host: replicaHost,
        url: `ssh://user@${replicaHost}`,
        description: `Remote: ${replicaHost} (replica)`
      });
    }

    // Add CI context if configured
    const ciEnabled = config.get('ciEnabled') as boolean;
    if (ciEnabled) {
      this.contexts.push({
        id: 'ci',
        name: 'CI/CD',
        type: 'ci',
        description: 'CI/CD pipeline execution'
      });
    }

    // Restore previous context
    const savedContextId = this.context.workspaceState.get(this.stateKey) as string | undefined;
    if (savedContextId) {
      const savedContext = this.contexts.find(c => c.id === savedContextId);
      if (savedContext) {
        this.currentContext = savedContext;
      }
    }
  }

  /**
   * Update status bar display
   */
  private updateStatusBar(): void {
    const icon = this.getContextIcon(this.currentContext.type);
    this.statusBarItem.text = `${icon} [${this.currentContext.name}]`;
    this.statusBarItem.show();
  }

  /**
   * Show context selection menu
   */
  public async showContextMenu(): Promise<void> {
    const items = this.contexts.map(ctx => ({
      label: `$(${this.getContextIcon(ctx.type)}) ${ctx.name}`,
      description: ctx.description,
      context: ctx
    }));

    const selected = await vscode.window.showQuickPick(items, {
      placeHolder: 'Select execution context...',
      matchOnDescription: true
    });

    if (selected) {
      await this.switchContext(selected.context);
    }
  }

  /**
   * Switch to a different execution context
   */
  public async switchContext(newContext: ExecutionContext): Promise<void> {
    if (newContext.id === this.currentContext.id) {
      vscode.window.showInformationMessage(`Already on ${newContext.name}`);
      return;
    }

    try {
      vscode.window.showInformationMessage(
        `Switching to ${newContext.name}...`,
        { modal: false }
      );

      // Save current state
      await this.saveCurrentState();

      // Switch context
      this.currentContext = newContext;

      // Load new context state
      await this.loadContextState(newContext);

      // Update UI
      this.updateStatusBar();

      // Save preference
      await this.context.workspaceState.update(this.stateKey, newContext.id);

      vscode.window.showInformationMessage(
        `Switched to ${newContext.name} ✅`
      );

      // Fire context changed event
      this.notifyContextChanged();
    } catch (error) {
      vscode.window.showErrorMessage(`Failed to switch context: ${error}`);
    }
  }

  /**
   * Save current state (open files, etc.) before switching
   */
  private async saveCurrentState(): Promise<void> {
    // Phase 1: Save open files list
    // Phase 2: Push workspace state to server
    // Phase 3: Sync entire VS Code settings

    const openFiles = vscode.window.visibleTextEditors.map(editor => ({
      path: editor.document.uri.fsPath,
      selection: {
        line: editor.selection.start.line,
        character: editor.selection.start.character
      }
    }));

    await this.context.workspaceState.update(
      `elevatediq.savedState.${this.currentContext.id}`,
      { openFiles, timestamp: Date.now() }
    );
  }

  /**
   * Load state for new context
   */
  private async loadContextState(newContext: ExecutionContext): Promise<void> {
    // Phase 1: Load env.yaml for display
    if (newContext.type === 'remote' && newContext.host) {
      try {
        const envConfig = vscode.workspace.getConfiguration('elevatediq');
        const apiUrl = envConfig.get('apiUrl') as string;

        const response = await fetch(`${apiUrl}/api/contexts/${newContext.id}/env.yaml`);
        if (response.ok) {
          const envYaml = await response.json();
          newContext.envYaml = envYaml;

          // Show env details in output channel
          const outputChannel = vscode.window.createOutputChannel('KC IDE Context');
          outputChannel.appendLine(`Context: ${newContext.name}`);
          outputChannel.appendLine(`Host: ${newContext.host}`);
          outputChannel.appendLine(`Environment: ${JSON.stringify(envYaml, null, 2)}`);
          outputChannel.show();
        }
      } catch (error) {
        console.debug('Failed to load environment config:', error);
      }
    }

    // Restore open files from saved state (Phase 1 placeholder)
    const savedState = this.context.workspaceState.get(
      `elevatediq.savedState.${newContext.id}`
    ) as any;

    if (savedState?.openFiles) {
      // Reopen previously open files
      for (const file of savedState.openFiles) {
        try {
          const doc = await vscode.workspace.openTextDocument(file.path);
          const editor = await vscode.window.showTextDocument(doc);
          editor.selection = new vscode.Selection(
            file.selection.line,
            file.selection.character,
            file.selection.line,
            file.selection.character
          );
        } catch (error) {
          console.debug(`Failed to restore file ${file.path}:`, error);
        }
      }
    }
  }

  /**
   * Get icon for context type
   */
  private getContextIcon(type: string): string {
    const icons: Record<string, string> = {
      local: 'circle-large-filled',
      remote: 'remote',
      ci: 'gist-new'
    };
    return icons[type] || 'circle-outline';
  }

  /**
   * Broadcast context change to other extensions
   */
  private notifyContextChanged(): void {
    // Emit event that other extensions can listen to
    vscode.commands.executeCommand('elevatediq.onContextChanged', this.currentContext);
  }

  /**
   * Get current context
   */
  public getCurrentContext(): ExecutionContext {
    return this.currentContext;
  }

  /**
   * Get all available contexts
   */
  public getContexts(): ExecutionContext[] {
    return [...this.contexts];
  }

  /**
   * Register commands
   */
  private registerCommands(): void {
    // This would be called from the main extension
  }

  public dispose(): void {
    this.statusBarItem.dispose();
  }
}
