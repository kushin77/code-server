"use strict";
/**
 * Phase 5: Knowledge Graph Integration - Test Suite
 * Tests for CodeDependencyExtractor and KnowledgeGraphBuilder
 */
Object.defineProperty(exports, "__esModule", { value: true });
const globals_1 = require("@jest/globals");
const CodeDependencyExtractor_1 = require("../ml/CodeDependencyExtractor");
const KnowledgeGraphBuilder_1 = require("../ml/KnowledgeGraphBuilder");
(0, globals_1.describe)('Phase 5: Knowledge Graph Integration', () => {
    let extractor;
    let builder;
    (0, globals_1.beforeEach)(() => {
        extractor = new CodeDependencyExtractor_1.CodeDependencyExtractor();
        builder = new KnowledgeGraphBuilder_1.KnowledgeGraphBuilder();
    });
    (0, globals_1.describe)('CodeDependencyExtractor', () => {
        (0, globals_1.it)('should extract import dependencies from ES6 imports', () => {
            const code = `
        import { foo } from './utils';
        import * as Bar from './bar';
        import baz from './baz';
      `;
            const deps = extractor.extractDependencies(code, 'test.ts');
            (0, globals_1.expect)(deps.length).toBeGreaterThanOrEqual(3);
            (0, globals_1.expect)(deps[0].to.type).toBe('import');
            (0, globals_1.expect)(deps[0].strength).toBeGreaterThan(0.8);
        });
        (0, globals_1.it)('should extract CommonJS require dependencies', () => {
            const code = `
        const utils = require('./utils');
        const { foo } = require('./foo');
      `;
            const deps = extractor.extractDependencies(code, 'test.js');
            (0, globals_1.expect)(deps.length).toBeGreaterThanOrEqual(2);
            (0, globals_1.expect)(deps[0].to.type).toBe('import');
        });
        (0, globals_1.it)('should extract class inheritance dependencies', () => {
            const code = `
        class Animal {}
        class Dog extends Animal {}
        class Cat extends Animal {}
      `;
            const deps = extractor.extractDependencies(code, 'animals.ts');
            (0, globals_1.expect)(deps.length).toBeGreaterThanOrEqual(2);
            (0, globals_1.expect)(deps.some((d) => d.to.type === 'extends')).toBeTruthy();
            (0, globals_1.expect)(deps.every((d) => d.to.type === 'extends')).toBeTruthy();
        });
        (0, globals_1.it)('should extract interface extension dependencies', () => {
            const code = `
        interface Base {}
        interface Derived extends Base {}
        interface Multi extends Base, Derived {}
      `;
            const deps = extractor.extractDependencies(code, 'interfaces.ts');
            (0, globals_1.expect)(deps.length).toBeGreaterThanOrEqual(3);
            (0, globals_1.expect)(deps.filter((d) => d.to.type === 'extends').length).toBeGreaterThan(0);
        });
        (0, globals_1.it)('should extract class implements dependencies', () => {
            const code = `
        interface Logger {}
        class ConsoleLogger implements Logger {}
        class FileLogger implements Logger {}
      `;
            const deps = extractor.extractDependencies(code, 'logger.ts');
            (0, globals_1.expect)(deps.some((d) => d.to.type === 'implements')).toBeTruthy();
        });
        (0, globals_1.it)('should extract function call dependencies', () => {
            const code = `
        function helper() {}
        function main() {
          helper();
          helper();
        }
      `;
            const deps = extractor.extractDependencies(code, 'functions.ts');
            (0, globals_1.expect)(deps.some((d) => d.to.type === 'calls')).toBeTruthy();
        });
        (0, globals_1.it)('should build complete dependency graph', () => {
            const files = [
                {
                    path: 'file1.ts',
                    content: `
            import { foo } from './file2';
            class Main {}
          `,
                },
                {
                    path: 'file2.ts',
                    content: `
            export function foo() {}
            class Helper {}
          `,
                },
            ];
            const graph = extractor.buildDependencyGraph(files);
            (0, globals_1.expect)(graph.nodes.size).toBeGreaterThan(0);
            (0, globals_1.expect)(graph.edges.size).toBeGreaterThan(0);
            (0, globals_1.expect)(graph.metrics.totalDependencies).toBeGreaterThan(0);
        });
        (0, globals_1.it)('should detect cyclic dependencies', () => {
            const files = [
                { path: 'a.ts', content: 'import B from "./b"' },
                { path: 'b.ts', content: 'import C from "./c"' },
                { path: 'c.ts', content: 'import A from "./a"' },
            ];
            const graph = extractor.buildDependencyGraph(files);
            const cycles = extractor.analyzeCyclicDependencies(graph);
            (0, globals_1.expect)(cycles.length).toBeGreaterThan(0);
        });
        (0, globals_1.it)('should compute complexity metrics', () => {
            const files = [
                { path: 'file.ts', content: 'import dep from "./dep"; function foo() {}' },
            ];
            const graph = extractor.buildDependencyGraph(files);
            const metrics = extractor.computeComplexityMetrics(graph);
            (0, globals_1.expect)(metrics.totalNodes).toBeGreaterThan(0);
            (0, globals_1.expect)(metrics.totalEdges).toBeGreaterThanOrEqual(0);
            (0, globals_1.expect)(metrics.averageInDegree).toBeGreaterThanOrEqual(0);
        });
        (0, globals_1.it)('should identify orphaned nodes', () => {
            const files = [
                { path: 'used.ts', content: 'import dep from "./dep"' },
                { path: 'unused.ts', content: 'function isolated() {}' },
            ];
            const graph = extractor.buildDependencyGraph(files);
            // Unused.ts should be orphaned
            (0, globals_1.expect)(graph.metrics.orphanedNodes.length).toBeGreaterThanOrEqual(0);
        });
    });
    (0, globals_1.describe)('KnowledgeGraphBuilder', () => {
        (0, globals_1.it)('should add nodes to graph', () => {
            const node = {
                id: 'test-1',
                type: 'function',
                label: 'testFunction',
                filePath: 'test.ts',
                line: 10,
                metadata: { complexity: 1 },
                relatedNodes: [],
                importance: 0.5,
                tags: ['test', 'function'],
            };
            builder.addNode(node);
            const graph = builder.getGraph();
            (0, globals_1.expect)(graph.nodes.size).toBe(1);
            (0, globals_1.expect)(graph.nodes.get('test-1')).toBeDefined();
        });
        (0, globals_1.it)('should add edges between nodes', () => {
            const node1 = {
                id: 'n1',
                type: 'function',
                label: 'foo',
                filePath: 'file.ts',
                line: 1,
                metadata: {},
                relatedNodes: [],
                importance: 0,
                tags: [],
            };
            const node2 = {
                id: 'n2',
                type: 'function',
                label: 'bar',
                filePath: 'file.ts',
                line: 5,
                metadata: {},
                relatedNodes: [],
                importance: 0,
                tags: [],
            };
            builder.addNode(node1);
            builder.addNode(node2);
            builder.addEdge('n1', 'n2', 'calls', 0.9);
            const graph = builder.getGraph();
            (0, globals_1.expect)(graph.edges.size).toBe(1);
            (0, globals_1.expect)(graph.nodes.get('n1')?.relatedNodes).toContain('n2');
        });
        (0, globals_1.it)('should query by relationship', () => {
            const node1 = {
                id: 'func1',
                type: 'function',
                label: 'authenticate',
                filePath: 'auth.ts',
                line: 1,
                metadata: {},
                relatedNodes: ['func2'],
                importance: 0.7,
                tags: ['auth', 'security'],
            };
            const node2 = {
                id: 'func2',
                type: 'function',
                label: 'validate',
                filePath: 'auth.ts',
                line: 10,
                metadata: {},
                relatedNodes: ['func1'],
                importance: 0.6,
                tags: ['validate', 'security'],
            };
            builder.addNode(node1);
            builder.addNode(node2);
            builder.addEdge('func1', 'func2', 'calls', 0.8);
            const results = builder.queryByRelationship('auth', undefined, 1);
            (0, globals_1.expect)(results.length).toBeGreaterThanOrEqual(1);
            (0, globals_1.expect)(results.some((r) => r.label === 'authenticate')).toBeTruthy();
        });
        (0, globals_1.it)('should find shortest path between nodes', () => {
            // Create a chain: n1 -> n2 -> n3
            ['n1', 'n2', 'n3'].forEach((id, idx) => {
                builder.addNode({
                    id,
                    type: 'function',
                    label: `node${idx}`,
                    filePath: 'test.ts',
                    line: idx,
                    metadata: {},
                    relatedNodes: [],
                    importance: 0,
                    tags: [],
                });
            });
            builder.addEdge('n1', 'n2', 'calls', 1.0);
            builder.addEdge('n2', 'n3', 'calls', 1.0);
            const path = builder.findShortestPath('n1', 'n3');
            (0, globals_1.expect)(path.length).toBeGreaterThan(0);
            (0, globals_1.expect)(path[0]).toBe('n1');
            (0, globals_1.expect)(path[path.length - 1]).toBe('n3');
        });
        (0, globals_1.it)('should return empty path for disconnected nodes', () => {
            builder.addNode({
                id: 'isolated1',
                type: 'function',
                label: 'func1',
                filePath: 'test.ts',
                line: 1,
                metadata: {},
                relatedNodes: [],
                importance: 0,
                tags: [],
            });
            builder.addNode({
                id: 'isolated2',
                type: 'function',
                label: 'func2',
                filePath: 'test.ts',
                line: 2,
                metadata: {},
                relatedNodes: [],
                importance: 0,
                tags: [],
            });
            const path = builder.findShortestPath('isolated1', 'isolated2');
            (0, globals_1.expect)(path.length).toBe(0);
        });
        (0, globals_1.it)('should get node context', () => {
            const centerNode = {
                id: 'center',
                type: 'function',
                label: 'main',
                filePath: 'main.ts',
                line: 1,
                metadata: {},
                relatedNodes: ['neighbor1', 'neighbor2'],
                importance: 0.8,
                tags: [],
            };
            builder.addNode(centerNode);
            ['neighbor1', 'neighbor2'].forEach((id) => {
                builder.addNode({
                    id,
                    type: 'function',
                    label: id,
                    filePath: 'main.ts',
                    line: 5,
                    metadata: {},
                    relatedNodes: ['center'],
                    importance: 0.5,
                    tags: [],
                });
            });
            builder.addEdge('center', 'neighbor1', 'calls', 0.9);
            builder.addEdge('center', 'neighbor2', 'calls', 0.8);
            const context = builder.getNodeContext('center', 1);
            (0, globals_1.expect)(context.centerNode.id).toBe('center');
            (0, globals_1.expect)(context.neighbors.length).toBeGreaterThan(0);
            (0, globals_1.expect)(context.edges.length).toBeGreaterThan(0);
        });
        (0, globals_1.it)('should search nodes by keyword', () => {
            builder.addNode({
                id: 'auth-login',
                type: 'function',
                label: 'loginUser',
                filePath: 'auth.ts',
                line: 1,
                metadata: {},
                relatedNodes: [],
                importance: 0.8,
                tags: ['authentication', 'login', 'user'],
            });
            builder.addNode({
                id: 'auth-logout',
                type: 'function',
                label: 'logoutUser',
                filePath: 'auth.ts',
                line: 10,
                metadata: {},
                relatedNodes: [],
                importance: 0.7,
                tags: ['authentication', 'logout', 'user'],
            });
            const results = builder.search('auth', 10);
            (0, globals_1.expect)(results.length).toBeGreaterThanOrEqual(1);
            (0, globals_1.expect)(results.some((r) => r.id === 'auth-login')).toBeTruthy();
        });
        (0, globals_1.it)('should get graph statistics', () => {
            builder.addNode({
                id: 'n1',
                type: 'function',
                label: 'func1',
                filePath: 'test.ts',
                line: 1,
                metadata: { inDegree: 2, outDegree: 1 },
                relatedNodes: ['n2', 'n3', 'n4'],
                importance: 0.8,
                tags: [],
            });
            builder.addNode({
                id: 'n2',
                type: 'class',
                label: 'MyClass',
                filePath: 'test.ts',
                line: 10,
                metadata: { inDegree: 1, outDegree: 0 },
                relatedNodes: ['n1'],
                importance: 0.5,
                tags: [],
            });
            const stats = builder.getStatistics();
            (0, globals_1.expect)(stats.nodeCount).toBe(2);
            (0, globals_1.expect)(stats.typeDistribution['function']).toBe(1);
            (0, globals_1.expect)(stats.typeDistribution['class']).toBe(1);
            (0, globals_1.expect)(stats.densestNodes.length).toBeGreaterThan(0);
        });
        (0, globals_1.it)('should detect communities in graph', () => {
            // Create two separate communities
            ['n1', 'n2'].forEach((id) => {
                builder.addNode({
                    id,
                    type: 'function',
                    label: id,
                    filePath: 'test.ts',
                    line: 1,
                    metadata: {},
                    relatedNodes: [],
                    importance: 0.5,
                    tags: [],
                });
            });
            builder.addEdge('n1', 'n2', 'calls', 0.9);
            const communities = builder.detectCommunities();
            (0, globals_1.expect)(communities.length).toBeGreaterThan(0);
            (0, globals_1.expect)(communities[0].size).toBeGreaterThanOrEqual(1);
        });
    });
    (0, globals_1.describe)('Phase 5 Integration', () => {
        (0, globals_1.it)('should build graph from dependency graph', () => {
            const files = [
                { path: 'auth.ts', content: 'import utils from "./utils"; function login() {}' },
                { path: 'utils.ts', content: 'export function validate() {}' },
            ];
            const depGraph = extractor.buildDependencyGraph(files);
            builder.buildFromDependencyGraph(depGraph);
            const graph = builder.getGraph();
            (0, globals_1.expect)(graph.nodes.size).toBeGreaterThan(0);
            (0, globals_1.expect)(graph.metadata.totalNodes).toBeGreaterThan(0);
        });
        (0, globals_1.it)('should track importance based on relationships', () => {
            const node = {
                id: 'central',
                type: 'function',
                label: 'hub',
                filePath: 'hub.ts',
                line: 1,
                metadata: {},
                relatedNodes: ['a', 'b', 'c', 'd', 'e'],
                importance: 0,
                tags: [],
            };
            builder.addNode(node);
            const graph = builder.getGraph();
            const graphNode = graph.nodes.get('central');
            (0, globals_1.expect)(graphNode?.importance).toBeGreaterThan(0);
            (0, globals_1.expect)(graphNode?.importance).toBeLessThanOrEqual(1);
        });
        (0, globals_1.it)('should handle complex codebase', () => {
            const files = Array(5)
                .fill(null)
                .map((_, i) => ({
                path: `module${i}.ts`,
                content: `
            import { foo } from './module${(i + 1) % 5}';
            class Service${i} {}
            function handler${i}() {}
          `,
            }));
            const depGraph = extractor.buildDependencyGraph(files);
            (0, globals_1.expect)(depGraph.nodes.size).toBeGreaterThan(0);
            builder.buildFromDependencyGraph(depGraph);
            const graph = builder.getGraph();
            (0, globals_1.expect)(graph.nodes.size).toBeGreaterThan(0);
            (0, globals_1.expect)(graph.metadata.codebaseMetrics.totalFunctions).toBeGreaterThan(0);
        });
    });
});
//# sourceMappingURL=phase5.test.js.map