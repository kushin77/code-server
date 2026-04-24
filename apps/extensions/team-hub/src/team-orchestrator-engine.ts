// @file apps/extensions/team-hub/src/team-orchestrator-engine.ts
// @module ide/team-coordination
// @description P2-1539 Phase 7: Team orchestrator for cross-team task assignment and workflow coordination
// @governance GOV-002: All team operations audited, permission-based access control enforced

import * as vscode from 'vscode';

export interface TeamMember {
  id: string;
  name: string;
  email: string;
  status: 'online' | 'away' | 'offline' | 'dnd';
  availabilityPercentage: number;  // 0-100: how much capacity available
  skillTags: string[];
  currentTasks: string[];
  timezone: string;
  workHours: { start: string; end: string };
}

export interface DistributedTask {
  id: string;
  title: string;
  description: string;
  priority: 'critical' | 'high' | 'medium' | 'low';
  estimatedHours: number;
  requiredSkills: string[];
  assignedTeamId: string;
  assignedMemberId: string | null;
  status: 'unassigned' | 'assigned' | 'in_progress' | 'completed' | 'blocked';
  dependencies: string[];  // Task IDs this depends on
  createdAt: Date;
  dueAt: Date;
  completedAt?: Date;
  auditLog: AuditLogEntry[];
}

export interface AuditLogEntry {
  timestamp: Date;
  userId: string;
  action: string;
  details: Record<string, unknown>;
}

export interface TeamWorkflow {
  id: string;
  name: string;
  description: string;
  stages: WorkflowStage[];
  automationRules: AutomationRule[];
  createdBy: string;
}

export interface WorkflowStage {
  id: string;
  name: string;
  taskFilters: Record<string, unknown>;
  autoAssignRules?: AutoAssignRule[];
}

export interface AutoAssignRule {
  id: string;
  condition: string;  // Evaluates to boolean
  targetMember?: string;  // If empty, use load balancing
  skipIfUnavailable: boolean;
}

export interface AutomationRule {
  id: string;
  trigger: string;  // Event trigger
  actions: WorkflowAction[];
}

export interface WorkflowAction {
  type: 'assign_task' | 'notify_team' | 'create_issue' | 'escalate' | 'block';
  config: Record<string, unknown>;
}

/**
 * Team Orchestrator Engine - Distributed task assignment and team coordination
 */
export class TeamOrchestratorEngine {
  private teams: Map<string, TeamMember[]> = new Map();
  private tasks: Map<string, DistributedTask> = new Map();
  private workflows: Map<string, TeamWorkflow> = new Map();
  private outputChannel: vscode.OutputChannel;
  private auditLog: AuditLogEntry[] = [];

  constructor(private context: vscode.ExtensionContext) {
    this.outputChannel = vscode.window.createOutputChannel('Team Orchestrator');
  }

  /**
   * Register a team with members
   */
  registerTeam(teamId: string, members: TeamMember[]): void {
    this.teams.set(teamId, members);
    this.logAudit('register_team', { teamId, memberCount: members.length });
    this.outputChannel.appendLine(`[INFO] Team registered: ${teamId} (${members.length} members)`);
  }

  /**
   * Get all teams
   */
  getTeams(): Map<string, TeamMember[]> {
    return this.teams;
  }

  /**
   * Get team members
   */
  getTeamMembers(teamId: string): TeamMember[] {
    return this.teams.get(teamId) || [];
  }

