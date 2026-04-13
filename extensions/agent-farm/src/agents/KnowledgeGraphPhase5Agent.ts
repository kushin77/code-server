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

  /**
   * Analyze code context using knowledge graph
   */
  async analyze(context: CodeContext): Promise<AgentOutput> {
    try {
      this.log('Starting knowledge graph analysis...');

      // Extract single file
      const dependencies = await this.dependencyExtractor.extractDependencies(
        context.content,
        context.uri.fsPath
      );

      const recommendations: string[] = [];

      // Analyze dependency structure
      if (dependencies.length === 0) {
        recommendations.push('No dependencies found - consider this module can be tested independently');
      } else if (dependencies.length > 10) {
        recommendations.push(`High dependency count (${dependencies.length}) - consider breaking into smaller modules`);
      }

      // Detect different dependency types
      const types = new Set(dependencies.map((d) => d.type));
      const summary = `Found ${dependencies.length} dependencies of types: ${Array.from(types).join(', ')}`;

      return this.formatOutput(summary, recommendations, dependencies.length > 10 ? 'warning' : 'info');
    } catch (error) {
      this.log(`Analysis error: ${error instanceof Error ? error.message : String(error)}`);
      return this.formatOutput('Analysis failed', ['Dependency extraction error'], 'error');
    }
  }

  /**
   * Coordinate with other agents
   */
  async coordinate(context: MultiAgentContext, previousResults: AgentOutput[]): Promise<void> {
    this.log('Knowledge graph agent coordinating with other agents...');

    // Could use previous results from other analysis agents
    const insights = previousResults.map((r) => `[${r.agentName}] ${r.summary}`).join('\n');

    if (insights) {
      this.log(`Incorporating insights:\n${insights}`);
    }
  }

  /**
   * Query the knowledge graph
   */
  async queryGraph(
    queryText: string,
    files: Array<{ path: string; content: string }>
  ): Promise<KnowledgeGraphResult> {
    // Parse query
    const parsedQuery = this.parseQuery(queryText);

    // Build graph if needed
    if (!this.cachedGraph || this.cachedGraph.nodes.size === 0) {
      await this.buildGraph(files);
    }

    const graph = this.cachedGraph!;

    // Execute query based on type
    let analysisResult;

    switch (parsedQuery.type) {
      case 'dependency':
        analysisResult = this.analyzeDependencies(parsedQuery.target, graph);
        break;
      case 'relationship':
        analysisResult = this.analyzeRelationships(parsedQuery.target, graph);
        break;
      case 'architecture':
        analysisResult = this.analyzeArchitecture(graph);
        break;
      case 'complexity':
        analysisResult = this.analyzeComplexity(parsedQuery.target, graph);
        break;
      case 'impact':
        analysisResult = this.analyzeImpact(parsedQuery.target, graph);
        break;
      default:
        analysisResult = this.analyzeRelationships(parsedQuery.target, graph);
    }

    return {
      query: parsedQuery,
      graph,
      analysis: analysisResult,
      reasoning: this.generateReasoning(parsedQuery, analysisResult),
    };
  }

  /**
   * Build knowledge graph from files
   */
  private async buildGraph(files: Array<{ path: string; content: string }>): Promise<void> {
    const startTime = performance.now();

    // Extract dependencies from all files
    const depGraph = this.dependencyExtractor.buildDependencyGraph(files);

    // Build knowledge graph
    this.graphBuilder.buildFromDependencyGraph(depGraph);
    this.cachedGraph = this.graphBuilder.getGraph();

    const duration = performance.now() - startTime;
    this.log(`Built graph with ${this.cachedGraph.nodes.size} nodes and ${this.cachedGraph.edges.size} edges in ${duration.toFixed(2)}ms`);
  }

  /**
   * Analyze dependencies of a target
   */
  private analyzeDependencies(
    target: string,
    graph: KnowledgeGraph
  ): KnowledgeGraphResult['analysis'] {
    const targetNode = this.findNodeByLabel(target, graph);
    if (!targetNode) {
      return {
        cyclicDependencies: [],
        criticality: 0,
        affectedComponents: [],
        recommendations: [`Target "${target}" not found in codebase`],
      };
    }

    const outgoing: Array<{ target: string; relation: string; weight: number }> = [];
    const incoming: Array<{ source: string; relation: string; weight: number }> = [];

    // Iterate through edges using the correct property names
    for (const edge of graph.edges.values()) {
      if (edge.fromId === targetNode.id) {
        outgoing.push({
          target: this.getNodeLabel(edge.toId, graph),
          relation: edge.relation,
          weight: edge.weight ?? 1,
        });
      } else if (edge.toId === targetNode.id) {
        incoming.push({
          source: this.getNodeLabel(edge.fromId, graph),
          relation: edge.relation,
          weight: edge.weight ?? 1,
        });
      }
    }

    const criticality = (incoming.length + outgoing.length * 0.5) / (graph.nodes.size || 1);

    return {
      cyclicDependencies: [],
      criticality,
      affectedComponents: [...incoming.map((i) => i.source), ...outgoing.map((o) => o.target)],
      recommendations: [
        criticality > 0.5
          ? `${target} is a critical component with ${incoming.length} dependents`
          : `${target} has moderate dependency density`,
        incoming.length === 0 ? `Consider if ${target} can be removed or refactored` : '',
      ].filter(Boolean),
    };
  }

  /**
   * Analyze relationships
   */
  private analyzeRelationships(
    target: string,
    graph: KnowledgeGraph
  ): KnowledgeGraphResult['analysis'] {
    const results = this.graphBuilder.search(target, 5);

    if (results.length === 0) {
      return {
        cyclicDependencies: [],
        criticality: 0,
        affectedComponents: [],
        recommendations: [`No components related to "${target}" found`],
      };
    }

    const relatedLabels = results.map((r) => r.label);

    return {
      cyclicDependencies: [],
      criticality: results.length > 0 ? 0.5 : 0,
      affectedComponents: relatedLabels,
      recommendations: [
        `Found ${results.length} related components`,
        `Consider refactoring ${results.slice(0, 2).map((r) => r.label).join(', ')} together`,
      ],
    };
  }

  /**
   * Analyze architecture
   */
  private analyzeArchitecture(graph: KnowledgeGraph): KnowledgeGraphResult['analysis'] {
    const stats = this.graphBuilder.getStatistics();
    const communities = this.graphBuilder.detectCommunities();

    return {
      cyclicDependencies: [],
      criticality: (stats.nodeCount / (graph.nodes.size || 1)) * 0.5,
      affectedComponents: Array.from(graph.nodes.values()).map((n) => n.label),
      recommendations: [
        `Architecture has ${communities.length} communities`,
        `Densest nodes: ${stats.densestNodes.slice(0, 3).join(', ')}`,
        `Type distribution: ${Object.entries(stats.typeDistribution)
          .map(([k, v]) => `${k}(${v})`)
          .join(', ')}`,
      ],
    };
  }

  /**
   * Analyze complexity
   */
  private analyzeComplexity(target: string, graph: KnowledgeGraph): KnowledgeGraphResult['analysis'] {
    const targetNode = this.findNodeByLabel(target, graph);
    if (!targetNode) {
      return {
        cyclicDependencies: [],
        criticality: 0,
        affectedComponents: [],
        recommendations: [`Target "${target}" not found`],
      };
    }

    let outEdges = 0;
    let inEdges = 0;

    for (const edge of graph.edges.values()) {
      if (edge.fromId === targetNode.id) outEdges++;
      if (edge.toId === targetNode.id) inEdges++;
    }

    const complexity = (inEdges + outEdges) / (graph.nodes.size || 1);

    return {
      cyclicDependencies: [],
      criticality: complexity,
      affectedComponents: [target],
      recommendations: [
        complexity > 0.3 ? `${target} has HIGH complexity with ${inEdges + outEdges} connections` : '',
        outEdges > inEdges ? `${target} is a hub that depends on many modules` : '',
        inEdges > outEdges ? `${target} is a core dependency for many modules` : '',
      ].filter(Boolean),
    };
  }

  /**
   * Analyze impact of changes
   */
  private analyzeImpact(target: string, graph: KnowledgeGraph): KnowledgeGraphResult['analysis'] {
    const targetNode = this.findNodeByLabel(target, graph);
    if (!targetNode) {
      return {
        cyclicDependencies: [],
        criticality: 0,
        affectedComponents: [],
        recommendations: [`Target "${target}" not found`],
      };
    }

    // Find all nodes that depend on target using BFS
    const dependents = new Set<string>();
    const queue = [targetNode.id];
    const visited = new Set<string>();

    while (queue.length > 0) {
      const nodeId = queue.shift()!;
      if (visited.has(nodeId)) continue;
      visited.add(nodeId);

      for (const edge of graph.edges.values()) {
        if (edge.toId === nodeId && !visited.has(edge.fromId)) {
          dependents.add(edge.fromId);
          queue.push(edge.fromId);
        }
      }
    }

    const impactScore = dependents.size / (graph.nodes.size || 1);

    return {
      cyclicDependencies: [],
      criticality: impactScore,
      affectedComponents: Array.from(dependents).map((id) => this.getNodeLabel(id, graph)),
      recommendations: [
        `Changing ${target} would impact ${dependents.size} components`,
        dependents.size > 5 ? `CRITICAL: This is a breaking change for ${dependents.size} modules` : '',
        `Test ${Math.min(5, dependents.size)} most-used dependents before deployment`,
      ].filter(Boolean),
    };
  }

  /**
   * Parse natural language query
   */
  private parseQuery(queryText: string): KnowledgeGraphQuery {
    const lower = queryText.toLowerCase();

    let type: KnowledgeGraphQuery['type'] = 'relationship';
    if (lower.includes('depend')) type = 'dependency';
    if (lower.includes('impact')) type = 'impact';
    if (lower.includes('complex')) type = 'complexity';
    if (lower.includes('architecture')) type = 'architecture';

    // Extract target (word after "of" or "for")
    const ofMatch = queryText.match(/(?:of|for)\s+(\w+)/i);
    const target = ofMatch ? ofMatch[1] : queryText.split(/\s+/)[0];

    return { type, target };
  }

  /**
   * Find node by label
   */
  private findNodeByLabel(label: string, graph: KnowledgeGraph): any {
    return Array.from(graph.nodes.values()).find((n) => n.label.toLowerCase() === label.toLowerCase());
  }

  /**
   * Get node label
   */
  private getNodeLabel(nodeId: string, graph: KnowledgeGraph): string {
    return graph.nodes.get(nodeId)?.label || nodeId;
  }

  /**
   * Generate reasoning explanation
   */
  private generateReasoning(query: KnowledgeGraphQuery, analysis: KnowledgeGraphResult['analysis']): string {
    return `Based on knowledge graph analysis for query type "${query.type}" on target "${query.target}":
    - Criticality score: ${(analysis.criticality * 100).toFixed(1)}%
    - Affected components: ${analysis.affectedComponents.length}
    - Key findings: ${analysis.recommendations.slice(0, 2).join('; ')}`;
  }
}

