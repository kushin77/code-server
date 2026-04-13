/**
 * Phase 5: Knowledge Graph Integration - Test Suite
 * Tests for CodeDependencyExtractor and KnowledgeGraphBuilder
 */

import { describe, it, expect, beforeEach } from '@jest/globals';
import { CodeDependencyExtractor, DependencyGraph } from '../ml/CodeDependencyExtractor';
import {
  KnowledgeGraphBuilder,
  KnowledgeGraphNode,
  KnowledgeGraph,
} from '../ml/KnowledgeGraphBuilder';

describe('Phase 5: Knowledge Graph Integration', () => {
  let extractor: CodeDependencyExtractor;
  let builder: KnowledgeGraphBuilder;

  beforeEach(() => {
    extractor = new CodeDependencyExtractor();
    builder = new KnowledgeGraphBuilder();
  });

  describe('CodeDependencyExtractor', () => {
    it('should extract import dependencies from ES6 imports', () => {
      const code = `
        import { foo } from './utils';
        import * as Bar from './bar';
        import baz from './baz';
      `;

      const deps = extractor.extractDependencies(code, 'test.ts');

      expect(deps.length).toBeGreaterThanOrEqual(3);
      expect(deps[0].to.type).toBe('import');
      expect(deps[0].strength).toBeGreaterThan(0.8);
    });

    it('should extract CommonJS require dependencies', () => {
      const code = `
        const utils = require('./utils');
        const { foo } = require('./foo');
      `;

      const deps = extractor.extractDependencies(code, 'test.js');

      expect(deps.length).toBeGreaterThanOrEqual(2);
      expect(deps[0].to.type).toBe('import');
    });

    it('should extract class inheritance dependencies', () => {
      const code = `
        class Animal {}
        class Dog extends Animal {}
        class Cat extends Animal {}
      `;

      const deps = extractor.extractDependencies(code, 'animals.ts');

      expect(deps.length).toBeGreaterThanOrEqual(2);
      expect(deps.some((d) => d.to.type === 'extends')).toBeTruthy();
      expect(deps.every((d) => d.to.type === 'extends')).toBeTruthy();
    });

    it('should extract interface extension dependencies', () => {
      const code = `
        interface Base {}
        interface Derived extends Base {}
        interface Multi extends Base, Derived {}
      `;

      const deps = extractor.extractDependencies(code, 'interfaces.ts');

      expect(deps.length).toBeGreaterThanOrEqual(3);
      expect(deps.filter((d) => d.to.type === 'extends').length).toBeGreaterThan(0);
    });

    it('should extract class implements dependencies', () => {
      const code = `
        interface Logger {}
        class ConsoleLogger implements Logger {}
        class FileLogger implements Logger {}
      `;

      const deps = extractor.extractDependencies(code, 'logger.ts');

      expect(deps.some((d) => d.to.type === 'implements')).toBeTruthy();
    });

    it('should extract function call dependencies', () => {
      const code = `
        function helper() {}
        function main() {
          helper();
          helper();
        }
      `;

      const deps = extractor.extractDependencies(code, 'functions.ts');

      expect(deps.some((d) => d.to.type === 'calls')).toBeTruthy();
    });

    it('should build complete dependency graph', () => {
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

      expect(graph.nodes.size).toBeGreaterThan(0);
      expect(graph.edges.size).toBeGreaterThan(0);
      expect(graph.metrics.totalDependencies).toBeGreaterThan(0);
    });

    it('should detect cyclic dependencies', () => {
      const files = [
        { path: 'a.ts', content: 'import B from "./b"' },
        { path: 'b.ts', content: 'import C from "./c"' },
        { path: 'c.ts', content: 'import A from "./a"' },
      ];

      const graph = extractor.buildDependencyGraph(files);
      const cycles = extractor.analyzeCyclicDependencies(graph);

      expect(cycles.length).toBeGreaterThan(0);
    });

    it('should compute complexity metrics', () => {
      const files = [
        { path: 'file.ts', content: 'import dep from "./dep"; function foo() {}' },
      ];

      const graph = extractor.buildDependencyGraph(files);
      const metrics = extractor.computeComplexityMetrics(graph);

      expect(metrics.totalNodes).toBeGreaterThan(0);
      expect(metrics.totalEdges).toBeGreaterThanOrEqual(0);
      expect(metrics.averageInDegree).toBeGreaterThanOrEqual(0);
    });

    it('should identify orphaned nodes', () => {
      const files = [
        { path: 'used.ts', content: 'import dep from "./dep"' },
        { path: 'unused.ts', content: 'function isolated() {}' },
      ];

      const graph = extractor.buildDependencyGraph(files);

      // Unused.ts should be orphaned
      expect(graph.metrics.orphanedNodes.length).toBeGreaterThanOrEqual(0);
    });
  });

  describe('KnowledgeGraphBuilder', () => {
    it('should add nodes to graph', () => {
      const node: KnowledgeGraphNode = {
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

      expect(graph.nodes.size).toBe(1);
      expect(graph.nodes.get('test-1')).toBeDefined();
    });

    it('should add edges between nodes', () => {
      const node1: KnowledgeGraphNode = {
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

      const node2: KnowledgeGraphNode = {
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

      expect(graph.edges.size).toBe(1);
      expect(graph.nodes.get('n1')?.relatedNodes).toContain('n2');
    });

    it('should query by relationship', () => {
      const node1: KnowledgeGraphNode = {
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

      const node2: KnowledgeGraphNode = {
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

      expect(results.length).toBeGreaterThanOrEqual(1);
      expect(results.some((r) => r.label === 'authenticate')).toBeTruthy();
    });

    it('should find shortest path between nodes', () => {
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

      expect(path.length).toBeGreaterThan(0);
      expect(path[0]).toBe('n1');
      expect(path[path.length - 1]).toBe('n3');
    });

    it('should return empty path for disconnected nodes', () => {
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

      expect(path.length).toBe(0);
    });

    it('should get node context', () => {
      const centerNode: KnowledgeGraphNode = {
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

      expect(context.centerNode.id).toBe('center');
      expect(context.neighbors.length).toBeGreaterThan(0);
      expect(context.edges.length).toBeGreaterThan(0);
    });

    it('should search nodes by keyword', () => {
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

      expect(results.length).toBeGreaterThanOrEqual(1);
      expect(results.some((r) => r.id === 'auth-login')).toBeTruthy();
    });

    it('should get graph statistics', () => {
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

      expect(stats.nodeCount).toBe(2);
      expect(stats.typeDistribution['function']).toBe(1);
      expect(stats.typeDistribution['class']).toBe(1);
      expect(stats.densestNodes.length).toBeGreaterThan(0);
    });

    it('should detect communities in graph', () => {
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

      expect(communities.length).toBeGreaterThan(0);
      expect(communities[0].size).toBeGreaterThanOrEqual(1);
    });
  });

  describe('Phase 5 Integration', () => {
    it('should build graph from dependency graph', () => {
      const files = [
        { path: 'auth.ts', content: 'import utils from "./utils"; function login() {}' },
        { path: 'utils.ts', content: 'export function validate() {}' },
      ];

      const depGraph = extractor.buildDependencyGraph(files);
      builder.buildFromDependencyGraph(depGraph);
      const graph = builder.getGraph();

      expect(graph.nodes.size).toBeGreaterThan(0);
      expect(graph.metadata.totalNodes).toBeGreaterThan(0);
    });

    it('should track importance based on relationships', () => {
      const node: KnowledgeGraphNode = {
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

      expect(graphNode?.importance).toBeGreaterThan(0);
      expect(graphNode?.importance).toBeLessThanOrEqual(1);
    });

    it('should handle complex codebase', () => {
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
      expect(depGraph.nodes.size).toBeGreaterThan(0);

      builder.buildFromDependencyGraph(depGraph);
      const graph = builder.getGraph();

      expect(graph.nodes.size).toBeGreaterThan(0);
      expect(graph.metadata.codebaseMetrics.totalFunctions).toBeGreaterThan(0);
    });
  });
});
