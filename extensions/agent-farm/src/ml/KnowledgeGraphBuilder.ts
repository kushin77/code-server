/**
 * Phase 5: Knowledge Graph Integration
 * KnowledgeGraphBuilder - Build and query semantic knowledge graphs
 */

export interface KnowledgeGraphNode {
  id: string;
  type: 'file' | 'function' | 'class' | 'module' | 'interface' | 'type';
  label: string;
  filePath?: string;
  embedding?: number[]; // For semantic similarity
  metadata?: Record<string, unknown>;
  relatedNodes?: string[];
  importance?: number;
  tags?: string[];
}

export interface KnowledgeGraphEdge {
  fromId: string;
  toId: string;
  relation: string;
  weight?: number;
  metadata?: Record<string, unknown>;
}

export interface KnowledgeGraph {
  nodes: Map<string, KnowledgeGraphNode>;
  edges: Map<string, KnowledgeGraphEdge>;
  metadata: GraphMetadata;
}

export interface GraphMetadata {
  createdAt: Date;
  updatedAt: Date;
  codebaseMetrics: CodebaseMetrics;
  version: string;
}

export interface CodebaseMetrics {
  totalFiles: number;
  totalFunctions: number;
  totalClasses: number;
  averageDepth: number;
}

export interface ContextGraph {
  centerNode: KnowledgeGraphNode;
  neighbors: KnowledgeGraphNode[];
  edges: KnowledgeGraphEdge[];
  depth: number;
}

export interface GraphStatistics {
  nodeCount: number;
  edgeCount: number;
  typeDistribution: Record<string, number>;
  densestNodes: string[];
  averageConnectivity: number;
}

export interface Community {
  members: string[];
  size: number;
  cohesion: number;
}

export class KnowledgeGraphBuilder {
  private graph: KnowledgeGraph;

  constructor() {
    this.graph = {
      nodes: new Map(),
      edges: new Map(),
      metadata: {
        createdAt: new Date(),
        updatedAt: new Date(),
        codebaseMetrics: {
          totalFiles: 0,
          totalFunctions: 0,
          totalClasses: 0,
          averageDepth: 0,
        },
        version: '5.0',
      },
    };
  }

  /**
   * Add a node to the graph
   */
  addNode(node: KnowledgeGraphNode): void {
    this.graph.nodes.set(node.id, node);
    this.graph.metadata.updatedAt = new Date();
  }

  /**
   * Add an edge to the graph
   */
  addEdge(fromId: string, toId: string, relation: string, weight: number = 1): void {
    const edgeId = `${fromId}->${toId}`;
    this.graph.edges.set(edgeId, {
      fromId,
      toId,
      relation,
      weight,
    });
    this.graph.metadata.updatedAt = new Date();
  }

  /**
   * Query by relationship - find nodes by relation type and keyword
   */
  queryByRelationship(query: string, relation?: string, hops: number = 1): KnowledgeGraphNode[] {
    const results = new Set<KnowledgeGraphNode>();
    const visited = new Set<string>();

    // Find nodes matching keyword
    const startNodes = Array.from(this.graph.nodes.values()).filter(
      (n) => n.label.toLowerCase().includes(query.toLowerCase()) || 
              (n.tags?.some((t) => t.toLowerCase().includes(query.toLowerCase())))
    );

    // Traverse graph for specified hops
    for (const startNode of startNodes) {
      this.traverseRelationship(startNode.id, relation, hops, visited, results);
    }

    // Sort by importance
    return Array.from(results).sort((a, b) => (b.importance || 0) - (a.importance || 0));
  }

  /**
   * Find shortest path between two nodes
   */
  findShortestPath(fromId: string, toId: string): string[] {
    const queue: string[][] = [[fromId]];
    const visited = new Set<string>([fromId]);

    while (queue.length > 0) {
      const path = queue.shift()!;
      const currentId = path[path.length - 1];

      if (currentId === toId) {
        return path;
      }

      // Find neighbors
      for (const edge of this.graph.edges.values()) {
        if (edge.fromId === currentId && !visited.has(edge.toId)) {
          visited.add(edge.toId);
          queue.push([...path, edge.toId]);
        }
      }
    }

    return []; // No path found
  }