export default KnowledgeGraphPhase5Agent;
/**
 * Phase 5: Knowledge Graph Integration Agent
 * Semantic code understanding through knowledge graphs
 */

import { Agent } from '../phases';
import { CodeDependencyExtractor, DependencyGraph } from '../ml/CodeDependencyExtractor';
import { KnowledgeGraphBuilder, KnowledgeGraph } from '../ml/KnowledgeGraphBuilder';
import { RelationshipAnalyzer, CallGraph } from '../ml/RelationshipAnalyzer';

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
  graph: KnowledgeGraph | DependencyGraph | CallGraph;
  analysis: {
    cyclicDependencies?: Array<{ nodes: string[]; severity: string }>;
    criticality: number;
    affectedComponents: string[];
    recommendations: string[];
  };
  reasoning: string;
}

export class KnowledgeGraphPhase5Agent extends Agent {
  private dependencyExtractor: CodeDependencyExtractor;
  private graphBuilder: KnowledgeGraphBuilder;
  private relationshipAnalyzer: RelationshipAnalyzer;

  constructor(context: any) {
    super('KnowledgeGraphPhase5Agent', context);
    this.dependencyExtractor = new CodeDependencyExtractor();
    this.graphBuilder = new KnowledgeGraphBuilder();
    this.relationshipAnalyzer = new RelationshipAnalyzer();
  }

