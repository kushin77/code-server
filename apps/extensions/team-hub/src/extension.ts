import * as vscode from 'vscode';
import { readTeamHubConfig } from './config';
import { PresenceService } from './presence';
import { TeamHubActions } from './actions';
import { TeamHubSidebarProvider } from './sidebar';
import { TerminalDLPScanner } from './terminal-dlp';
import { GitHubTaskPanelProvider } from './github-task-panel';
import { TeamHubWelcomePage } from './welcome-page';

export async function activate(context: vscode.ExtensionContext): Promise<void> {
  const getConfig = readTeamHubConfig;
  const presenceService = new PresenceService(getConfig);
  const actions = new TeamHubActions(presenceService);
  const sidebarProvider = new TeamHubSidebarProvider(context.extensionUri, presenceService, actions, getConfig, context.workspaceState);
  const welcomePage = new TeamHubWelcomePage(context.extensionUri, context.workspaceState, actions);

  // Initialize Terminal DLP Scanner
  const dlpScanner = new TerminalDLPScanner();
  const terminalMonitor = new TerminalDLPMonitor(dlpScanner);

  // Initialize GitHub Task Sync (optional, if enabled)
  const config = getConfig();
  let gitHubTaskPanel: GitHubTaskPanelProvider | undefined;

  if (config.enableGitHubTaskSync && config.githubToken && config.githubOwner && config.githubRepo) {
    try {
      gitHubTaskPanel = new GitHubTaskPanelProvider({
        apiBaseUrl: 'http://localhost:3100',
        pollingIntervalMs: config.gitHubTaskSyncInterval,
      });

      context.subscriptions.push(
        vscode.window.registerTreeDataProvider('gitHubTasks', gitHubTaskPanel)
      );
    } catch (error) {
      vscode.window.showErrorMessage(`Failed to initialize GitHub Task Sync: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  context.subscriptions.push(
    vscode.commands.registerCommand('teamHub.openActivityFeed', () => {
      void vscode.commands.executeCommand('workbench.view.extension.teamHub-container');
    }),
    vscode.commands.registerCommand('teamHub.openWelcome', () => welcomePage.open()),
    vscode.window.registerWebviewViewProvider('teamHub.sidebar', sidebarProvider),
    vscode.commands.registerCommand('teamHub.mentionUser', (userId: string) => actions.mentionUser(userId)),
    vscode.commands.registerCommand('teamHub.startMeet', (userIds: string[] | undefined) => actions.startMeet(userIds ?? [])),
    vscode.commands.registerCommand('teamHub.goToUserFile', (userId: string) => actions.goToUserFile(userId)),
    vscode.commands.registerCommand('teamHub.refreshPresence', () => actions.refreshPresence()),
    vscode.commands.registerCommand('teamHub.settings', () => actions.openSettings()),
    vscode.commands.registerCommand('teamHub.shareWorkspace', () => actions.shareWorkspace()),
    vscode.commands.registerCommand('teamHub.toggleDLP', () => terminalMonitor.toggleDLP()),
    vscode.commands.registerCommand('gitHubTasks.refresh', () => gitHubTaskPanel?.refresh()),
    vscode.commands.registerCommand('gitHubTasks.openIssue', (task: any) => {
      if (task?.gitHubUrl) {
        vscode.env.openExternal(vscode.Uri.parse(task.gitHubUrl));
      }
    }),
    new vscode.Disposable(() => presenceService.dispose()),
    new vscode.Disposable(() => terminalMonitor.dispose()),
    new vscode.Disposable(() => welcomePage.dispose())
  );

  await welcomePage.openIfNeeded();

  const enableAutoPresence = config.enableAutoPresence;
  if (enableAutoPresence) {
    context.subscriptions.push(
      vscode.window.onDidChangeActiveTextEditor((editor) => {
        presenceService.updateActiveEditor(editor);
      })
    );
  }

  // Enable DLP monitoring if configured
  const enableDLP = config.enableTerminalDLP ?? true;
  if (enableDLP) {
    terminalMonitor.startMonitoring();
  }

  await presenceService.connect();
  presenceService.updateActiveEditor(vscode.window.activeTextEditor);
}

class TerminalDLPMonitor {
  private dlpScanner: TerminalDLPScanner;
  private terminals: Map<vscode.Terminal, vscode.TerminalWriteEvent[]> = new Map();
  private dlpEnabled: boolean = true;
  private outputChannel: vscode.OutputChannel;

  constructor(scanner: TerminalDLPScanner) {
    this.dlpScanner = scanner;
    this.outputChannel = vscode.window.createOutputChannel('Terminal DLP');
  }

  startMonitoring(): void {
    // Monitor new terminals
    vscode.window.onDidOpenTerminal((terminal) => {
      this.terminals.set(terminal, []);
    });

    // Clean up closed terminals
    vscode.window.onDidCloseTerminal((terminal) => {
      this.terminals.delete(terminal);
    });

    // Monitor terminal data
    vscode.window.onDidWriteTerminalData?.((event) => {
      if (!this.dlpEnabled) return;
      
      const terminal = event.terminal;
      const data = event.data;
      
      const result = this.dlpScanner.scan(data);
      if (result.matches.length > 0) {
        this.logDLPEvent(terminal, result);
      }
    });
  }

  private logDLPEvent(terminal: vscode.Terminal, result: any): void {
    const timestamp = new Date().toISOString();
    const message = `[${timestamp}] DLP Event in ${terminal.name}: ${result.severity} - ${result.matches.length} matches detected`;
    this.outputChannel.appendLine(message);

    // Show notification for critical matches
    if (result.severity === 'critical') {
      vscode.window.showWarningMessage(
        `Terminal DLP: Critical sensitive data detected in ${terminal.name}`,
        'View Details'
      ).then((selection) => {
        if (selection === 'View Details') {
          this.outputChannel.show();
        }
      });
    }
  }

  toggleDLP(): void {
    this.dlpEnabled = !this.dlpEnabled;
    const status = this.dlpEnabled ? 'enabled' : 'disabled';
    vscode.window.showInformationMessage(`Terminal DLP ${status}`);
  }

  dispose(): void {
    this.outputChannel.dispose();
    this.terminals.clear();
  }
}

export function deactivate(): void {
  // VS Code disposes subscriptions on shutdown.
}
