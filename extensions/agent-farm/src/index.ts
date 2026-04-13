/**
 * Agent Farm VS Code Extension
 * 
 * Multi-agent development system integrated into VS Code.
 * Provides intelligent code analysis and recommendations.
 */

import * as vscode from 'vscode';
import { AgentOrchestrator } from './orchestrator';
import { AgentFarmDashboard } from './dashboard';
import { TaskType } from './types';
import { CodeIndexer } from './code-indexer';

let orchestrator: AgentOrchestrator;
let dashboard: AgentFarmDashboard;
let statusBarItem: vscode.StatusBarItem;

/**
 * Extension activation
 */
export function activate(context: vscode.ExtensionContext) {
  console.log('Agent Farm extension activated');

  // Initialize components
  orchestrator = new AgentOrchestrator();
  dashboard = new AgentFarmDashboard(context.extensionUri);

  // Create status bar item
  statusBarItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 100);
  statusBarItem.command = 'agentFarm.showDashboard';
  statusBarItem.text = '🤖 Agent Farm';
  statusBarItem.show();
  context.subscriptions.push(statusBarItem);

  // Register commands
  registerCommands(context);

  // Register providers
  registerTreeDataProvider(context);

  console.log('Agent Farm initialized with ' + orchestrator.getAgents().length + ' agents');
}

/**
 * Register VS Code commands
 */
function registerCommands(context: vscode.ExtensionContext): void {
  // Analyze current file
  context.subscriptions.push(
    vscode.commands.registerCommand('agentFarm.analyzeFile', async () => {
      const editor = vscode.window.activeTextEditor;
      if (!editor) {
        vscode.window.showWarningMessage('No file open');
        return;
      }

      await analyzeFile(editor);
    })
  );

  // Analyze with specific task type
  context.subscriptions.push(
    vscode.commands.registerCommand('agentFarm.analyzeWithTask', async () => {
      const editor = vscode.window.activeTextEditor;
      if (!editor) {
        vscode.window.showWarningMessage('No file open');
        return;
      }

      const taskType = await vscode.window.showQuickPick(
        [
          { label: 'Code Review', taskType: TaskType.CODE_REVIEW },
          { label: 'Implementation Check', taskType: TaskType.CODE_IMPLEMENTATION },
          { label: 'Refactoring Opportunities', taskType: TaskType.REFACTORING },
          { label: 'Performance Analysis', taskType: TaskType.PERFORMANCE },
          { label: 'Security Audit', taskType: TaskType.SECURITY },
        ],
        { placeHolder: 'Select analysis type' }
      );

      if (taskType) {
        await analyzeFile(editor, taskType.taskType);
      }
    })
  );

  // Show dashboard
  context.subscriptions.push(
    vscode.commands.registerCommand('agentFarm.showDashboard', () => {
      dashboard.show();
    })
  );

  // Semantic search
  context.subscriptions.push(
    vscode.commands.registerCommand('agentFarm.semanticSearch', async () => {
      const query = await vscode.window.showInputBox({
        placeHolder: 'Search by meaning (e.g., "authentication logic")',
      });

      if (query) {
        await semanticSearch(query);
      }
    })
  );

  // Index current file
  context.subscriptions.push(
    vscode.commands.registerCommand('agentFarm.indexFile', async () => {
      const editor = vscode.window.activeTextEditor;
      if (!editor) {
        vscode.window.showWarningMessage('No file open');
        return;
      }

      const code = editor.document.getText();
      const fileName = editor.document.fileName;
      const index = CodeIndexer.index(code, fileName);

      vscode.window.showInformationMessage(
        `📊 Code Index: ${index.statistics.totalFunctions} functions, ` +
        `${index.statistics.totalClasses} classes, ` +
        `Avg complexity: ${index.statistics.averageComplexity}`
      );
    })
  );

  // Show audit trail
  context.subscriptions.push(
    vscode.commands.registerCommand('agentFarm.showAuditTrail', async () => {
      const auditTrail = orchestrator.getAuditTrail();
      
      if (auditTrail.length === 0) {
        vscode.window.showInformationMessage('No analysis history yet');
        return;
      }

      const items = auditTrail.map((result, idx) => ({
        label: `$(file-code) Analysis ${idx + 1}`,
        description: `${result.summary.totalRecommendations} recommendations • ${result.totalDuration}ms`,
        detail: result.documentUri,
      }));

      const selected = await vscode.window.showQuickPick(items, {
        placeHolder: 'Select analysis to view',
      });

      if (selected) {
        const index = auditTrail.findIndex(r => r.documentUri === selected.detail);
        if (index >= 0) {
          dashboard.updateAnalysis(auditTrail[index]);
          dashboard.show();
        }
      }
    })
  );

  // Clear audit trail
  context.subscriptions.push(
    vscode.commands.registerCommand('agentFarm.clearAuditTrail', async () => {
      const confirmed = await vscode.window.showWarningMessage(
        'Clear all analysis history?',
        { modal: true },
        'Clear'
      );

      if (confirmed === 'Clear') {
        orchestrator.clearAuditTrail();
        vscode.window.showInformationMessage('Audit trail cleared');
      }
    })
  );

  // Show agent list
  context.subscriptions.push(
    vscode.commands.registerCommand('agentFarm.listAgents', async () => {
      const agents = orchestrator.getAgents();
      const message = agents
        .map(agent => `📍 ${agent.name} (${agent.specialization})\n   Tasks: ${agent.taskTypes.join(', ')}`)
        .join('\n\n');

      vscode.window.showInformationMessage(message);
    })
  );
}

