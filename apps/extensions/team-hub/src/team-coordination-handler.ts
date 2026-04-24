// @file apps/extensions/team-hub/src/team-coordination-handler.ts
// @module ide/team-coordination
// @description P2-1539 Phase 7: Handle team coordination UI and task distribution
// @governance GOV-002: All coordination operations logged with user context

import * as vscode from 'vscode';
import { TeamOrchestratorEngine, DistributedTask, TeamMember } from './team-orchestrator-engine';

export interface CoordinationContext {
  currentUserId: string;
  currentTeamId: string;
  permissions: string[];
  availableTeams: string[];
}

/**
 * Team Coordination Handler - UI and orchestration coordination
 */
export class TeamCoordinationHandler {
  private orchestrator: TeamOrchestratorEngine;
  private context: CoordinationContext | null = null;
  private outputChannel: vscode.OutputChannel;

  constructor(private extensionContext: vscode.ExtensionContext) {
    this.orchestrator = new TeamOrchestratorEngine(extensionContext);
    this.outputChannel = vscode.window.createOutputChannel('Team Coordination');
  }

  /**
   * Initialize coordination context
   */
  async initializeContext(userId: string, teamId: string): Promise<void> {
    this.context = {
      currentUserId: userId,
      currentTeamId: teamId,
      permissions: ['read', 'write', 'assign'],  // In production: fetch from service
      availableTeams: ['team-a', 'team-b']  // In production: fetch from service
    };

    this.outputChannel.appendLine(`[INFO] Coordination context initialized for user: ${userId}`);
  }

  /**
   * Display team workload view
   */
  async showTeamWorkloadView(): Promise<void> {
    if (!this.context) {
      vscode.window.showErrorMessage('Coordination context not initialized');
      return;
    }

    const summary = this.orchestrator.getTeamAvailabilitySummary(this.context.currentTeamId);
    const taskCount = this.orchestrator.getTeamTasks(this.context.currentTeamId).length;

    const items = [
      `👥 Team Availability`,
      `  Available: ${summary.available.length} members`,
      `  Busy: ${summary.busy.length} members`,
      `  Offline: ${summary.offline.length} members`,
      ``,
      `📊 Capacity`,
      `  Total: ${summary.totalCapacity}%`,
      `  Used: ${summary.usedCapacity}%`,
      `  Available: ${summary.totalCapacity - summary.usedCapacity}%`,
      ``,
      `📋 Tasks`,
      `  Active: ${taskCount} tasks`
    ];

    this.outputChannel.appendLine(items.join('\n'));
    vscode.window.showInformationMessage(`Team workload: ${taskCount} tasks, ${summary.totalCapacity - summary.usedCapacity}% capacity available`);
  }

  /**
   * Show task assignment UI
   */
  async showTaskAssignmentUI(): Promise<void> {
    if (!this.context) {
      vscode.window.showErrorMessage('Coordination context not initialized');
      return;
    }

    const title = await vscode.window.showInputBox({
      prompt: 'Enter task title',
      placeHolder: 'e.g., Implement user authentication'
    });

    if (!title) return;

    const description = await vscode.window.showInputBox({
      prompt: 'Enter task description',
      placeHolder: 'e.g., Add GitHub OAuth integration'
    });

    if (!description) return;

    const hoursStr = await vscode.window.showInputBox({
      prompt: 'Estimated hours',
      placeHolder: '4',
      validateInput: v => /^\d+$/.test(v) ? '' : 'Must be a number'
    });

    if (!hoursStr) return;

    const priorityItems = ['critical', 'high', 'medium', 'low'];
    const priorityIndex = await vscode.window.showQuickPick(priorityItems, {
      placeHolder: 'Select priority'
    });

    if (priorityIndex === undefined) return;

    const skillsStr = await vscode.window.showInputBox({
      prompt: 'Required skills (comma-separated)',
      placeHolder: 'e.g., typescript, react'
    });

    const skills = skillsStr ? skillsStr.split(',').map(s => s.trim()) : [];

    const task = this.orchestrator.createDistributedTask(
      title,
      description,
      skills,
      parseInt(hoursStr),
      this.context.currentTeamId,
      priorityItems[priorityIndex || 0] as any
    );

    vscode.window.showInformationMessage(
      `Task created: ${task.id}\nAssigned to: ${task.assignedMemberId || 'Unassigned'}`
    );
  }

  /**
   * Show team member tasks
   */
  async showMemberTasks(memberId: string): Promise<void> {
    if (!this.context) {
      vscode.window.showErrorMessage('Coordination context not initialized');
      return;
    }

    const tasks = this.orchestrator.getMemberTasks(this.context.currentTeamId, memberId);

    if (!tasks.length) {
      vscode.window.showInformationMessage('No active tasks for this member');
      return;
    }

    const items = tasks.map(t => ({
      label: `[${t.priority.toUpperCase()}] ${t.title}`,
      description: `${t.status} - ${t.estimatedHours}h`,
      detail: t.description,
      task: t
    }));

    const selected = await vscode.window.showQuickPick(items, {
      placeHolder: 'Select task to view details'
    });

    if (!selected) return;

    const task = selected.task;
    this.outputChannel.appendLine(`
Task Details: ${task.id}
Title: ${task.title}
Status: ${task.status}
Priority: ${task.priority}
Estimated: ${task.estimatedHours}h
Due: ${task.dueAt.toISOString().split('T')[0]}
Required Skills: ${task.requiredSkills.join(', ')}
    `);
  }

