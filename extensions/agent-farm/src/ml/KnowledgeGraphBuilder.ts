/**
 * Phase 5: Knowledge Graph Integration
 * KnowledgeGraphBuilder - Build searchable semantic graph from code dependencies
 */

import { CodeDependency, DependencyGraph, DependencyNode } from './CodeDependencyExtractor';

export interface KnowledgeGraphNode {
  id: string;
  type: 'file' | 'function' | 'class' | 'module' | 'package' | 'interface' | 'type';
  label: string;
  filePath: string;
  line: number;
  embedding?: number[];
  metadata: Record<string, any>;
  relatedNodes: string[];
  importance: number; // 0-1 ranking importance
  tags: string[];
}

export interface KnowledgeGraphEdge {
  fromId: string;
  toId: string;
  relation: string;
  weight: number;
  metadata: Record<string, any>;
}

export interface KnowledgeGraph {
  nodes: Map<string, KnowledgeGraphNode>;
  edges: Map<string, KnowledgeGraphEdge>;
  metadata: GraphMetadata;
}

export interface GraphMetadata {
  totalNodes: number;
  totalEdges: number;
  lastUpdated: Date;
  codebaseMetrics: CodebaseMetrics;
}

export interface CodebaseMetrics {
  totalFiles: number;
  totalFunctions: number;
  totalClasses: number;
  averageComplexity: number;
  cyclicDependencies: number;
}

export interface ContextGraph {
  centerNode: KnowledgeGraphNode;
  neighbors: KnowledgeGraphNode[];
  edges: KnowledgeGraphEdge[];
  depth: number;
}

/**
 * Build and manage semantic code knowledge graph
 */
export class KnowledgeGraphBuilder {
  private nodes = new Map<string, KnowledgeGraphNode>();
  private edges = new Map<string, KnowledgeGraphEdge>();
  private embeddingCache = new Map<string, number[]>();
  private metadata: GraphMetadata = {
    totalNodes: 0,
    totalEdges: 0,
    lastUpdated: new Date(),
    codebaseMetrics: {
      totalFiles: 0,
      totalFunctions: 0,
      totalClasses: 0,
      averageComplexity: 0,
      cyclicDependencies: 0,
    },
  };

  /**
   * Add a node to the graph
   */
  addNode(node: KnowledgeGraphNode): void {
    // Compute importance based on relationships
    const relatedCount = node.relatedNodes.length;
    node.importance = Math.min(1, 0.1 + (relatedCount * 0.1));

    this.nodes.set(node.id, node);
    this.metadata.totalNodes = this.nodes.size;
    this.metadata.lastUpdated = new Date();

    // Update codebase metrics
    if (node.type === 'file') this.metadata.codebaseMetrics.totalFiles++;
    if (node.type === 'function') this.metadata.codebaseMetrics.totalFunctions++;
    if (node.type === 'class') this.metadata.codebaseMetrics.totalClasses++;
  }

  /**
   * Add an edge between nodes
   */
  addEdge(fromId: string, toId: string, relation: string, weight: number = 1.0): void {
    const edgeId = `${fromId}-${relation}->${toId}`;

    if (!this.nodes.has(fromId) || !this.nodes.has(toId)) {
      console.warn(`Cannot add edge: missing nodes ${fromId} or ${toId}`);
      return;
    }

    const edge: KnowledgeGraphEdge = {
      fromId,
      toId,
      relation,
      weight: Math.min(1, weight),
      metadata: {},
    };

    this.edges.set(edgeId, edge);
    this.metadata.totalEdges = this.edges.size;

    // Update node relationships
    const fromNode = this.nodes.get(fromId);
    const toNode = this.nodes.get(toId);

    if (fromNode && !fromNode.relatedNodes.includes(toId)) {
      fromNode.relatedNodes.push(toId);
    }
    if (toNode && !toNode.relatedNodes.includes(fromId)) {
      toNode.relatedNodes.push(fromId);
    }
  }