  /**
   * Analyze code and build knowledge graph
   */
  async analyzeCodebase(files: Array<{ path: string; content: string }>): Promise<KnowledgeGraph> {
    const startTime = performance.now();

    // Extract dependencies
    const depGraph = this.dependencyExtractor.buildDependencyGraph(files);

    // Build knowledge graph
    this.graphBuilder.buildFromDependencyGraph(depGraph);

    // Analyze relationships
    const callGraph = this.relationshipAnalyzer.buildCallGraph(files);
    const inheritanceHierarchy = this.relationshipAnalyzer.analyzeInheritanceHierarchy(files);

    // Enrich graph with analysis
    this.graphBuilder.enrichWithCallGraph(callGraph);

    const graph = this.graphBuilder.getGraph();
    const duration = performance.now() - startTime;

    this.log(`Analyzed ${files.length} files in ${duration.toFixed(2)}ms`);
    this.log(`Built graph with ${graph.nodes.size} nodes and ${graph.edges.size} edges`);

    return graph;
  }

  /**
   * Query the knowledge graph
   */
  async query(queryText: string, files: Array<{ path: string; content: string }>): Promise<KnowledgeGraphResult> {
    // Parse query
    const parsedQuery = this.parseQuery(queryText);

    // Build graph if needed
    if (this.graphBuilder.getGraph().nodes.size === 0) {
      await this.analyzeCodebase(files);
    }

    // Execute query based on type
    let analysisResult;
    const graph = this.graphBuilder.getGraph();

    switch (parsedQuery.type) {
      case 'dependency':
        analysisResult = this.analyzeDependencies(parsedQuery.target, graph);
        break;
      case 'relationship':
        analysisResult = this.analyzeRelationships(parsedQuery.target, graph);
        break;
      case 'architecture':
        analysisResult = this.analyzeArchitecture(graph);
        break;
      case 'complexity':
        analysisResult = this.analyzeComplexity(parsedQuery.target, graph);
        break;
      case 'impact':
        analysisResult = this.analyzeImpact(parsedQuery.target, graph);
        break;
      default:
        analysisResult = this.analyzeRelationships(parsedQuery.target, graph);
    }

    return {
      query: parsedQuery,
      graph,
      analysis: analysisResult,
      reasoning: this.generateReasoning(parsedQuery, analysisResult),
    };
  }