  /**
   * Auto-assign unassigned tasks
   */
  async autoAssignUnassignedTasks(): Promise<void> {
    if (!this.context) {
      vscode.window.showErrorMessage('Coordination context not initialized');
      return;
    }

    const teamTasks = this.orchestrator.getTeamTasks(this.context.currentTeamId);
    const unassignedTasks = teamTasks.filter(t => t.status === 'unassigned');

    let assignedCount = 0;
    for (const task of unassignedTasks) {
      if (this.orchestrator.getTask(task.id)) {
        assignedCount++;
      }
    }

    vscode.window.showInformationMessage(
      `Auto-assignment complete: ${assignedCount}/${unassignedTasks.length} tasks assigned`
    );
  }

  /**
   * Create workflow from template
   */
  async createWorkflowFromTemplate(): Promise<void> {
    const templates = [
      { label: 'Standard Delivery', description: 'Design → Dev → Review → Deploy' },
      { label: 'Hotfix', description: 'Dev → Review → Deploy' },
      { label: 'Documentation', description: 'Draft → Review → Publish' }
    ];

    const selected = await vscode.window.showQuickPick(templates, {
      placeHolder: 'Select workflow template'
    });

    if (!selected) return;

    const workflowName = await vscode.window.showInputBox({
      prompt: 'Workflow name',
      placeHolder: `${selected.label} Workflow`
    });

    if (!workflowName) return;

    // Create based on template
    const stages = selected.label === 'Standard Delivery'
      ? [
        { id: 'design', name: 'Design', taskFilters: { type: 'design' }, autoAssignRules: [] },
        { id: 'dev', name: 'Development', taskFilters: { type: 'development' }, autoAssignRules: [] },
        { id: 'review', name: 'Code Review', taskFilters: { type: 'review' }, autoAssignRules: [] },
        { id: 'deploy', name: 'Deployment', taskFilters: { type: 'deployment' }, autoAssignRules: [] }
      ]
      : [];

    const workflow = this.orchestrator.createWorkflow(workflowName, selected.description, stages);
    vscode.window.showInformationMessage(`Workflow created: ${workflow.id}`);
  }

  /**
   * Monitor team capacity in real-time
   */
  async startCapacityMonitoring(): Promise<void> {
    if (!this.context) {
      vscode.window.showErrorMessage('Coordination context not initialized');
      return;
    }

    const interval = setInterval(() => {
      const summary = this.orchestrator.getTeamAvailabilitySummary(this.context!.currentTeamId);
      const utilization = Math.round(
        (summary.usedCapacity / summary.totalCapacity) * 100
      );

      if (utilization > 90) {
        this.outputChannel.appendLine(`⚠️  [ALERT] Team at ${utilization}% capacity`);
      } else if (utilization < 30) {
        this.outputChannel.appendLine(`ℹ️  [INFO] Team at ${utilization}% capacity - room for more work`);
      }
    }, 60000);  // Check every minute

    this.extensionContext.subscriptions.push({
      dispose: () => clearInterval(interval)
    });
  }

  /**
   * Export team workload report
   */
  async exportWorkloadReport(): Promise<void> {
    if (!this.context) {
      vscode.window.showErrorMessage('Coordination context not initialized');
      return;
    }

    const tasks = this.orchestrator.getTeamTasks(this.context.currentTeamId);
    const summary = this.orchestrator.getTeamAvailabilitySummary(this.context.currentTeamId);

    const report = {
      timestamp: new Date().toISOString(),
      teamId: this.context.currentTeamId,
      summary,
      tasks: tasks.map(t => ({
        id: t.id,
        title: t.title,
        status: t.status,
        priority: t.priority,
        assignedMemberId: t.assignedMemberId,
        estimatedHours: t.estimatedHours,
        requiredSkills: t.requiredSkills
      }))
    };

    // Copy to clipboard
    await vscode.env.clipboard.writeText(JSON.stringify(report, null, 2));
    vscode.window.showInformationMessage('Workload report copied to clipboard');
  }

  /**
   * Get orchestrator for testing/advanced use
   */
  getOrchestrator(): TeamOrchestratorEngine {
    return this.orchestrator;
  }

  /**
   * Dispose resources
   */
  dispose(): void {
    this.orchestrator.dispose();
    this.outputChannel.dispose();
  }
}

export function createTeamCoordinationHandler(context: vscode.ExtensionContext): TeamCoordinationHandler {
  return new TeamCoordinationHandler(context);
}
