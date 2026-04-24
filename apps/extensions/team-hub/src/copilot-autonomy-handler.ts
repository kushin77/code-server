// @file apps/extensions/team-hub/src/copilot-autonomy-handler.ts
// @module ide/copilot-autonomy
// @description P2-1539 Phase 2: Handle Copilot autonomy with context injection
// @governance GOV-002: All Copilot interactions logged and audited

import * as vscode from 'vscode';
import { CopilotContextEngine, ContextQueryResult } from './copilot-context-engine';
import { AutonomousTaskDetector, AutonomousTask, TaskSeverity } from './autonomous-task-detector';

export interface CopilotInteraction {
  id: string;
  timestamp: string;
  prompt: string;
  task: AutonomousTask | null;
  contextUsed: boolean;
  contextSize: number;
  responseTime: number;
  status: 'success' | 'error' | 'pending_approval';
}

export class CopilotAutonomyHandler {
  private contextEngine: CopilotContextEngine;
  private taskDetector: AutonomousTaskDetector;
  private interactions: CopilotInteraction[] = [];
  private outputChannel: vscode.OutputChannel;

  constructor() {
    this.contextEngine = new CopilotContextEngine();
    this.taskDetector = new AutonomousTaskDetector();
    this.outputChannel = vscode.window.createOutputChannel('KC IDE Copilot Autonomy');
  }

  /**
   * Handle a Copilot prompt with autonomous task detection and context injection
   */
  async handleCopilotPrompt(prompt: string): Promise<{
    enhancedPrompt: string;
    task: AutonomousTask | null;
    context: ContextQueryResult | null;
  }> {
    const startTime = Date.now();
    const interaction: CopilotInteraction = {
      id: `interact-${Date.now()}-${Math.random().toString(36).substring(7)}`,
      timestamp: new Date().toISOString(),
      prompt,
      task: null,
      contextUsed: false,
      contextSize: 0,
      responseTime: 0,
      status: 'pending_approval'
    };

    try {
      this.log(`[${interaction.id}] Processing prompt: ${prompt.substring(0, 100)}...`);

      // Step 1: Detect autonomous task
      const task = this.taskDetector.analyzePrompt(prompt);
      interaction.task = task;

      if (!task) {
        this.log(`[${interaction.id}] No task pattern detected, passing through to Copilot`);
        return {
          enhancedPrompt: prompt,
          task: null,
          context: null
        };
      }

      this.log(`[${interaction.id}] Task detected: ${task.category} (severity: ${task.severity})`);
      this.log(`[${interaction.id}] Confidence: ${(task.confidence * 100).toFixed(1)}%`);
      this.log(`[${interaction.id}] Requires approval: ${task.requiresApproval}`);

      // Step 2: Build context for the task
      let context: ContextQueryResult | null = null;
      let enhancedPrompt = prompt;

      if (task.confidence > 0.7) {
        context = await this.contextEngine.buildContext(prompt);
        interaction.contextUsed = true;
        interaction.contextSize = context.sources.docs.length + context.sources.issues.length;

        this.log(`[${interaction.id}] Context built: ${interaction.contextSize} sources`);

        // Append context to prompt for Copilot
        const formattedContext = this.contextEngine.formatContextForPrompt(context);
        enhancedPrompt = `${formattedContext}\n\n## Original Task:\n${prompt}`;
      }

      // Step 3: Handle based on approval requirement
      if (task.requiresApproval && task.severity === TaskSeverity.CRITICAL) {
        this.log(`[${interaction.id}] ⚠️  CRITICAL task requires user approval`);
        interaction.status = 'pending_approval';

        // Show approval dialog
        const approved = await this.requestUserApproval(task);
        if (!approved) {
          this.log(`[${interaction.id}] User declined approval`);
          return {
            enhancedPrompt: `⚠️  BLOCKED: User declined execution of critical task.\n\n${prompt}`,
            task,
            context
          };
        }
      }

      interaction.status = 'success';
      interaction.responseTime = Date.now() - startTime;
      this.interactions.push(interaction);

      this.log(`[${interaction.id}] ✅ Complete (${interaction.responseTime}ms)`);

      return {
        enhancedPrompt,
        task,
        context
      };
    } catch (error) {
      interaction.status = 'error';
      interaction.responseTime = Date.now() - startTime;
      this.interactions.push(interaction);

      this.log(`[${interaction.id}] ❌ Error: ${error}`);
      throw error;
    }
  }

  /**
   * Request user approval for critical tasks
   */
  private async requestUserApproval(task: AutonomousTask): Promise<boolean> {
    const response = await vscode.window.showWarningMessage(
      `⚠️  Copilot is requesting execution of a ${task.severity} task`,
      {
        detail: `\nTask: ${task.action}\nEstimated duration: ${task.estimatedDuration}s\n\nThis action requires your approval.`,
        modal: true
      },
      'Approve',
      'Deny'
    );

    return response === 'Approve';
  }

  /**
   * Log message to output channel and console
   */
  private log(message: string): void {
    this.outputChannel.appendLine(message);
    console.log(`[CopilotAutonomyHandler] ${message}`);
  }

  /**
   * Get interaction history
   */
  getInteractionHistory(): CopilotInteraction[] {
    return [...this.interactions];
  }

  /**
   * Get statistics on autonomous task execution
   */
  getStatistics(): {
    totalInteractions: number;
    successfulTasks: number;
    approvalRequired: number;
    averageResponseTime: number;
  } {
    const stats = {
      totalInteractions: this.interactions.length,
      successfulTasks: this.interactions.filter(i => i.status === 'success').length,
      approvalRequired: this.interactions.filter(i => i.task?.requiresApproval).length,
      averageResponseTime: 0
    };

    if (this.interactions.length > 0) {
      const totalTime = this.interactions.reduce((sum, i) => sum + i.responseTime, 0);
      stats.averageResponseTime = totalTime / this.interactions.length;
    }

    return stats;
  }

  /**
   * Show statistics in output channel
   */
  showStatistics(): void {
    const stats = this.getStatistics();
    this.log(`
===== Copilot Autonomy Statistics =====
Total Interactions: ${stats.totalInteractions}
Successful Tasks: ${stats.successfulTasks}
Approval Required: ${stats.approvalRequired}
Average Response Time: ${stats.averageResponseTime.toFixed(0)}ms
======================================
    `);
  }
}

export function createCopilotAutonomyHandler(): CopilotAutonomyHandler {
  return new CopilotAutonomyHandler();
}