/**
 * Register tree data provider for sidebar
 */
function registerTreeDataProvider(context: vscode.ExtensionContext): void {
  const treeDataProvider = new AgentFarmTreeDataProvider();
  vscode.window.createTreeView('agentFarmView', {
    treeDataProvider,
  });

  context.subscriptions.push(
    vscode.workspace.onDidChangeTextDocument(() => {
      treeDataProvider.refresh();
    })
  );
}

/**
 * Analyze current file
 */
async function analyzeFile(editor: vscode.TextEditor, taskType?: TaskType): Promise<void> {
  const documentUri = editor.document.uri;
  const code = editor.document.getText();

  // Show progress
  vscode.window.withProgress(
    {
      location: vscode.ProgressLocation.Notification,
      title: 'Agent Farm analyzing...',
      cancellable: false,
    },
    async (progress) => {
      try {
        orchestrator.showOutput();
        const result = await orchestrator.execute(documentUri, code, taskType);

        // Show results in dashboard
        dashboard.updateAnalysis(result);
        dashboard.show();

        // Update status bar
        const { totalRecommendations, criticalCount } = result.summary;
        if (criticalCount > 0) {
          statusBarItem.text = `🤖 ${criticalCount} critical issues`;
          statusBarItem.color = new vscode.ThemeColor('statusBarItem.errorBackground');
        } else {
          statusBarItem.text = `🤖 ${totalRecommendations} findings`;
          statusBarItem.color = undefined;
        }

        // Show status message
        const message = `✓ Analysis complete: ${totalRecommendations} recommendations`;
        vscode.window.showInformationMessage(message);
      } catch (error) {
        orchestrator.showOutput();
        vscode.window.showErrorMessage(
          `Agent Farm analysis failed: ${error instanceof Error ? error.message : String(error)}`
        );
      }
    }
  );
}

/**
 * Semantic search across workspace
 */
async function semanticSearch(query: string): Promise<void> {
  vscode.window.showInformationMessage(`🔍 Searching for: "${query}" (Semantic search coming in Phase 2)`);
}

/**
 * Tree data provider for Agent Farm sidebar
 */
class AgentFarmTreeDataProvider implements vscode.TreeDataProvider<AgentFarmTreeItem> {
  private _onDidChangeTreeData = new vscode.EventEmitter<AgentFarmTreeItem | undefined | void>();
  readonly onDidChangeTreeData = this._onDidChangeTreeData.event;

  getTreeItem(element: AgentFarmTreeItem): vscode.TreeItem {
    return element;
  }

  getChildren(element?: AgentFarmTreeItem): Thenable<AgentFarmTreeItem[]> {
    if (!element) {
      // Root level
      return Promise.resolve([
        new AgentFarmTreeItem('🔍 Analyze File', vscode.TreeItemCollapsibleState.None, {
          command: 'agentFarm.analyzeFile',
          title: 'Analyze File',
        }),
        new AgentFarmTreeItem('⚡ Quick Analysis', vscode.TreeItemCollapsibleState.None, {
          command: 'agentFarm.analyzeWithTask',
          title: 'Quick Analysis',
        }),
        new AgentFarmTreeItem('📊 Dashboard', vscode.TreeItemCollapsibleState.None, {
          command: 'agentFarm.showDashboard',
          title: 'Dashboard',
        }),
        new AgentFarmTreeItem('🤖 Agents', vscode.TreeItemCollapsibleState.None, {
          command: 'agentFarm.listAgents',
          title: 'List Agents',
        }),
        new AgentFarmTreeItem('📈 Audit Trail', vscode.TreeItemCollapsibleState.None, {
          command: 'agentFarm.showAuditTrail',
          title: 'Show Audit Trail',
        }),
      ]);
    }

    return Promise.resolve([]);
  }

  refresh(): void {
    this._onDidChangeTreeData.fire();
  }
}

/**
 * Tree item for Agent Farm
 */
class AgentFarmTreeItem extends vscode.TreeItem {
  constructor(
    label: string,
    collapsibleState: vscode.TreeItemCollapsibleState,
    command?: vscode.Command
  ) {
    super(label, collapsibleState);
    this.command = command;
  }
}

/**
 * Extension deactivation
 */
export function deactivate() {
  if (orchestrator) {
    orchestrator.dispose();
  }
  if (dashboard) {
    dashboard.dispose();
  }
  if (statusBarItem) {
    statusBarItem.dispose();
  }
}
