/**
 * Agent Farm - Base Agent Class
 * 
 * Provides core functionality for specialized AI agents optimized for specific domains.
 * Each agent implements domain-specific analysis and recommendations.
 */

import * as vscode from 'vscode';
import { AgentSpecialization, TaskType, Recommendation, AgentResult } from './types';

/**
 * Base class for all specialized agents
 */
export abstract class Agent {
  protected name: string;
  protected specialization: AgentSpecialization;
  protected taskTypes: TaskType[];
  protected outputChannel: vscode.OutputChannel;

  constructor(
    name: string,
    specialization: AgentSpecialization,
    taskTypes: TaskType[]
  ) {
    this.name = name;
    this.specialization = specialization;
    this.taskTypes = taskTypes;
    this.outputChannel = vscode.window.createOutputChannel(`Agent Farm: ${name}`);
  }

  /**
   * Analyze code and generate recommendations
   */
  abstract analyze(
    documentUri: vscode.Uri,
    code: string,
    context?: Record<string, unknown>
  ): Promise<Recommendation[]>;

  /**
   * Check if this agent can handle the given task
   */
  canHandle(taskType: TaskType): boolean {
    return this.taskTypes.includes(taskType);
  }

  /**
   * Get agent metadata for UI display
   */
  getMetadata(): {
    name: string;
    specialization: AgentSpecialization;
    taskTypes: TaskType[];
    description: string;
  } {
    return {
      name: this.name,
      specialization: this.specialization,
      taskTypes: this.taskTypes,
      description: `${this.name} - Specialized in ${this.specialization}`,
    };
  }

  /**
   * Prepare and execute agent analysis with metrics
   */
  async execute(
    documentUri: vscode.Uri,
    code: string,
    context?: Record<string, unknown>
  ): Promise<AgentResult> {
    const startTime = Date.now();
    
    try {
      this.log(`Starting analysis on ${documentUri.fsPath}`);
      
      const recommendations = await this.analyze(documentUri, code, context);
      const duration = Date.now() - startTime;

      const result: AgentResult = {
        agent: this.name,
        specialization: this.specialization,
        taskType: context?.taskType as TaskType || TaskType.CODE_REVIEW,
        timestamp: startTime,
        duration,
        recommendations,
        confidence: this.calculateConfidence(recommendations),
        metadata: {
          documentUri: documentUri.fsPath,
          codeLength: code.length,
          recommendationCount: recommendations.length,
        },
      };

      this.log(`Analysis complete: ${recommendations.length} recommendations in ${duration}ms`);
      return result;
    } catch (error) {
      this.logError(`Analysis failed: ${error instanceof Error ? error.message : String(error)}`);
      throw error;
    }
  }

  /**
   * Calculate confidence score based on recommendations
   */
  protected calculateConfidence(recommendations: Recommendation[]): number {
    if (recommendations.length === 0) return 50; // Base confidence for no findings
    
    const criticalCount = recommendations.filter(r => r.severity === 'critical').length;
    const actionableCount = recommendations.filter(r => r.actionable).length;
    
    // Confidence increases with actionable findings
    return Math.min(95, 60 + (actionableCount * 5) - (criticalCount * 10));
  }

  /**
   * Log message to output channel
   */
  protected log(message: string): void {
    this.outputChannel.appendLine(`[${new Date().toISOString()}] ${message}`);
  }

  /**
   * Log error to output channel
   */
  protected logError(message: string): void {
    this.outputChannel.appendLine(`[ERROR] ${message}`);
  }

  /**
   * Show output channel
   */
  showOutput(): void {
    this.outputChannel.show();
  }
}
