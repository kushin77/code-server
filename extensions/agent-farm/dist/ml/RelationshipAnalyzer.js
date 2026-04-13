"use strict";
/**
 * Phase 5: Knowledge Graph Integration
 * RelationshipAnalyzer - Analyze code relationships and patterns
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.RelationshipAnalyzer = void 0;
/**
 * Analyze code relationships and design patterns
 */
class RelationshipAnalyzer {
    /**
     * Analyze class inheritance hierarchy
     */
    analyzeInheritanceHierarchy(classes) {
        const childMap = new Map();
        const parentMap = new Map();
        const rootClasses = [];
        classes.forEach((cls) => {
            if (cls.extends) {
                parentMap.set(cls.name, cls.extends);
                if (!childMap.has(cls.extends)) {
                    childMap.set(cls.extends, []);
                }
                childMap.get(cls.extends).push(cls.name);
            }
            else {
                rootClasses.push(cls.name);
            }
        });
        const depth = this.calculateHierarchyDepth(rootClasses, childMap);
        return { rootClasses, childMap, parentMap, depth };
    }
    /**
     * Find composition patterns in code
     */
    findCompositionPatterns(code) {
        const patterns = [];
        // Parse class declarations with properties
        const classRegex = /class\s+(\w+)\s*{([^}]*?)}/gs;
        const propertyRegex = /(?:private|protected|public)?\s*(\w+):\s*(\w+)(?:\[\])?/g;
        let classMatch;
        while ((classMatch = classRegex.exec(code)) !== null) {
            const className = classMatch[1];
            const classBody = classMatch[2];
            let propMatch;
            while ((propMatch = propertyRegex.exec(classBody)) !== null) {
                patterns.push({
                    composerClass: className,
                    composedClass: propMatch[2],
                    propertyName: propMatch[1],
                    cardinality: classBody.includes(`${propMatch[1]}[]`) ? 'many' : 'one',
                    file: 'unknown',
                    line: 0,
                });
            }
        }
        return patterns;
    }
    /**
     * Detect dependency injection patterns
     */
    detectDependencyInjection() {
        const patterns = [];
        // TODO: Implement full DI pattern detection
        return patterns;
    }
    /**
     * Analyze function call graphs
     */
    analyzeCallGraphs(functions) {
        const nodes = new Map();
        const edges = new Map();
        const cycles = [];
        // Build nodes
        functions.forEach((func) => {
            nodes.set(func.name, {
                id: func.name,
                name: func.name,
                file: func.file,
                line: func.line,
                params: [],
                returns: 'unknown',
                calls: func.calls,
                calledBy: [],
            });
        });
        // Build edges and calledBy relationships
        functions.forEach((func) => {
            func.calls.forEach((callee) => {
                const edgeId = `${func.name}->${callee}`;
                edges.set(edgeId, {
                    from: func.name,
                    to: callee,
                    count: 1,
                    lines: [func.line],
                });
                if (nodes.has(callee)) {
                    nodes.get(callee).calledBy.push(func.name);
                }
            });
        });
        // Detect cycles
        const visited = new Set();
        nodes.forEach((node) => {
            if (!visited.has(node.id)) {
                const cycle = this.findCallCycle(node.id, node.calls, new Set(), [node.id], nodes);
                if (cycle) {
                    cycles.push(cycle);
                }
            }
        });
        return { nodes, edges, cycles };
    }
    /**
     * Identify common design patterns
     */
    identifyCommonPatterns(code) {
        const patterns = [];
        // Singleton pattern
        if (this.detectSingletonPattern(code)) {
            patterns.push({
                name: 'Singleton',
                type: 'Creational',
                confidence: 0.85,
                locations: [],
                description: 'Static instance with private constructor',
            });
        }
        // Factory pattern
        if (this.detectFactoryPattern(code)) {
            patterns.push({
                name: 'Factory',
                type: 'Creational',
                confidence: 0.80,
                locations: [],
                description: 'Static factory method for object creation',
            });
        }
        // Observer pattern
        if (this.detectObserverPattern(code)) {
            patterns.push({
                name: 'Observer',
                type: 'Behavioral',
                confidence: 0.75,
                locations: [],
                description: 'Event subscription and notification',
            });
        }
        // Strategy pattern
        if (this.detectStrategyPattern(code)) {
            patterns.push({
                name: 'Strategy',
                type: 'Behavioral',
                confidence: 0.70,
                locations: [],
                description: 'Interchangeable behavior implementations',
            });
        }
        // Dependency Injection pattern
        if (this.detectDIPattern(code)) {
            patterns.push({
                name: 'Dependency Injection',
                type: 'Structural',
                confidence: 0.80,
                locations: [],
                description: 'Constructor or property injection',
            });
        }
        return patterns;
    }
    // Private helper methods
    calculateHierarchyDepth(roots, childMap) {
        let maxDepth = 0;
        roots.forEach((root) => {
            const depth = this.getDepth(root, childMap);
            maxDepth = Math.max(maxDepth, depth);
        });
        return maxDepth;
    }
    getDepth(node, childMap) {
        const children = childMap.get(node) || [];
        if (children.length === 0)
            return 1;
        let maxChildDepth = 0;
        children.forEach((child) => {
            const childDepth = this.getDepth(child, childMap);
            maxChildDepth = Math.max(maxChildDepth, childDepth);
        });
        return 1 + maxChildDepth;
    }
    findCallCycle(start, callees, visited, path, nodes) {
        if (path.length > 1 && (callees.includes(start) || path.includes(callees[0]))) {
            const cycleStart = path.indexOf(callees[0]);
            if (cycleStart !== -1) {
                const cyclePath = path.slice(cycleStart);
                return {
                    functions: cyclePath,
                    length: cyclePath.length,
                    severity: cyclePath.length > 5 ? 'low' : cyclePath.length > 3 ? 'medium' : 'high',
                };
            }
        }
        visited.add(start);
        for (const callee of callees) {
            if (!visited.has(callee)) {
                const node = nodes.get(callee);
                if (node) {
                    const cycle = this.findCallCycle(callee, node.calls, visited, [...path, callee], nodes);
                    if (cycle)
                        return cycle;
                }
            }
        }
        return null;
    }
    detectSingletonPattern(code) {
        return /static\s+(?:readonly\s+)?(?:instance|INSTANCE)/.test(code) &&
            /private\s+constructor/.test(code);
    }
    detectFactoryPattern(code) {
        return /static\s+(?:create|build|of|from)\s*\(/.test(code) &&
            /return\s+new\s+\w+/.test(code);
    }
    detectObserverPattern(code) {
        return /subscribe|addEventListener|on\(|addEventListener/.test(code) &&
            /notify|emit|dispatch/.test(code);
    }
    detectStrategyPattern(code) {
        return /interface\s+\w*Strategy/.test(code) &&
            /execute|perform|handle|process/.test(code);
    }
    detectDIPattern(code) {
        return /constructor\s*\(.*:/.test(code) ||
            /inject\(|provide\(|Container/.test(code);
    }
}
exports.RelationshipAnalyzer = RelationshipAnalyzer;
//# sourceMappingURL=RelationshipAnalyzer.js.map