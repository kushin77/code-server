/**
 * Agent Farm Orchestrator
 * 
 * Coordinates multiple agents, routes tasks, and aggregates recommendations
 * into a cohesive analysis result.
 */

import * as vscode from 'vscode';
import { Agent } from './agent';
import { TaskType, AgentResult, Recommendation, OrchestratorResult } from './types';
import { CodeAgent } from './agents/code-agent';
import { ReviewAgent } from './agents/review-agent';
import { ArchitectAgent } from './agents/architect-agent';
import { TestAgent } from './agents/test-agent';

/**
 * Orchestrates multiple AI agents for comprehensive code analysis
 */
export class AgentOrchestrator {
  private agents: Map<string, Agent>;
  private auditTrail: OrchestratorResult[] = [];
  private outputChannel: vscode.OutputChannel;

  constructor() {
    this.agents = new Map();
    this.outputChannel = vscode.window.createOutputChannel('Agent Farm: Orchestrator');
    this.initializeAgents();
  }

  /**
   * Initialize all available agents
   */
  private initializeAgents(): void {
    const agentInstances: Agent[] = [
      new CodeAgent(),
      new ReviewAgent(),
      new ArchitectAgent(),
      new TestAgent(),
    ];

    agentInstances.forEach(agent => {
      const metadata = agent.getMetadata();
      this.agents.set(metadata.name, agent);
      this.log(`Registered agent: ${metadata.name} (${metadata.specialization})`);
    });
  }

  /**
   * Route task to appropriate agents
   */
  private selectAgentsForTask(taskType: TaskType): Agent[] {
    return Array.from(this.agents.values()).filter(agent => agent.canHandle(taskType));
  }

  /**
   * Execute coordinated multi-agent analysis
   */
  async execute(
    documentUri: vscode.Uri,
    code: string,
    taskType?: TaskType
  ): Promise<OrchestratorResult> {
    const startTime = Date.now();
    const selectedTaskType = taskType || TaskType.CODE_REVIEW;

    this.log(`Starting orchestrated analysis on ${documentUri.fsPath}`);
    this.log(`Task type: ${selectedTaskType}`);

    // Select appropriate agents for this task
    const selectedAgents = this.selectAgentsForTask(selectedTaskType);
    
    if (selectedAgents.length === 0) {
      this.logError(`No agents available for task type: ${selectedTaskType}`);
      throw new Error(`No agents available for task type: ${selectedTaskType}`);
    }

    this.log(`Selected ${selectedAgents.length} agents: ${selectedAgents.map(a => a.getMetadata().name).join(', ')}`);

    // Execute all agents in parallel
    const agentResults = await Promise.all(
      selectedAgents.map(agent => 
        agent.execute(documentUri, code, { taskType: selectedTaskType })
          .catch(error => {
            this.logError(`Agent ${agent.getMetadata().name} failed: ${error.message}`);
            throw error;
          })
      )
    );

    // Aggregate recommendations from all agents
    const aggregatedRecommendations = this.aggregateRecommendations(agentResults);

    // Sort by severity (critical > warning > info)
    const severityOrder = { critical: 0, warning: 1, info: 2 };
    aggregatedRecommendations.sort(
      (a, b) => severityOrder[a.severity] - severityOrder[b.severity]
    );

    const totalDuration = Date.now() - startTime;
    const summary = this.generateSummary(agentResults, aggregatedRecommendations);

    const result: OrchestratorResult = {
      documentUri: documentUri.fsPath,
      totalDuration,
      agentResults,
      aggregatedRecommendations,
      summary,
    };

    this.auditTrail.push(result);
    this.log(`Analysis complete: ${totalDuration}ms, ${aggregatedRecommendations.length} total recommendations`);

    return result;
  }

  /**
   * Aggregate and deduplicate recommendations from multiple agents
   */
  private aggregateRecommendations(agentResults: AgentResult[]): Recommendation[] {
    const recommendationMap = new Map<string, Recommendation>();

    agentResults.forEach(result => {
      result.recommendations.forEach(rec => {
        // Use title as deduplication key
        const key = rec.title.toLowerCase();
        const existing = recommendationMap.get(key);

        if (existing) {
          // Upgrade severity if new recommendation is more severe
          const severityOrder = { critical: 2, warning: 1, info: 0 };
          if (severityOrder[rec.severity] > severityOrder[existing.severity]) {
            recommendationMap.set(key, rec);
          }
        } else {
          recommendationMap.set(key, rec);
        }
      });
    });

    return Array.from(recommendationMap.values());
  }

  /**
   * Generate summary statistics
   */
  private generateSummary(
    agentResults: AgentResult[],
    recommendations: Recommendation[]
  ): OrchestratorResult['summary'] {
    const criticalCount = recommendations.filter(r => r.severity === 'critical').length;
    const warningCount = recommendations.filter(r => r.severity === 'warning').length;
    const infoCount = recommendations.filter(r => r.severity === 'info').length;
    const averageConfidence = agentResults.length > 0
      ? agentResults.reduce((sum, r) => sum + r.confidence, 0) / agentResults.length
      : 0;

    return {
      totalRecommendations: recommendations.length,
      criticalCount,
      warningCount,
      infoCount,
      averageConfidence: Math.round(averageConfidence),
    };
  }

  /**
   * Get list of available agents
   */
  getAgents(): Array<{ name: string; specialization: string; taskTypes: TaskType[] }> {
    return Array.from(this.agents.values()).map(agent => {
      const metadata = agent.getMetadata();
      return {
        name: metadata.name,
        specialization: metadata.specialization,
        taskTypes: metadata.taskTypes,
      };
    });
  }

  /**
   * Get audit trail of all analyses
   */
  getAuditTrail(): OrchestratorResult[] {
    return [...this.auditTrail];
  }

  /**
   * Clear audit trail
   */
  clearAuditTrail(): void {
    this.auditTrail = [];
    this.log('Audit trail cleared');
  }

  /**
   * Log message to output channel
   */
  private log(message: string): void {
    this.outputChannel.appendLine(`[${new Date().toISOString()}] ${message}`);
  }

  /**
   * Log error to output channel
   */
  private logError(message: string): void {
    this.outputChannel.appendLine(`[ERROR] ${message}`);
  }

  /**
   * Show output channel
   */
  showOutput(): void {
    this.outputChannel.show();
  }

  /**
   * Dispose resources
   */
  dispose(): void {
    this.agents.forEach(agent => {
      if ('dispose' in agent && typeof agent.dispose === 'function') {
        (agent as any).dispose();
      }
    });
    this.outputChannel.dispose();
  }
}
