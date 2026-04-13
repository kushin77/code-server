/**
 * Phase 5: Knowledge Graph Integration
 * CodeDependencyExtractor - Extract and analyze code dependencies
 */

export interface CodeDependency {
  from: string;
  to: string;
  type: 'import' | 'inherit' | 'implement' | 'call' | 'reference';
  strength: number; // 0-1, confidence in the dependency
}

export interface DependencyNode {
  id: string;
  name: string;
  type: 'file' | 'class' | 'function' | 'interface';
  filePath?: string;
  metrics?: DependencyNodeMetrics;
}

export interface DependencyNodeMetrics {
  inDegree: number;
  outDegree: number;
  cyclicDepth?: number;
  isOrphaned: boolean;
}

export interface DependencyGraph {
  nodes: Map<string, DependencyNode>;
  edges: Map<string, CodeDependency>;
  metrics: ComplexityReport;
}

export interface CyclicDependency {
  nodes: string[];
  severity: 'low' | 'medium' | 'high';
  depth: number;
}

export interface NodeMetrics {
  inDegree: number;
  outDegree: number;
  orphaned: boolean;
  cyclicDepth: number;
}

export interface ComplexityReport {
  totalNodes: number;
  totalEdges: number;
  averageDependencyDepth: number;
  cyclesDetected: number;
  orphanedNodes: string[];
  highComplexityNodes: string[];
}

export class CodeDependencyExtractor {
  /**
   * Extract all dependencies from source code
   */
  async extractDependencies(code: string, filePath: string): Promise<CodeDependency[]> {
    const dependencies: CodeDependency[] = [];

    // Extract imports
    dependencies.push(...this.extractImports(code, filePath));

    // Extract inheritance
    dependencies.push(...this.extractInheritance(code, filePath));

    // Extract function calls
    dependencies.push(...this.extractCalls(code, filePath));

    // Extract references
    dependencies.push(...this.extractReferences(code, filePath));

    return dependencies;
  }

  /**
   * Build complete dependency graph
   */
  buildDependencyGraph(
    files: Array<{ path: string; content: string }>
  ): DependencyGraph {
    const nodes = new Map<string, DependencyNode>();
    const edges = new Map<string, CodeDependency>();

    // First pass: create nodes
    for (const file of files) {
      const nodeId = file.path;
      nodes.set(nodeId, {
        id: nodeId,
        name: file.path.split('/').pop() || file.path,
        type: 'file',
        filePath: file.path,
      });
    }

    // Second pass: extract edges
    for (const file of files) {
      const deps = this.extractDependenciesSync(file.content, file.path);
      for (const dep of deps) {
        const edgeId = `${dep.from}->${dep.to}`;
        edges.set(edgeId, dep);
      }
    }

    // Compute metrics
    const metrics = this.computeComplexityMetrics({ nodes, edges, metrics: {} as ComplexityReport });

    return { nodes, edges, metrics };
  }

  /**
   * Detect cyclic dependencies
   */
  analyzeCyclicDependencies(graph: DependencyGraph): CyclicDependency[] {
    const cycles: CyclicDependency[] = [];
    const visited = new Set<string>();
    const recursionStack = new Set<string>();

    for (const node of graph.nodes.keys()) {
      if (!visited.has(node)) {
        this.dfs(node, graph, visited, recursionStack, [], cycles);
      }
    }

    return cycles;
  }

  /**
   * Compute complexity metrics
   */
  computeComplexityMetrics(graph: DependencyGraph): ComplexityReport {
    const inDegree = new Map<string, number>();
    const outDegree = new Map<string, number>();

    // Initialize degrees
    for (const nodeId of graph.nodes.keys()) {
      inDegree.set(nodeId, 0);
      outDegree.set(nodeId, 0);
    }

    // Count edges
    for (const edge of graph.edges.values()) {
      outDegree.set(edge.from, (outDegree.get(edge.from) || 0) + 1);
      inDegree.set(edge.to, (inDegree.get(edge.to) || 0) + 1);
    }

    // Find orphaned nodes
    const orphanedNodes: string[] = [];
    const highComplexityNodes: string[] = [];

    for (const [nodeId, node] of graph.nodes) {
      const in_deg = inDegree.get(nodeId) || 0;
      const out_deg = outDegree.get(nodeId) || 0;

      if (in_deg === 0 && out_deg === 0) {
        orphanedNodes.push(node.name);
      }

      if (in_deg + out_deg > 10) {
        highComplexityNodes.push(node.name);
      }

      // Update node metrics
      if (node.metrics) {
        node.metrics.inDegree = in_deg;
        node.metrics.outDegree = out_deg;
        node.metrics.isOrphaned = in_deg === 0 && out_deg === 0;
      }
    }

    const cycles = this.analyzeCyclicDependencies(graph);
    const totalDepth = Array.from(graph.nodes.keys()).reduce((sum, nodeId) => {
      return sum + this.computeNodeDepth(nodeId, graph);
    }, 0);

    return {
      totalNodes: graph.nodes.size,
      totalEdges: graph.edges.size,
      averageDependencyDepth: graph.nodes.size > 0 ? totalDepth / graph.nodes.size : 0,
      cyclesDetected: cycles.length,
      orphanedNodes,
      highComplexityNodes,
    };
  }

