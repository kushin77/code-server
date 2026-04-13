/**
 * Phase 5: Knowledge Graph Integration Agent
 * Semantic code understanding through knowledge graphs
 */

import { Agent, AgentOutput, CodeContext, MultiAgentContext } from '../types';
import { CodeDependencyExtractor, DependencyGraph } from '../ml/CodeDependencyExtractor';
import { KnowledgeGraphBuilder, KnowledgeGraph } from '../ml/KnowledgeGraphBuilder';

export interface KnowledgeGraphQuery {
  type: 'dependency' | 'relationship' | 'architecture' | 'complexity' | 'impact';
  target: string;
  depth?: number;
  filters?: {
    types?: string[];
    complexity?: 'low' | 'medium' | 'high';
    bidirectional?: boolean;
  };
}

export interface KnowledgeGraphResult {
  query: KnowledgeGraphQuery;
  graph: KnowledgeGraph | DependencyGraph;
  analysis: {
    cyclicDependencies?: Array<{ nodes: string[]; severity: string }>;
    criticality: number;
    affectedComponents: string[];
    recommendations: string[];
  };
  reasoning: string;
}

export class KnowledgeGraphPhase5Agent extends Agent {
  readonly name = 'KnowledgeGraphPhase5Agent';
  readonly domain = 'Code Intelligence & Architecture';

  private dependencyExtractor: CodeDependencyExtractor;
  private graphBuilder: KnowledgeGraphBuilder;
  private cachedGraph: KnowledgeGraph | null = null;

  constructor() {
    super();
    this.dependencyExtractor = new CodeDependencyExtractor();
    this.graphBuilder = new KnowledgeGraphBuilder();
  }

  async analyze(context: CodeContext): Promise<AgentOutput> {
    try {
      this.log('Starting knowledge graph analysis...');
      const dependencies = await this.dependencyExtractor.extractDependencies(
        context.content,
        context.uri.fsPath
      );
      const recommendations: string[] = [];
      if (dependencies.length === 0) {
        recommendations.push('No dependencies found - module is testable independently');
      } else if (dependencies.length > 10) {
        recommendations.push(`High dependency count (${dependencies.length}) - consider breaking into smaller modules`);
      }
      const types = new Set(dependencies.map((d) => d.type));
      const summary = `Found ${dependencies.length} dependencies of types: ${Array.from(types).join(', ')}`;
      return this.formatOutput(summary, recommendations, dependencies.length > 10 ? 'warning' : 'info');
    } catch (error) {
      this.log(`Analysis error: ${error instanceof Error ? error.message : String(error)}`);
      return this.formatOutput('Analysis failed', ['Dependency extraction error'], 'error');
    }
  }

  async coordinate(context: MultiAgentContext, previousResults: AgentOutput[]): Promise<void> {
    this.log('Knowledge graph agent coordinating with other agents...');
  }

  private parseQuery(queryText: string): KnowledgeGraphQuery {
    const lower = queryText.toLowerCase();
    let type: KnowledgeGraphQuery['type'] = 'relationship';
    if (lower.includes('depend')) type = 'dependency';
    if (lower.includes('impact')) type = 'impact';
    if (lower.includes('complex')) type = 'complexity';
    if (lower.includes('architecture')) type = 'architecture';
    const ofMatch = queryText.match(/(?:of|for)\s+(\w+)/i);
    const target = ofMatch ? ofMatch[1] : queryText.split(/\s+/)[0];
    return { type, target };
  }

  private findNodeByLabel(label: string, graph: KnowledgeGraph): any {
    return Array.from(graph.nodes.values()).find((n) => n.label.toLowerCase() === label.toLowerCase());
  }

  private getNodeLabel(nodeId: string, graph: KnowledgeGraph): string {
    return graph.nodes.get(nodeId)?.label || nodeId;
  }

  private generateReasoning(query: KnowledgeGraphQuery, analysis: KnowledgeGraphResult['analysis']): string {
    return `Based on knowledge graph analysis for query type "${query.type}" on target "${query.target}": Criticality ${(analysis.criticality * 100).toFixed(1)}%, Components affected: ${analysis.affectedComponents.length}`;
  }
}

export default KnowledgeGraphPhase5Agent;