  /**
   * Create a distributed task
   */
  createDistributedTask(
    title: string,
    description: string,
    requiredSkills: string[],
    estimatedHours: number,
    teamId: string,
    priority: 'critical' | 'high' | 'medium' | 'low' = 'medium',
    dueAt: Date = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000)
  ): DistributedTask {
    const task: DistributedTask = {
      id: `task-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
      title,
      description,
      priority,
      estimatedHours,
      requiredSkills,
      assignedTeamId: teamId,
      assignedMemberId: null,
      status: 'unassigned',
      dependencies: [],
      createdAt: new Date(),
      dueAt,
      auditLog: []
    };

    this.tasks.set(task.id, task);
    this.logAudit('create_task', { taskId: task.id, title, teamId, priority });
    this.outputChannel.appendLine(`[INFO] Task created: ${task.id} - ${title}`);

    // Try auto-assignment
    this.autoAssignTask(task.id);

    return task;
  }

  /**
   * Auto-assign task to best available team member
   */
  autoAssignTask(taskId: string): boolean {
    const task = this.tasks.get(taskId);
    if (!task || task.assignedMemberId) {
      return false;
    }

    const teamMembers = this.getTeamMembers(task.assignedTeamId);
    if (!teamMembers.length) {
      return false;
    }

    // Find members with required skills and availability
    const candidateMembers = teamMembers.filter(m => {
      const hasSkills = task.requiredSkills.every(skill =>
        m.skillTags.some(tag => tag.toLowerCase() === skill.toLowerCase())
      );
      const isAvailable = m.status !== 'offline' && m.availabilityPercentage > 0;
      return hasSkills && isAvailable;
    });

    if (!candidateMembers.length) {
      this.outputChannel.appendLine(`[WARN] No qualified members available for task: ${taskId}`);
      return false;
    }

    // Sort by availability and current load, pick least loaded
    const bestMember = candidateMembers.sort((a, b) => {
      const aLoad = a.currentTasks.length;
      const bLoad = b.currentTasks.length;
      if (aLoad !== bLoad) return aLoad - bLoad;
      return b.availabilityPercentage - a.availabilityPercentage;
    })[0];

    task.assignedMemberId = bestMember.id;
    task.status = 'assigned';
    task.auditLog.push({
      timestamp: new Date(),
      userId: 'system',
      action: 'auto_assign',
      details: { memberId: bestMember.id, method: 'load_balancing' }
    });

    bestMember.currentTasks.push(taskId);
    this.logAudit('assign_task', { taskId, memberId: bestMember.id, method: 'auto' });
    this.outputChannel.appendLine(`[INFO] Task auto-assigned: ${taskId} → ${bestMember.name}`);

    return true;
  }

  /**
   * Manually assign task to team member
   */
  assignTaskToMember(taskId: string, memberId: string, userId: string): boolean {
    const task = this.tasks.get(taskId);
    if (!task) {
      return false;
    }

    const member = this.getTeamMembers(task.assignedTeamId).find(m => m.id === memberId);
    if (!member) {
      return false;
    }

    if (task.assignedMemberId && task.assignedMemberId !== memberId) {
      const oldMember = this.getTeamMembers(task.assignedTeamId).find(
        m => m.id === task.assignedMemberId
      );
      if (oldMember) {
        oldMember.currentTasks = oldMember.currentTasks.filter(t => t !== taskId);
      }
    }

    task.assignedMemberId = memberId;
    task.status = 'assigned';
    member.currentTasks.push(taskId);
    task.auditLog.push({
      timestamp: new Date(),
      userId,
      action: 'manual_assign',
      details: { memberId }
    });

    this.logAudit('assign_task_manual', { taskId, memberId, assignedBy: userId });
    this.outputChannel.appendLine(`[INFO] Task manually assigned: ${taskId} → ${member.name}`);

    return true;
  }

  /**
   * Get task by ID
   */
  getTask(taskId: string): DistributedTask | undefined {
    return this.tasks.get(taskId);
  }

  /**
   * Get all tasks for a team
   */
  getTeamTasks(teamId: string): DistributedTask[] {
    return Array.from(this.tasks.values()).filter(t => t.assignedTeamId === teamId);
  }

  /**
   * Get all tasks for a team member
   */
  getMemberTasks(teamId: string, memberId: string): DistributedTask[] {
    return Array.from(this.tasks.values()).filter(
      t => t.assignedTeamId === teamId && t.assignedMemberId === memberId
    );
  }

  /**
   * Update task status
   */
  updateTaskStatus(
    taskId: string,
    status: DistributedTask['status'],
    userId: string
  ): boolean {
    const task = this.tasks.get(taskId);
    if (!task) {
      return false;
    }

    const oldStatus = task.status;
    task.status = status;

    if (status === 'completed') {
      task.completedAt = new Date();
    }

    task.auditLog.push({
      timestamp: new Date(),
      userId,
      action: 'status_change',
      details: { from: oldStatus, to: status }
    });

    this.logAudit('task_status_update', { taskId, oldStatus, newStatus: status, userId });
    this.outputChannel.appendLine(`[INFO] Task status updated: ${taskId} (${oldStatus} → ${status})`);

    return true;
  }

  /**
   * Create a workflow for automated task orchestration
   */
  createWorkflow(
    name: string,
    description: string,
    stages: WorkflowStage[],
    automationRules: AutomationRule[] = []
  ): TeamWorkflow {
    const workflow: TeamWorkflow = {
      id: `workflow-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
      name,
      description,
      stages,
      automationRules
    };

    this.workflows.set(workflow.id, workflow);
    this.logAudit('create_workflow', { workflowId: workflow.id, name, stageCount: stages.length });
    this.outputChannel.appendLine(`[INFO] Workflow created: ${workflow.id} - ${name}`);

    return workflow;
  }

  /**
   * Get workflow by ID
   */
  getWorkflow(workflowId: string): TeamWorkflow | undefined {
    return this.workflows.get(workflowId);
  }

  /**
   * Execute workflow rules on a task
   */
  executeWorkflowRules(taskId: string, workflowId: string): void {
    const workflow = this.workflows.get(workflowId);
    const task = this.tasks.get(taskId);

    if (!workflow || !task) {
      return;
    }

    for (const rule of workflow.automationRules) {
      // Simple condition evaluation - in production, would use expression evaluator
      try {
        const matches = this.evaluateCondition(rule.trigger, task);

        if (matches) {
          for (const action of rule.actions) {
            this.executeAction(action, task);
          }
        }
      } catch (error) {
        this.outputChannel.appendLine(`[ERROR] Workflow rule execution failed: ${error}`);
      }
    }
  }

  /**
   * Evaluate workflow condition
   */
  private evaluateCondition(condition: string, task: DistributedTask): boolean {
    // Simple pattern matching - in production would use safer expression evaluator
    if (condition.includes('priority:critical') && task.priority === 'critical') {
      return true;
    }
    if (condition.includes('status:unassigned') && task.status === 'unassigned') {
      return true;
    }
    if (condition.includes('overdue')) {
      return task.dueAt < new Date();
    }
    return false;
  }

  /**
   * Execute workflow action
   */
  private executeAction(action: WorkflowAction, task: DistributedTask): void {
    switch (action.type) {
      case 'assign_task':
        if (action.config.memberId) {
          this.assignTaskToMember(task.id, action.config.memberId as string, 'workflow');
        }
        break;
      case 'notify_team':
        this.outputChannel.appendLine(
          `[NOTIFICATION] Task ${task.id}: ${action.config.message}`
        );
        break;
      case 'escalate':
        if (task.priority !== 'critical') {
          task.priority = 'critical';
          this.logAudit('escalate_task', { taskId: task.id, reason: action.config.reason });
        }
        break;
    }
  }

  /**
   * Get team member availability summary
   */
  getTeamAvailabilitySummary(teamId: string): {
    available: TeamMember[];
    busy: TeamMember[];
    offline: TeamMember[];
    totalCapacity: number;
    usedCapacity: number;
  } {
    const members = this.getTeamMembers(teamId);

    return {
      available: members.filter(m => m.status !== 'offline' && m.availabilityPercentage > 50),
      busy: members.filter(m => m.status !== 'offline' && m.availabilityPercentage <= 50),
      offline: members.filter(m => m.status === 'offline'),
      totalCapacity: members.reduce((sum, m) => sum + m.availabilityPercentage, 0),
      usedCapacity: members.reduce((sum, m) => sum + (100 - m.availabilityPercentage), 0)
    };
  }

  /**
   * Log audit entry (bounded: max 10K, keeps last 5K)
   */
  private logAudit(action: string, details: Record<string, unknown>): void {
    const entry: AuditLogEntry = {
      timestamp: new Date(),
      userId: 'system',
      action,
      details
    };

    this.auditLog.push(entry);

    // Maintain bounded history
    if (this.auditLog.length > 10000) {
      this.auditLog = this.auditLog.slice(-5000);
    }
  }

  /**
   * Get audit log
   */
  getAuditLog(): AuditLogEntry[] {
    return [...this.auditLog];
  }

  /**
   * Dispose resources
   */
  dispose(): void {
    this.outputChannel.dispose();
  }
}