  // Private extraction methods

  private extractImports(code: string, filePath: string): CodeDependency[] {
    const imports: CodeDependency[] = [];

    // ES6 imports: import X from 'module'
    const es6Pattern = /import\s+(?:{[^}]*}|[\w$]+)\s+from\s+['"]([^'"]+)['"]/g;
    let match;
    while ((match = es6Pattern.exec(code)) !== null) {
      imports.push({
        from: filePath,
        to: match[1],
        type: 'import',
        strength: 0.9,
      });
    }

    // CommonJS requires: const X = require('module')
    const requirePattern = /require\s*\(\s*['"]([^'"]+)['"]\s*\)/g;
    while ((match = requirePattern.exec(code)) !== null) {
      imports.push({
        from: filePath,
        to: match[1],
        type: 'import',
        strength: 0.85,
      });
    }

    return imports;
  }

  private extractInheritance(code: string, filePath: string): CodeDependency[] {
    const inheritance: CodeDependency[] = [];

    // Class extends: class Child extends Parent
    const extendsPattern = /class\s+\w+\s+extends\s+(\w+)/g;
    let match;
    while ((match = extendsPattern.exec(code)) !== null) {
      inheritance.push({
        from: filePath,
        to: match[1],
        type: 'inherit',
        strength: 0.95,
      });
    }

    // Interface extends: interface Child extends Parent
    const ifacePattern = /interface\s+\w+\s+extends\s+(\w+)/g;
    while ((match = ifacePattern.exec(code)) !== null) {
      inheritance.push({
        from: filePath,
        to: match[1],
        type: 'inherit',
        strength: 0.85,
      });
    }

    // Implements: class X implements Interface
    const implPattern = /class\s+\w+(?:\s+extends\s+\w+)?\s+implements\s+([^{]+)/g;
    while ((match = implPattern.exec(code)) !== null) {
      const interfaces = match[1].split(',').map((i) => i.trim());
      for (const iface of interfaces) {
        inheritance.push({
          from: filePath,
          to: iface,
          type: 'implement',
          strength: 0.85,
        });
      }
    }

    return inheritance;
  }

  private extractCalls(code: string, filePath: string): CodeDependency[] {
    const calls: CodeDependency[] = [];

    // Function calls: methodName() or Class.methodName()
    const callPattern = /([A-Z]\w+)\.(\w+)\s*\(/g;
    let match;
    while ((match = callPattern.exec(code)) !== null) {
      calls.push({
        from: filePath,
        to: `${match[1]}.${match[2]}`,
        type: 'call',
        strength: 0.7,
      });
    }

    return calls;
  }

  private extractReferences(code: string, filePath: string): CodeDependency[] {
    const references: CodeDependency[] = [];

    // Type references: : ClassName
    const typePattern = /:\s+(\w+)(?:\[|\s|;|,|\))/g;
    let match;
    while ((match = typePattern.exec(code)) !== null) {
      references.push({
        from: filePath,
        to: match[1],
        type: 'reference',
        strength: 0.5,
      });
    }

    return references;
  }

  private extractDependenciesSync(code: string, filePath: string): CodeDependency[] {
    const dependencies: CodeDependency[] = [];
    dependencies.push(...this.extractImports(code, filePath));
    dependencies.push(...this.extractInheritance(code, filePath));
    dependencies.push(...this.extractCalls(code, filePath));
    dependencies.push(...this.extractReferences(code, filePath));
    return dependencies;
  }

  private dfs(
    node: string,
    graph: DependencyGraph,
    visited: Set<string>,
    recursionStack: Set<string>,
    currentPath: string[],
    cycles: CyclicDependency[]
  ): void {
    visited.add(node);
    recursionStack.add(node);
    currentPath.push(node);

    // Find all outgoing edges from this node
    for (const edge of graph.edges.values()) {
      if (edge.from === node) {
        const neighbor = edge.to;

        if (!visited.has(neighbor)) {
          this.dfs(neighbor, graph, visited, recursionStack, currentPath, cycles);
        } else if (recursionStack.has(neighbor)) {
          // Found a cycle
          const cycleStartIndex = currentPath.indexOf(neighbor);
          const cycleNodes = currentPath.slice(cycleStartIndex);
          cycleNodes.push(neighbor); // Complete the cycle

          cycles.push({
            nodes: cycleNodes,
            severity: cycleNodes.length > 5 ? 'high' : cycleNodes.length > 3 ? 'medium' : 'low',
            depth: cycleNodes.length,
          });
        }
      }
    }

    currentPath.pop();
    recursionStack.delete(node);
  }

  private computeNodeDepth(nodeId: string, graph: DependencyGraph): number {
    const visited = new Set<string>();
    let maxDepth = 0;

    const traverse = (currentNode: string, depth: number): void => {
      if (visited.has(currentNode)) return;
      visited.add(currentNode);
      maxDepth = Math.max(maxDepth, depth);

      for (const edge of graph.edges.values()) {
        if (edge.from === currentNode) {
          traverse(edge.to, depth + 1);
        }
      }
    };

    traverse(nodeId, 0);
    return maxDepth;
  }
}

export default CodeDependencyExtractor;