  /**
   * Get context around a node
   */
  getNodeContext(nodeId: string, depth: number = 1): ContextGraph {
    const centerNode = this.graph.nodes.get(nodeId);
    if (!centerNode) {
      throw new Error(`Node ${nodeId} not found`);
    }

    const neighbors = new Set<KnowledgeGraphNode>();
    const contextEdges: KnowledgeGraphEdge[] = [];
    const visited = new Set<string>([nodeId]);

    const traverse = (currentId: string, currentDepth: number): void => {
      if (currentDepth === 0) return;

      for (const edge of this.graph.edges.values()) {
        if (edge.fromId === currentId && !visited.has(edge.toId)) {
          visited.add(edge.toId);
          const neighbor = this.graph.nodes.get(edge.toId);
          if (neighbor) {
            neighbors.add(neighbor);
            contextEdges.push(edge);
            traverse(edge.toId, currentDepth - 1);
          }
        } else if (edge.toId === currentId && !visited.has(edge.fromId)) {
          visited.add(edge.fromId);
          const neighbor = this.graph.nodes.get(edge.fromId);
          if (neighbor) {
            neighbors.add(neighbor);
            contextEdges.push(edge);
            traverse(edge.fromId, currentDepth - 1);
          }
        }
      }
    };

    traverse(nodeId, depth);

    return {
      centerNode,
      neighbors: Array.from(neighbors),
      edges: contextEdges,
      depth,
    };
  }

  /**
   * Build graph from dependency graph
   */
  buildFromDependencyGraph(depGraph: any): void {
    // Add nodes from dependency graph
    for (const [nodeId, node] of depGraph.nodes) {
      const kgNode: KnowledgeGraphNode = {
        id: nodeId,
        type: node.type || 'file',
        label: node.name,
        filePath: node.filePath,
        importance: this.computeImportance(nodeId, depGraph),
        tags: this.extractTags(node.name),
      };
      this.addNode(kgNode);
    }

    // Add edges from dependency graph
    for (const edge of depGraph.edges.values()) {
      this.addEdge(edge.from, edge.to, edge.type, this.computeWeight(edge));
    }
  }

  /**
   * Search for nodes by keyword
   */
  search(keyword: string, limit: number = 10): KnowledgeGraphNode[] {
    return Array.from(this.graph.nodes.values())
      .filter(
        (n) => n.label.toLowerCase().includes(keyword.toLowerCase()) ||
               (n.tags?.some((t) => t.toLowerCase().includes(keyword.toLowerCase())))
      )
      .sort((a, b) => (b.importance || 0) - (a.importance || 0))
      .slice(0, limit);
  }

  /**
   * Get graph statistics
   */
  getStatistics(): GraphStatistics {
    const typeDistribution: Record<string, number> = {};
    const connectivity: number[] = [];

    for (const node of this.graph.nodes.values()) {
      typeDistribution[node.type] = (typeDistribution[node.type] || 0) + 1;
      const connections = Array.from(this.graph.edges.values())
        .filter((e) => e.fromId === node.id || e.toId === node.id)
        .length;
      connectivity.push(connections);
    }

    const avgConnectivity = connectivity.length > 0 ? 
      connectivity.reduce((a, b) => a + b, 0) / connectivity.length : 0;

    // Find densest nodes
    const nodeConnectivity = new Map<string, number>();
    for (const node of this.graph.nodes.values()) {
      const connections = Array.from(this.graph.edges.values())
        .filter((e) => e.fromId === node.id || e.toId === node.id)
        .length;
      nodeConnectivity.set(node.id, connections);
    }

    const densestNodes = Array.from(nodeConnectivity.entries())
      .sort((a, b) => b[1] - a[1])
      .slice(0, 5)
      .map(([id]) => this.graph.nodes.get(id)?.label || id);

    return {
      nodeCount: this.graph.nodes.size,
      edgeCount: this.graph.edges.size,
      typeDistribution,
      densestNodes,
      averageConnectivity: avgConnectivity,
    };
  }

