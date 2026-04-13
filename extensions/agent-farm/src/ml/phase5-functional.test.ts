/**
 * Phase 5 Functional Integration Test
 * Validates that all Phase 5 components work together
 */

// Import the core components
import CodeDependencyExtractor from '../ml/CodeDependencyExtractor';
import KnowledgeGraphBuilder from '../ml/KnowledgeGraphBuilder';

/**
 * Test 1: CodeDependencyExtractor can extract dependencies
 */
function testDependencyExtraction(): boolean {
  console.log('Test 1: Dependency Extraction...');
  const extractor = new CodeDependencyExtractor();
  
  const code = `
    import { foo } from './utils';
    class Child extends Parent {
      constructor() { super(); }
    }
    const result = MyClass.doSomething();
  `;
  
  try {
    const deps = extractor.extractDependencies(code, 'test.ts');
    console.log(`  ✓ Extracted ${deps.length} dependencies`);
    return deps.length > 0;
  } catch (error) {
    console.log(`  ✗ Error: ${error}`);
    return false;
  }
}

/**
 * Test 2: KnowledgeGraphBuilder can build and query graphs
 */
function testGraphBuilding(): boolean {
  console.log('Test 2: Graph Building...');
  const builder = new KnowledgeGraphBuilder();
  
  try {
    // Add some nodes
    builder.addNode({
      id: 'file1',
      type: 'file',
      label: 'service.ts',
      importance: 0.8,
    });
    
    builder.addNode({
      id: 'file2',
      type: 'file',
      label: 'utils.ts',
      importance: 0.5,
    });
    
    // Add edges
    builder.addEdge('file1', 'file2', 'imports', 0.9);
    
    // Get graph
    const graph = builder.getGraph();
    console.log(`  ✓ Graph has ${graph.nodes.size} nodes and ${graph.edges.size} edges`);
    
    // Search
    const results = builder.search('service', 10);
    console.log(`  ✓ Search returned ${results.length} results`);
    
    // Get statistics
    const stats = builder.getStatistics();
    console.log(`  ✓ Statistics computed: ${stats.nodeCount} nodes, ${stats.edgeCount} edges`);
    
    return true;
  } catch (error) {
    console.log(`  ✗ Error: ${error}`);
    return false;
  }
}

/**
 * Test 3: Path finding works
 */
function testPathFinding(): boolean {
  console.log('Test 3: Path Finding...');
  const builder = new KnowledgeGraphBuilder();
  
  try {
    // Create a chain: A -> B -> C
    builder.addNode({ id: 'a', type: 'file', label: 'A' });
    builder.addNode({ id: 'b', type: 'file', label: 'B' });
    builder.addNode({ id: 'c', type: 'file', label: 'C' });
    
    builder.addEdge('a', 'b', 'imports');
    builder.addEdge('b', 'c', 'imports');
    
    // Find path
    const path = builder.findShortestPath('a', 'c');
    console.log(`  ✓ Found path: ${path.join(' -> ')}`);
    
    return path.length === 3 && path[0] === 'a' && path[2] === 'c';
  } catch (error) {
    console.log(`  ✗ Error: ${error}`);
    return false;
  }
}

/**
 * Test 4: Community detection works
 */
function testCommunityDetection(): boolean {
  console.log('Test 4: Community Detection...');
  const builder = new KnowledgeGraphBuilder();
  
  try {
    // Create two communities
    builder.addNode({ id: 'a', type: 'file', label: 'A' });
    builder.addNode({ id: 'b', type: 'file', label: 'B' });
    builder.addNode({ id: 'c', type: 'file', label: 'C' });
    builder.addNode({ id: 'd', type: 'file', label: 'D' });
    
    // Tight community 1
    builder.addEdge('a', 'b', 'imports');
    builder.addEdge('b', 'a', 'imports');
    
    // Tight community 2
    builder.addEdge('c', 'd', 'imports');
    builder.addEdge('d', 'c', 'imports');
    
    const communities = builder.detectCommunities();
    console.log(`  ✓ Detected ${communities.length} communities`);
    
    return communities.length >= 2;
  } catch (error) {
    console.log(`  ✗ Error: ${error}`);
    return false;
  }
}

/**
 * Run all tests
 */
export function runPhase5FunctionalTests(): boolean {
  console.log('\n=== PHASE 5 FUNCTIONAL TESTS ===\n');
  
  const results = [
    testDependencyExtraction(),
    testGraphBuilding(),
    testPathFinding(),
    testCommunityDetection(),
  ];
  
  const passed = results.filter(r => r).length;
  const total = results.length;
  
  console.log(`\n=== RESULTS ===`);
  console.log(`Passed: ${passed}/${total}`);
  
  if (passed === total) {
    console.log('\n✓ ALL PHASE 5 FUNCTIONAL TESTS PASSED\n');
    return true;
  } else {
    console.log(`\n✗ SOME TESTS FAILED (${total - passed} failures)\n`);
    return false;
  }
}

// Run tests if executed directly
if (require.main === module) {
  const success = runPhase5FunctionalTests();
  process.exit(success ? 0 : 1);
}