  /**
   * Analyze dependencies of a target
   */
  private analyzeDependencies(
    target: string,
    graph: KnowledgeGraph
  ): KnowledgeGraphResult['analysis'] {
    const targetNode = this.findNodeByLabel(target, graph);
    if (!targetNode) {
      return {
        cyclicDependencies: [],
        criticality: 0,
        affectedComponents: [],
        recommendations: [`Target "${target}" not found in codebase`],
      };
    }

    const outgoing = graph.edges
      .values()
      .filter((e) => e.from === targetNode.id)
      .map((e) => ({
        target: this.getNodeLabel(e.to, graph),
        type: e.type,
        strength: e.strength,
      }));

    const incoming = graph.edges
      .values()
      .filter((e) => e.to === targetNode.id)
      .map((e) => ({
        source: this.getNodeLabel(e.from, graph),
        type: e.type,
        strength: e.strength,
      }));

    const criticality = (incoming.length + outgoing.length * 0.5) / (graph.nodes.size || 1);

    return {
      cyclicDependencies: [],
      criticality,
      affectedComponents: [...incoming.map((i) => i.source), ...outgoing.map((o) => o.target)],
      recommendations: [
        criticality > 0.5
          ? `${target} is a critical component with ${incoming.length} dependents`
          : `${target} has moderate dependency density`,
        incoming.length === 0 ? `Consider if ${target} can be removed or refactored` : '',
      ].filter(Boolean),
    };
  }

  /**
   * Analyze relationships
   */
  private analyzeRelationships(
    target: string,
    graph: KnowledgeGraph
  ): KnowledgeGraphResult['analysis'] {
    const results = this.graphBuilder.search(target, 5);

    if (results.length === 0) {
      return {
        cyclicDependencies: [],
        criticality: 0,
        affectedComponents: [],
        recommendations: [`No components related to "${target}" found`],
      };
    }

    const relatedLabels = results.map((r) => r.label);

    return {
      cyclicDependencies: [],
      criticality: results.length > 0 ? 0.5 : 0,
      affectedComponents: relatedLabels,
      recommendations: [
        `Found ${results.length} related components`,
        `Consider refactoring ${results.slice(0, 2).map((r) => r.label).join(', ')} together`,
      ],
    };
  }

  /**
   * Analyze architecture
   */
  private analyzeArchitecture(graph: KnowledgeGraph): KnowledgeGraphResult['analysis'] {
    const stats = this.graphBuilder.getStatistics();
    const communities = this.graphBuilder.detectCommunities();

    return {
      cyclicDependencies: [],
      criticality: (stats.nodeCount / (graph.nodes.size || 1)) * 0.5,
      affectedComponents: Array.from(graph.nodes.values()).map((n) => n.label),
      recommendations: [
        `Architecture has ${communities.length} communities`,
        `Densest nodes: ${stats.densestNodes.slice(0, 3).join(', ')}`,
        `Type distribution: ${Object.entries(stats.typeDistribution)
          .map(([k, v]) => `${k}(${v})`)
          .join(', ')}`,
      ],
    };
  }