  /**
   * Detect communities in the graph
   */
  detectCommunities(): Community[] {
    const communities: Community[] = [];
    const visited = new Set<string>();

    for (const nodeId of this.graph.nodes.keys()) {
      if (!visited.has(nodeId)) {
        const community = this.extractCommunity(nodeId, visited);
        if (community.members.length > 0) {
          communities.push({
            members: community.members,
            size: community.members.length,
            cohesion: this.computeCohesion(community.members),
          });
        }
      }
    }

    return communities;
  }

  /**
   * Get the current graph
   */
  getGraph(): KnowledgeGraph {
    return this.graph;
  }

  // Private helper methods

  private traverseRelationship(
    nodeId: string,
    relation: string | undefined,
    hops: number,
    visited: Set<string>,
    results: Set<KnowledgeGraphNode>
  ): void {
    if (hops === 0 || visited.has(nodeId)) return;
    visited.add(nodeId);

    const node = this.graph.nodes.get(nodeId);
    if (node) results.add(node);

    for (const edge of this.graph.edges.values()) {
      if (edge.fromId === nodeId && (!relation || edge.relation === relation)) {
        this.traverseRelationship(edge.toId, relation, hops - 1, visited, results);
      }
    }
  }

  private computeImportance(nodeId: string, depGraph: any): number {
    const inDegree = Array.from(depGraph.edges.values())
      .filter((e: any) => e.to === nodeId)
      .length;
    const outDegree = Array.from(depGraph.edges.values())
      .filter((e: any) => e.from === nodeId)
      .length;

    return Math.min((inDegree + outDegree) / (depGraph.nodes.size || 1), 1);
  }

  private computeWeight(edge: any): number {
    const strengthMap: Record<string, number> = {
      import: 0.9,
      inherit: 0.95,
      implement: 0.85,
      call: 0.7,
      reference: 0.5,
    };
    return strengthMap[edge.type] || 0.5;
  }

  private extractTags(label: string): string[] {
    // Extract meaningful tags from label
    return label.split(/[._-]/).filter((t) => t.length > 2);
  }

  private extractCommunity(startId: string, globalVisited: Set<string>): { members: string[] } {
    const community: string[] = [];
    const queue = [startId];
    const visited = new Set<string>();

    while (queue.length > 0) {
      const nodeId = queue.shift()!;
      if (visited.has(nodeId) || globalVisited.has(nodeId)) continue;

      visited.add(nodeId);
      community.push(nodeId);
      globalVisited.add(nodeId);

      // Find connected nodes
      for (const edge of this.graph.edges.values()) {
        if ((edge.fromId === nodeId || edge.toId === nodeId) &&
            !visited.has(edge.fromId === nodeId ? edge.toId : edge.fromId)) {
          queue.push(edge.fromId === nodeId ? edge.toId : edge.fromId);
        }
      }
    }

    return { members: community };
  }

  private computeCohesion(members: string[]): number {
    const memberSet = new Set(members);
    let internalEdges = 0;
    let externalEdges = 0;

    for (const edge of this.graph.edges.values()) {
      const fromInternal = memberSet.has(edge.fromId);
      const toInternal = memberSet.has(edge.toId);

      if (fromInternal && toInternal) {
        internalEdges++;
      } else if (fromInternal || toInternal) {
        externalEdges++;
      }
    }

    const totalEdges = internalEdges + externalEdges;
    return totalEdges > 0 ? internalEdges / totalEdges : 0;
  }
}

export default KnowledgeGraphBuilder;