  /**
   * Query by relationship type
   */
  queryByRelationship(query: string, relation?: string, hops: number = 1): KnowledgeGraphNode[] {
    const results: KnowledgeGraphNode[] = [];
    const visited = new Set<string>();

    // Find starting nodes
    const startNodes = Array.from(this.nodes.values()).filter(
      (n) =>
        n.label.toLowerCase().includes(query.toLowerCase()) ||
        n.tags.some((t) => t.toLowerCase().includes(query.toLowerCase()))
    );

    // BFS to find related nodes
    const queue: Array<{ node: KnowledgeGraphNode; depth: number }> = startNodes.map((n) => ({
      node: n,
      depth: 0,
    }));

    while (queue.length > 0) {
      const { node, depth } = queue.shift()!;

      if (visited.has(node.id) || depth > hops) continue;
      visited.add(node.id);
      results.push(node);

      // Find connected nodes
      const connectedEdges = Array.from(this.edges.values()).filter(
        (e) =>
          (e.fromId === node.id || e.toId === node.id) &&
          (!relation || e.relation === relation)
      );

      connectedEdges.forEach((edge) => {
        const nextId = edge.fromId === node.id ? edge.toId : edge.fromId;
        const nextNode = this.nodes.get(nextId);
        if (nextNode && !visited.has(nextId) && depth < hops) {
          queue.push({ node: nextNode, depth: depth + 1 });
        }
      });
    }

    return results;
  }

  /**
   * Find shortest path between two nodes
   */
  findShortestPath(fromId: string, toId: string): string[] {
    if (!this.nodes.has(fromId) || !this.nodes.has(toId)) {
      return [];
    }

    const queue: Array<{ nodeId: string; path: string[] }> = [
      { nodeId: fromId, path: [fromId] },
    ];
    const visited = new Set<string>();

    while (queue.length > 0) {
      const { nodeId, path } = queue.shift()!;

      if (nodeId === toId) {
        return path;
      }

      if (visited.has(nodeId)) continue;
      visited.add(nodeId);

      // Find neighbors
      const neighborEdges = Array.from(this.edges.values()).filter(
        (e) => e.fromId === nodeId || e.toId === nodeId
      );

      neighborEdges.forEach((edge) => {
        const nextId = edge.fromId === nodeId ? edge.toId : edge.fromId;
        if (!visited.has(nextId)) {
          queue.push({ nodeId: nextId, path: [...path, nextId] });
        }
      });
    }

    return []; // No path found
  }

  /**
   * Get context graph for a node
   */
  getNodeContext(nodeId: string, depth: number = 2): ContextGraph {
    const node = this.nodes.get(nodeId);
    if (!node) {
      throw new Error(`Node not found: ${nodeId}`);
    }

    const neighbors: KnowledgeGraphNode[] = [];
    const edges: KnowledgeGraphEdge[] = [];
    const visited = new Set<string>();

    // BFS to collect neighbors at specified depth
    const queue: Array<{ nodeId: string; d: number }> = [{ nodeId, d: 0 }];

    while (queue.length > 0) {
      const { nodeId: currentId, d } = queue.shift()!;

      if (visited.has(currentId) || d > depth) continue;
      visited.add(currentId);

      // Get connected nodes
      const connectedEdges = Array.from(this.edges.values()).filter(
        (e) => e.fromId === currentId || e.toId === currentId
      );

      connectedEdges.forEach((edge) => {
        edges.push(edge);
        const nextId = edge.fromId === currentId ? edge.toId : edge.fromId;
        const nextNode = this.nodes.get(nextId);

        if (nextNode && !visited.has(nextId)) {
          neighbors.push(nextNode);
          if (d < depth) {
            queue.push({ nodeId: nextId, d: d + 1 });
          }
        }
      });
    }

    return {
      centerNode: node,
      neighbors,
      edges,
      depth,
    };
  }

  /**
   * Build graph from dependency graph
   */
  buildFromDependencyGraph(depGraph: DependencyGraph): void {
    // Add nodes
    depGraph.nodes.forEach((depNode) => {
      const graphNode: KnowledgeGraphNode = {
        id: depNode.id,
        type: (depNode.type as any) === 'module' ? 'file' : (depNode.type as any),
        label: depNode.name,
        filePath: depNode.filePath,
        line: depNode.line,
        metadata: {
          inDegree: depNode.metrics.inDegree,
          outDegree: depNode.metrics.outDegree,
          cyclicDepth: depNode.metrics.cyclicDepth,
        },
        relatedNodes: depNode.dependencies.concat(depNode.dependents),
        importance: 0,
        tags: this.extractTags(depNode.name, depNode.type as any),
      };

      this.addNode(graphNode);
    });

    // Add edges from dependencies
    depGraph.edges.forEach((dep) => {
      const fromId = `${dep.from.file}:${dep.from.symbol}`;
      const toId = `${dep.to.file}:${dep.to.symbol}`;

      if (this.nodes.has(fromId) && this.nodes.has(toId)) {
        this.addEdge(fromId, toId, dep.to.type, dep.strength);
      }
    });
  }

