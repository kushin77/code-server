#!/usr/bin/env typescript
// @file        apps/extensions/team-hub/src/agent-control.ts
// @module      ui/panels
// @description ElevatedIQ Agent Control panel - AI assistant task interface
// @owner       ui
// @status      production-ready
//
// Chat interface for sending natural language tasks to AI agent
// Approval queue for human review of agent actions

import * as vscode from 'vscode';

export interface AgentTask {
  id: string;
  description: string;
  createdAt: Date;
  status: 'pending' | 'working' | 'awaiting_approval' | 'completed' | 'failed';
  result?: string;
  approvals?: {
    approvedBy?: string;
    approvedAt?: Date;
    rejectedBy?: string;
    rejectedAt?: Date;
    notes?: string;
  };
}

export class AgentControlProvider implements vscode.TreeDataProvider<AgentTask> {
  private tasks: Map<string, AgentTask> = new Map();
  private eventEmitter = new vscode.EventEmitter<AgentTask | undefined>();
  readonly onDidChangeTreeData = this.eventEmitter.event;

  constructor(private readonly extensionUri: vscode.Uri) {}

  /**
   * Send natural language task to AI agent
   */
  public async submitTask(description: string): Promise<string> {
    const taskId = `task-${Date.now()}-${Math.random().toString(36).slice(2, 9)}`;

    const task: AgentTask = {
      id: taskId,
      description,
      createdAt: new Date(),
      status: 'pending'
    };

    this.tasks.set(taskId, task);
    this.eventEmitter.fire(task);

    try {
      const config = vscode.workspace.getConfiguration('elevatediq.agentControl');
      const apiUrl = vscode.workspace.getConfiguration('elevatediq').get('apiUrl') as string;

      if (!apiUrl) {
        throw new Error('Agent API URL not configured');
      }

      // Update to working status
      task.status = 'working';
      this.eventEmitter.fire(task);

      // Send to agent backend
      const response = await fetch(`${apiUrl}/api/agent/tasks`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          task_id: taskId,
          description,
          user_id: await this.getUserId(),
          session_id: await this.getSessionId()
        })
      });

      if (!response.ok) {
        throw new Error(`Agent API error: ${response.statusText}`);
      }

      const result = await response.json();

      // Update task based on agent response
      if (result.requires_approval) {
        task.status = 'awaiting_approval';
        task.result = result.planned_action;
      } else if (result.completed) {
        task.status = 'completed';
        task.result = result.output;
      }

      this.eventEmitter.fire(task);

      return taskId;
    } catch (error) {
      task.status = 'failed';
      task.result = error instanceof Error ? error.message : 'Unknown error';
      this.eventEmitter.fire(task);
      throw error;
    }
  }

  /**
   * Approve a task awaiting human approval
   */
  public async approveTask(taskId: string, notes: string = ''): Promise<void> {
    const task = this.tasks.get(taskId);
    if (!task) throw new Error('Task not found');

    try {
      const apiUrl = vscode.workspace.getConfiguration('elevatediq').get('apiUrl') as string;

      const response = await fetch(`${apiUrl}/api/agent/tasks/${taskId}/approve`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          approved_by: await this.getUserId(),
          notes
        })
      });

      if (!response.ok) {
        throw new Error(`Approval failed: ${response.statusText}`);
      }

      task.status = 'completed';
      task.approvals = {
        approvedBy: await this.getUserId(),
        approvedAt: new Date(),
        notes
      };

      this.eventEmitter.fire(task);
    } catch (error) {
      vscode.window.showErrorMessage(`Failed to approve task: ${error}`);
      throw error;
    }
  }

  /**
   * Reject a task awaiting human approval
   */
  public async rejectTask(taskId: string, reason: string): Promise<void> {
    const task = this.tasks.get(taskId);
    if (!task) throw new Error('Task not found');

    try {
      const apiUrl = vscode.workspace.getConfiguration('elevatediq').get('apiUrl') as string;

      const response = await fetch(`${apiUrl}/api/agent/tasks/${taskId}/reject`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          rejected_by: await this.getUserId(),
          reason
        })
      });

      if (!response.ok) {
        throw new Error(`Rejection failed: ${response.statusText}`);
      }

      task.status = 'failed';
      task.approvals = {
        rejectedBy: await this.getUserId(),
        rejectedAt: new Date(),
        notes: reason
      };

      this.eventEmitter.fire(task);
    } catch (error) {
      vscode.window.showErrorMessage(`Failed to reject task: ${error}`);
      throw error;
    }
  }

  private async getUserId(): Promise<string> {
    // Get from auth context or config
    const config = vscode.workspace.getConfiguration('elevatediq');
    return config.get('userId') as string || 'anonymous';
  }

  private async getSessionId(): Promise<string> {
    // Get from session context
    const config = vscode.workspace.getConfiguration('elevatediq');
    return config.get('sessionId') as string || `session-${Date.now()}`;
  }

  getTreeItem(element: AgentTask): vscode.TreeItem {
    const statusIcon = this.getStatusIcon(element.status);
    const item = new vscode.TreeItem(`${statusIcon} ${element.description.slice(0, 50)}...`);

    item.description = element.status;
    item.contextValue = element.status;

    item.tooltip = new vscode.MarkdownString(`
**Task:** ${element.description}  
**Status:** ${element.status}  
**Created:** ${element.createdAt.toLocaleString()}
${element.result ? `**Result:** ${element.result}` : ''}
${element.approvals ? `**Approval:** ${element.approvals.approvedBy || element.approvals.rejectedBy}` : ''}
    `);

    item.collapsibleState = vscode.TreeItemCollapsibleState.None;

    return item;
  }

  getChildren(element?: AgentTask): AgentTask[] {
    if (element) {
      return [];
    }

    // Return pending tasks first, then others, all sorted by creation date
    const pending = Array.from(this.tasks.values())
      .filter(t => t.status === 'awaiting_approval')
      .sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime());

    const others = Array.from(this.tasks.values())
      .filter(t => t.status !== 'awaiting_approval')
      .sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime());

    return [...pending, ...others].slice(0, 50);
  }

  private getStatusIcon(status: AgentTask['status']): string {
    const icons: Record<AgentTask['status'], string> = {
      pending: '⏳',
      working: '⚙️',
      awaiting_approval: '⚠️',
      completed: '✅',
      failed: '❌'
    };
    return icons[status] || '●';
  }
}