  /**
   * Analyze complexity
   */
  private analyzeComplexity(target: string, graph: KnowledgeGraph): KnowledgeGraphResult['analysis'] {
    const targetNode = this.findNodeByLabel(target, graph);
    if (!targetNode) {
      return {
        cyclicDependencies: [],
        criticality: 0,
        affectedComponents: [],
        recommendations: [`Target "${target}" not found`],
      };
    }

    const pathsOut = this.graphBuilder.findShortestPath(targetNode.id, '');
    const outEdges = Array.from(graph.edges.values()).filter((e) => e.from === targetNode.id).length;
    const inEdges = Array.from(graph.edges.values()).filter((e) => e.to === targetNode.id).length;

    const complexity = (inEdges + outEdges) / (graph.nodes.size || 1);

    return {
      cyclicDependencies: [],
      criticality: complexity,
      affectedComponents: [target],
      recommendations: [
        complexity > 0.3 ? `${target} has HIGH complexity with ${inEdges + outEdges} connections` : '',
        outEdges > inEdges ? `${target} is a hub that depends on many modules` : '',
        inEdges > outEdges ? `${target} is a core dependency for many modules` : '',
      ].filter(Boolean),
    };
  }

  /**
   * Analyze impact of changes
   */
  private analyzeImpact(target: string, graph: KnowledgeGraph): KnowledgeGraphResult['analysis'] {
    const targetNode = this.findNodeByLabel(target, graph);
    if (!targetNode) {
      return {
        cyclicDependencies: [],
        criticality: 0,
        affectedComponents: [],
        recommendations: [`Target "${target}" not found`],
      };
    }

    // Find all nodes that depend on target
    const dependents = new Set<string>();
    const queue = [targetNode.id];

    while (queue.length > 0) {
      const nodeId = queue.shift()!;
      Array.from(graph.edges.values())
        .filter((e) => e.to === nodeId)
        .forEach((e) => {
          if (!dependents.has(e.from)) {
            dependents.add(e.from);
            queue.push(e.from);
          }
        });
    }

    const impactScore = dependents.size / (graph.nodes.size || 1);

    return {
      cyclicDependencies: [],
      criticality: impactScore,
      affectedComponents: Array.from(dependents).map((id) => this.getNodeLabel(id, graph)),
      recommendations: [
        `Changing ${target} would impact ${dependents.size} components`,
        dependents.size > 5 ? `CRITICAL: This is a breaking change for ${dependents.size} modules` : '',
        `Test ${Math.min(5, dependents.size)} most-used dependents before deployment`,
      ].filter(Boolean),
    };
  }

  /**
   * Parse natural language query
   */
  private parseQuery(queryText: string): KnowledgeGraphQuery {
    const lower = queryText.toLowerCase();

    let type: KnowledgeGraphQuery['type'] = 'relationship';
    if (lower.includes('depend')) type = 'dependency';
    if (lower.includes('impact')) type = 'impact';
    if (lower.includes('complex')) type = 'complexity';
    if (lower.includes('architecture')) type = 'architecture';

    // Extract target (word after "of" or "for")
    const ofMatch = queryText.match(/(?:of|for)\s+(\w+)/i);
    const target = ofMatch ? ofMatch[1] : queryText.split(/\s+/)[0];

    return { type, target };
  }

  /**
   * Find node by label
   */
  private findNodeByLabel(label: string, graph: KnowledgeGraph): any {
    return Array.from(graph.nodes.values()).find((n) => n.label.toLowerCase() === label.toLowerCase());
  }

  /**
   * Get node label
   */
  private getNodeLabel(nodeId: string, graph: KnowledgeGraph): string {
    return graph.nodes.get(nodeId)?.label || nodeId;
  }

  /**
   * Generate reasoning explanation
   */
  private generateReasoning(query: KnowledgeGraphQuery, analysis: KnowledgeGraphResult['analysis']): string {
    return `Based on knowledge graph analysis for query type "${query.type}" on target "${query.target}":
    - Criticality score: ${(analysis.criticality * 100).toFixed(1)}%
    - Affected components: ${analysis.affectedComponents.length}
    - Key findings: ${analysis.recommendations.slice(0, 2).join('; ')}`;
  }

  async execute(input: any): Promise<KnowledgeGraphResult> {
    const files = input.files || [];
    const query = input.query || 'Analyze dependencies';

    return this.query(query, files);
  }
}

export default KnowledgeGraphPhase5Agent;
