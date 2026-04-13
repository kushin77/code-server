"use strict";
/**
 * Phase 5: Knowledge Graph Integration
 * CodeDependencyExtractor - Identify and extract code dependencies
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.CodeDependencyExtractor = void 0;
/**
 * Extract and analyze code dependencies
 */
class CodeDependencyExtractor {
    constructor() {
        this.nodeCounter = 0;
        this.nodeMap = new Map();
        this.edges = new Map();
    }
    /**
     * Extract all dependencies from code
     */
    extractDependencies(code, filePath) {
        const dependencies = [];
        // Extract imports/requires
        const importDeps = this.extractImportDependencies(code, filePath);
        dependencies.push(...importDeps);
        // Extract class/interface inheritance
        const inheritanceDeps = this.extractInheritanceDependencies(code, filePath);
        dependencies.push(...inheritanceDeps);
        // Extract function calls
        const callDeps = this.extractCallDependencies(code, filePath);
        dependencies.push(...callDeps);
        // Extract references
        const refDeps = this.extractReferenceDependencies(code, filePath);
        dependencies.push(...refDeps);
        return dependencies;
    }
    /**
     * Build complete dependency graph from multiple files
     */
    buildDependencyGraph(files) {
        const nodes = new Map();
        const edges = new Map();
        // Extract all dependencies
        files.forEach((file) => {
            const fileDeps = this.extractDependencies(file.content, file.path);
            fileDeps.forEach((dep) => {
                const edgeId = `${dep.from.file}:${dep.from.symbol}->${dep.to.file}:${dep.to.symbol}`;
                edges.set(edgeId, dep);
            });
        });
        // Build nodes from dependencies
        edges.forEach((dep) => {
            this.ensureNode(nodes, dep.from.file, dep.from.symbol, 'function');
            this.ensureNode(nodes, dep.to.file, dep.to.symbol, 'function');
        });
        // Compute metrics
        const metrics = this.computeMetrics(nodes, edges);
        return { nodes, edges, metrics };
    }
    /**
     * Analyze cyclic dependencies
     */
    analyzeCyclicDependencies(graph) {
        const cycles = [];
        const visited = new Set();
        const recursionStack = new Set();
        graph.nodes.forEach((node) => {
            if (!visited.has(node.id)) {
                this.detectCycles(node.id, graph, visited, recursionStack, [], cycles);
            }
        });
        return cycles;
    }
    /**
     * Compute complexity metrics
     */
    computeComplexityMetrics(graph) {
        const report = {
            totalNodes: graph.nodes.size,
            totalEdges: graph.edges.size,
            averageInDegree: Array.from(graph.nodes.values()).reduce((sum, n) => sum + n.metrics.inDegree, 0) /
                graph.nodes.size || 0,
            averageOutDegree: Array.from(graph.nodes.values()).reduce((sum, n) => sum + n.metrics.outDegree, 0) /
                graph.nodes.size || 0,
            cyclicCount: graph.metrics.cyclicDependencies.length,
            orphanedCount: graph.metrics.orphanedNodes.length,
            highestComplexityNode: this.findHighestComplexityNode(graph),
            complexityDistribution: this.computeComplexityDistribution(graph),
        };
        return report;
    }
    /**
     * Extract import/require dependencies
     */
    extractImportDependencies(code, filePath) {
        const deps = [];
        // ES6 imports
        const importRegex = /import\s+(?:{[^}]*}|[^from]+)?from\s+['"]([^'"]+)['"]/g;
        let match;
        while ((match = importRegex.exec(code)) !== null) {
            const importedPath = match[1];
            const line = code.substring(0, match.index).split('\n').length;
            deps.push({
                from: { file: filePath, symbol: 'module', line },
                to: { file: importedPath, symbol: 'module', type: 'import' },
                strength: 0.9,
                frequency: 1,
                bidirectional: false,
            });
        }
        // CommonJS requires
        const requireRegex = /require\(['"]([^'"]+)['"]\)/g;
        while ((match = requireRegex.exec(code)) !== null) {
            const requiredPath = match[1];
            const line = code.substring(0, match.index).split('\n').length;
            deps.push({
                from: { file: filePath, symbol: 'module', line },
                to: { file: requiredPath, symbol: 'module', type: 'import' },
                strength: 0.85,
                frequency: 1,
                bidirectional: false,
            });
        }
        return deps;
    }
    /**
     * Extract inheritance/implementation dependencies
     */
    extractInheritanceDependencies(code, filePath) {
        const deps = [];
        // Class extends
        const extendsRegex = /class\s+(\w+)\s+extends\s+(\w+)/g;
        let match;
        while ((match = extendsRegex.exec(code)) !== null) {
            const childClass = match[1];
            const parentClass = match[2];
            const line = code.substring(0, match.index).split('\n').length;
            deps.push({
                from: { file: filePath, symbol: childClass, line },
                to: { file: filePath, symbol: parentClass, type: 'extends' },
                strength: 0.95,
                frequency: 1,
                bidirectional: false,
            });
        }
        // Interface extends
        const interfaceExtendsRegex = /interface\s+(\w+)\s+extends\s+([^{]+)/g;
        while ((match = interfaceExtendsRegex.exec(code)) !== null) {
            const childInterface = match[1];
            const parentInterfaces = match[2].split(',').map((i) => i.trim());
            const line = code.substring(0, match.index).split('\n').length;
            parentInterfaces.forEach((parentInt) => {
                deps.push({
                    from: { file: filePath, symbol: childInterface, line },
                    to: { file: filePath, symbol: parentInt, type: 'extends' },
                    strength: 0.9,
                    frequency: 1,
                    bidirectional: false,
                });
            });
        }
        // Class implements
        const implementsRegex = /class\s+(\w+)\s+.*implements\s+([^{]+)/g;
        while ((match = implementsRegex.exec(code)) !== null) {
            const className = match[1];
            const interfaces = match[2].split(',').map((i) => i.trim());
            const line = code.substring(0, match.index).split('\n').length;
            interfaces.forEach((iface) => {
                deps.push({
                    from: { file: filePath, symbol: className, line },
                    to: { file: filePath, symbol: iface, type: 'implements' },
                    strength: 0.85,
                    frequency: 1,
                    bidirectional: false,
                });
            });
        }
        return deps;
    }
    /**
     * Extract function/method call dependencies
     */
    extractCallDependencies(code, filePath) {
        const deps = [];
        // Function definitions
        const functionRegex = /function\s+(\w+)|const\s+(\w+)\s*=|(?:^|\s)(\w+)\s*\(/gm;
        const functions = new Set();
        let match;
        const funcRegex = /(?:function|const)\s+(\w+)/g;
        while ((match = funcRegex.exec(code)) !== null) {
            functions.add(match[1]);
        }
        // Function calls within code
        const callRegex = /\b([a-zA-Z_]\w*)\s*\(/g;
        let lineNum = 0;
        code.split('\n').forEach((line) => {
            lineNum++;
            const callMatches = Array.from(line.matchAll(callRegex));
            callMatches.forEach((callMatch) => {
                const functionName = callMatch[1];
                if (functions.has(functionName)) {
                    deps.push({
                        from: { file: filePath, symbol: 'unknown', line: lineNum },
                        to: { file: filePath, symbol: functionName, type: 'calls' },
                        strength: 0.7,
                        frequency: 1,
                        bidirectional: false,
                    });
                }
            });
        });
        return deps;
    }
    /**
     * Extract symbol references
     */
    extractReferenceDependencies(code, filePath) {
        const deps = [];
        // Variable/constant references
        const symbolRegex = /const\s+(\w+)|let\s+(\w+)|var\s+(\w+)/g;
        const symbols = new Set();
        let match;
        while ((match = symbolRegex.exec(code)) !== null) {
            const symbol = match[1] || match[2] || match[3];
            if (symbol)
                symbols.add(symbol);
        }
        // Reference occurrences
        symbols.forEach((symbol) => {
            const refRegex = new RegExp(`\\b${symbol}\\b`, 'g');
            const matches = Array.from(code.matchAll(refRegex));
            let lineNum = 0;
            code.split('\n').forEach((line, idx) => {
                if (refRegex.test(line)) {
                    lineNum = idx + 1;
                    deps.push({
                        from: { file: filePath, symbol: 'unknown', line: lineNum },
                        to: { file: filePath, symbol, type: 'references' },
                        strength: 0.5,
                        frequency: matches.length,
                        bidirectional: false,
                    });
                }
            });
        });
        return deps;
    }
    /**
     * Ensure a node exists in the graph
     */
    ensureNode(nodes, filePath, symbol, type) {
        const nodeId = `${filePath}:${symbol}`;
        if (!nodes.has(nodeId)) {
            nodes.set(nodeId, {
                id: nodeId,
                type,
                name: symbol,
                filePath,
                line: 0,
                dependencies: [],
                dependents: [],
                metrics: { inDegree: 0, outDegree: 0, cyclicDepth: 0, reachableNodes: 0, affectingNodes: 0 },
            });
        }
    }
    /**
     * Detect cycles using DFS
     */
    detectCycles(nodeId, graph, visited, recursionStack, path, cycles) {
        visited.add(nodeId);
        recursionStack.add(nodeId);
        path.push(nodeId);
        const node = graph.nodes.get(nodeId);
        if (node) {
            node.dependencies.forEach((depId) => {
                if (!visited.has(depId)) {
                    this.detectCycles(depId, graph, visited, recursionStack, [...path], cycles);
                }
                else if (recursionStack.has(depId)) {
                    const cycleStart = path.indexOf(depId);
                    const cycle = path.slice(cycleStart);
                    cycle.push(depId); // close the cycle
                    cycles.push({
                        nodes: cycle,
                        length: cycle.length,
                        severity: cycle.length > 4 ? 'high' : cycle.length > 2 ? 'medium' : 'low',
                    });
                }
            });
        }
        recursionStack.delete(nodeId);
    }
    /**
     * Find node with highest complexity
     */
    findHighestComplexityNode(graph) {
        let maxComplexity = 0;
        let maxNode = '';
        graph.nodes.forEach((node) => {
            const complexity = node.metrics.inDegree + node.metrics.outDegree;
            if (complexity > maxComplexity) {
                maxComplexity = complexity;
                maxNode = node.id;
            }
        });
        return maxNode;
    }
    /**
     * Compute complexity distribution
     */
    computeComplexityDistribution(graph) {
        const distribution = {
            low: 0,
            medium: 0,
            high: 0,
            critical: 0,
        };
        graph.nodes.forEach((node) => {
            const complexity = node.metrics.inDegree + node.metrics.outDegree;
            if (complexity < 3)
                distribution.low++;
            else if (complexity < 8)
                distribution.medium++;
            else if (complexity < 15)
                distribution.high++;
            else
                distribution.critical++;
        });
        return distribution;
    }
    /**
     * Compute graph metrics
     */
    computeMetrics(nodes, edges) {
        const cyclicDependencies = [];
        const orphanedNodes = [];
        const highComplexityNodes = [];
        // Build adjacency data
        nodes.forEach((node) => {
            node.dependents = [];
            node.dependencies = [];
        });
        edges.forEach((edge) => {
            const fromNode = nodes.get(`${edge.from.file}:${edge.from.symbol}`);
            const toNode = nodes.get(`${edge.to.file}:${edge.to.symbol}`);
            if (fromNode && toNode) {
                fromNode.dependencies.push(toNode.id);
                toNode.dependents.push(fromNode.id);
                fromNode.metrics.outDegree++;
                toNode.metrics.inDegree++;
            }
        });
        // Identify special nodes
        nodes.forEach((node) => {
            if (node.metrics.inDegree === 0 && node.metrics.outDegree === 0) {
                orphanedNodes.push(node.id);
            }
            if (node.metrics.inDegree + node.metrics.outDegree > 10) {
                highComplexityNodes.push(node.id);
            }
        });
        return {
            totalDependencies: edges.size,
            totalDependents: nodes.size,
            cyclicDependencies,
            orphanedNodes,
            highComplexityNodes,
            averageDepth: this.computeAverageDepth(nodes),
        };
    }
    /**
     * Compute average dependency depth
     */
    computeAverageDepth(nodes) {
        let totalDepth = 0;
        let count = 0;
        nodes.forEach((node) => {
            const depth = this.computeNodeDepth(node, new Set());
            totalDepth += depth;
            count++;
        });
        return count > 0 ? totalDepth / count : 0;
    }
    /**
     * Compute depth of a node in dependency tree
     */
    computeNodeDepth(node, visited) {
        if (visited.has(node.id))
            return 0;
        if (node.dependencies.length === 0)
            return 1;
        visited.add(node.id);
        const childDepths = node.dependencies.map((depId) => 1); // simplified
        return 1 + (childDepths.length > 0 ? Math.max(...childDepths) : 0);
    }
}
exports.CodeDependencyExtractor = CodeDependencyExtractor;
//# sourceMappingURL=CodeDependencyExtractor.js.map