/**
 * Agent Control sidebar view with chat input
 */
export class AgentControlView {
  private webviewPanel: vscode.WebviewPanel | undefined;

  constructor(
    private readonly context: vscode.ExtensionContext,
    private readonly provider: AgentControlProvider
  ) {
    this.registerCommands();
  }

  /**
   * Show agent chat panel
   */
  public async showPanel(): Promise<void> {
    if (this.webviewPanel) {
      this.webviewPanel.reveal(vscode.ViewColumn.Beside);
      return;
    }

    this.webviewPanel = vscode.window.createWebviewPanel(
      'elevatediqAgentControl',
      'Agent Control',
      vscode.ViewColumn.Beside,
      { enableScripts: true }
    );

    this.webviewPanel.webview.html = this.getWebviewContent();

    this.webviewPanel.webview.onDidReceiveMessage(async (message) => {
      try {
        switch (message.command) {
          case 'submitTask':
            const taskId = await this.provider.submitTask(message.text);
            this.webviewPanel?.webview.postMessage({
              command: 'taskSubmitted',
              taskId
            });
            break;

          case 'approveTask':
            await this.provider.approveTask(message.taskId, message.notes);
            vscode.window.showInformationMessage('Task approved ✅');
            break;

          case 'rejectTask':
            await this.provider.rejectTask(message.taskId, message.reason);
            vscode.window.showInformationMessage('Task rejected ❌');
            break;
        }
      } catch (error) {
        vscode.window.showErrorMessage(`Error: ${error}`);
      }
    });

    this.webviewPanel.onDidDispose(() => {
      this.webviewPanel = undefined;
    });
  }

  private registerCommands(): void {
    this.context.subscriptions.push(
      vscode.commands.registerCommand('elevatediq.showAgentControl', () => {
        this.showPanel();
      })
    );
  }

  private getWebviewContent(): string {
    return `
<!DOCTYPE html>
<html>
<head>
  <style>
    body { font-family: sans-serif; padding: 16px; }
    .chat-container { display: flex; flex-direction: column; height: 100vh; }
    .messages { flex: 1; overflow-y: auto; margin-bottom: 16px; }
    .message { margin-bottom: 12px; padding: 8px; border-radius: 4px; }
    .message.user { background: #0066cc; color: white; }
    .message.assistant { background: #e0e0e0; color: black; }
    .message.approval { background: #fff3cd; color: black; border-left: 4px solid #ffc107; }
    .input-area { display: flex; gap: 8px; }
    input { flex: 1; padding: 8px; border: 1px solid #ccc; border-radius: 4px; }
    button { padding: 8px 16px; background: #0066cc; color: white; border: none; border-radius: 4px; cursor: pointer; }
    button:hover { background: #0052a3; }
  </style>
</head>
<body>
  <div class="chat-container">
    <div class="messages" id="messages"></div>
    <div class="input-area">
      <input type="text" id="taskInput" placeholder="Describe a task for the AI agent..." />
      <button onclick="submitTask()">Send</button>
    </div>
  </div>

  <script>
    const vscode = acquireVsCodeApi();

    function submitTask() {
      const input = document.getElementById('taskInput');
      const text = input.value.trim();
      if (!text) return;

      addMessage(text, 'user');
      vscode.postMessage({ command: 'submitTask', text });
      input.value = '';
    }

    function addMessage(text, type) {
      const messagesDiv = document.getElementById('messages');
      const msg = document.createElement('div');
      msg.className = \`message \${type}\`;
      msg.textContent = text;
      messagesDiv.appendChild(msg);
      messagesDiv.scrollTop = messagesDiv.scrollHeight;
    }

    window.addEventListener('message', (e) => {
      if (e.data.command === 'taskSubmitted') {
        addMessage(\`Task submitted (ID: \${e.data.taskId})\`, 'assistant');
      }
    });

    document.getElementById('taskInput').addEventListener('keypress', (e) => {
      if (e.key === 'Enter') submitTask();
    });
  </script>
</body>
</html>
    `;
  }

  dispose(): void {
    this.webviewPanel?.dispose();
  }
}