  /**
   * Get the complete knowledge graph
   */
  getGraph(): KnowledgeGraph {
    return {
      nodes: this.nodes,
      edges: this.edges,
      metadata: this.metadata,
    };
  }

  /**
   * Search for nodes by keyword
   */
  search(keyword: string, limit: number = 10): KnowledgeGraphNode[] {
    const results = Array.from(this.nodes.values())
      .filter(
        (n) =>
          n.label.toLowerCase().includes(keyword.toLowerCase()) ||
          n.tags.some((t) => t.toLowerCase().includes(keyword.toLowerCase()))
      )
      .sort((a, b) => b.importance - a.importance)
      .slice(0, limit);

    return results;
  }

  /**
   * Get statistics about the graph
   */
  getStatistics(): GraphStatistics {
    const nodes = Array.from(this.nodes.values());
    const edges = Array.from(this.edges.values());

    const complexity = nodes.reduce(
      (sum, n) =>
        sum +
        (n.metadata.inDegree || 0) +
        (n.metadata.outDegree || 0),
      0
    ) / nodes.length || 0;

    const typeDistribution: Record<string, number> = {};
    nodes.forEach((n) => {
      typeDistribution[n.type] = (typeDistribution[n.type] || 0) + 1;
    });

    return {
      nodeCount: nodes.length,
      edgeCount: edges.length,
      averageComplexity: complexity,
      typeDistribution,
      densestNodes: nodes
        .sort((a, b) => b.relatedNodes.length - a.relatedNodes.length)
        .slice(0, 5)
        .map((n) => ({ id: n.id, label: n.label, degree: n.relatedNodes.length })),
    };
  }

  /**
   * Detect communities in the graph
   */
  detectCommunities(): Community[] {
    const communities: Community[] = [];
    const visited = new Set<string>();

    this.nodes.forEach((node) => {
      if (!visited.has(node.id)) {
        const community = this.extractCommunity(node.id, visited);
        if (community.members.length > 1) {
          communities.push(community);
        }
      }
    });

    return communities;
  }

  /**
   * Extract community around a node
   */
  private extractCommunity(startId: string, visited: Set<string>): Community {
    const members: string[] = [];
    const queue = [startId];
    const distances = new Map<string, number>();
    distances.set(startId, 0);

    while (queue.length > 0) {
      const nodeId = queue.shift()!;
      if (visited.has(nodeId)) continue;

      visited.add(nodeId);
      members.push(nodeId);

      // Find neighbors with high connection strength
      const edges = Array.from(this.edges.values()).filter(
        (e) =>
          (e.fromId === nodeId || e.toId === nodeId) &&
          e.weight > 0.5 // Only follow strong edges
      );

      edges.forEach((edge) => {
        const nextId = edge.fromId === nodeId ? edge.toId : edge.fromId;
        if (!visited.has(nextId)) {
          const currentDist = distances.get(nodeId) || 0;
          const nextDist = distances.get(nextId) || Infinity;
          if (currentDist + 1 < nextDist) {
            distances.set(nextId, currentDist + 1);
            queue.push(nextId);
          }
        }
      });
    }

    return {
      id: `community_${startId}`,
      members,
      size: members.length,
      cohesion: this.computeCohesion(members),
    };
  }

  /**
   * Compute cohesion of a community
   */
  private computeCohesion(members: string[]): number {
    if (members.length < 2) return 1;

    let internalEdges = 0;
    let totalEdges = 0;

    members.forEach((memberId) => {
      const edges = Array.from(this.edges.values()).filter(
        (e) => e.fromId === memberId || e.toId === memberId
      );

      totalEdges += edges.length;
      internalEdges += edges.filter(
        (e) =>
          members.includes(e.fromId) &&
          members.includes(e.toId)
      ).length;
    });

    return totalEdges > 0 ? internalEdges / totalEdges : 0;
  }

  /**
   * Extract tags from symbol name
   */
  private extractTags(name: string, type: string): string[] {
    const tags = [type.toLowerCase()];

    // Add camelCase parts as tags
    const parts = name
      .replace(/([A-Z])/g, ' $1')
      .toLowerCase()
      .split(/\s+/)
      .filter((p) => p.length > 2);

    tags.push(...parts);

    return tags;
  }
}

export interface GraphStatistics {
  nodeCount: number;
  edgeCount: number;
  averageComplexity: number;
  typeDistribution: Record<string, number>;
  densestNodes: Array<{ id: string; label: string; degree: number }>;
}

export interface Community {
  id: string;
  members: string[];
  size: number;
  cohesion: number; // 0-1
}