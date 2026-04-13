/**
 * Test Agent - Test Coverage and Quality Analysis
 * 
 * Specializes in analyzing test coverage, identifying untested code paths,
 * suggesting edge cases, and recommending property-based testing strategies.
 */

import * as vscode from 'vscode';
import { Agent } from '../agent';
import { AgentSpecialization, TaskType, Recommendation } from '../types';

export class TestAgent extends Agent {
  constructor() {
    super(
      'TestAgent',
      AgentSpecialization.TESTER,
      [
        TaskType.TEST_COVERAGE,
        TaskType.CODE_IMPLEMENTATION,
      ]
    );
  }

  /**
   * Analyze code for test coverage and quality
   */
  async analyze(
    documentUri: vscode.Uri,
    code: string,
    context?: Record<string, unknown>
  ): Promise<Recommendation[]> {
    const recommendations: Recommendation[] = [];

    // Check for functions without tests
    const missingTestAnalysis = this.analyzeMissingTests(code);
    recommendations.push(...missingTestAnalysis);

    // Check for untested edge cases
    const edgeCaseAnalysis = this.analyzeEdgeCases(code);
    recommendations.push(...edgeCaseAnalysis);

    // Check for testability issues
    const testabilityAnalysis = this.analyzeTestability(code);
    recommendations.push(...testabilityAnalysis);

    // Check for mocking complexity
    const mockingAnalysis = this.analyzeMockingComplexity(code);
    recommendations.push(...mockingAnalysis);

    // Check for property-based testing opportunities
    const propertyTestAnalysis = this.analyzePropertyTesting(code);
    recommendations.push(...propertyTestAnalysis);

    // Check for missing error case testing
    const errorTestingAnalysis = this.analyzeErrorTesting(code);
    recommendations.push(...errorTestingAnalysis);

    // Check for performance testing needs
    const perfTestAnalysis = this.analyzePerformanceTesting(code);
    recommendations.push(...perfTestAnalysis);

    return recommendations;
  }

  /**
   * Detect public functions/exported code without tests
   */
  private analyzeMissingTests(code: string): Recommendation[] {
    const recommendations: Recommendation[] = [];
    
    // Find exported functions
    const exportFunctionRegex = /export\s+(?:async\s+)?function\s+(\w+)\s*\(/g;
    const exportClassRegex = /export\s+class\s+(\w+)/g;
    
    let match;
    const exportedFunctions = new Set<string>();
    const exportedClasses = new Set<string>();

    while ((match = exportFunctionRegex.exec(code)) !== null) {
      exportedFunctions.add(match[1]);
    }

    while ((match = exportClassRegex.exec(code)) !== null) {
      exportedClasses.add(match[1]);
    }

    // Check if this file or related .test/.spec file has tests
    const isTestFile = /\.test\.|\.spec\.|__tests__|\.test\.ts|\.spec\.ts/.test(code);
    
    if (!isTestFile) {
      const totalExports = exportedFunctions.size + exportedClasses.size;
      
      if (totalExports > 0) {
        recommendations.push({
          id: 'test-missing-coverage',
          title: `Missing Tests for ${totalExports} Exported Function(s)`,
          description: `Found ${exportedFunctions.size} exported function(s) and ${exportedClasses.size} class(es) with no apparent test file.`,
          severity: totalExports > 5 ? 'critical' : 'warning',
          actionable: true,
          suggestedFix: `Create test file:\n${[...exportedFunctions].slice(0, 2).map(fn => `  - ${fn}()`).join('\n')}${exportedFunctions.size > 2 ? `\n  - ... +${exportedFunctions.size - 2} more` : ''}`,
          codeSnippet: `// Create: ${(code.match(/^.*(?:\.ts|\.js)/)?.[0] || 'module').replace(/\.\w+$/, '.test.ts')}\nimport { ${[...exportedFunctions].slice(0, 2).join(', ')} } from './';\n\ndescribe('Module', () => {\n  describe('${[...exportedFunctions][0] || 'function'}', () => {\n    it('should ...', () => {\n      // Arrange\n      // Act\n      // Assert\n    });\n  });\n});`,
          documentationUrl: 'https://jestjs.io/docs/getting-started',
        });
      }
    }

    return recommendations;
  }

  /**
   * Identify untested edge cases
   */
  private analyzeEdgeCases(code: string): Recommendation[] {
    const recommendations: Recommendation[] = [];

    // Check for array operations without boundary checks
    const arrayOpsRegex = /\.map\(|\.filter\(|\.reduce\(|\.some\(|\.find\(|\.slice\(|\.splice\(/g;
    const arrayOpsCount = (code.match(arrayOpsRegex) || []).length;

    if (arrayOpsCount > 0) {
      recommendations.push({
        id: 'test-missing-array-edge-cases',
        title: `${arrayOpsCount} Array Operations Need Edge Case Tests`,
        description: 'Found array operations without evidence of testing empty arrays, single elements, or boundary conditions.',
        severity: 'info',
        actionable: true,
        suggestedFix: 'Add tests for: empty arrays, single element, large arrays, null/undefined values.',
        codeSnippet: `it('should handle edge cases for array operations', () => {\n  expect(processArray([])).toEqual(...);      // Empty\n  expect(processArray([1])).toEqual(...);      // Single\n  expect(processArray([1, 2, 3])).toEqual(...); // Multiple\n  expect(processArray(null)).toThrow();         // Null\n});`,
      });
    }

    // Check for numeric calculations
    const numericRegex = /[+\-*/%]|(parseFloat|parseInt|Math\.)/g;
    const numericCount = (code.match(numericRegex) || []).length;

    if (numericCount > 3) {
      recommendations.push({
        id: 'test-missing-numeric-edge-cases',
        title: 'Numeric Operations Need Edge Case Testing',
        description: `Found ${numericCount} numeric operations. Tests should cover: zero, negative, very large, floating-point precision.`,
        severity: 'info',
        actionable: true,
        suggestedFix: 'Test boundary values: 0, -1, Number.MAX_SAFE_INTEGER, Number.EPSILON, NaN, Infinity.',
        codeSnippet: `it('should handle numeric edge cases', () => {\n  expect(calculate(0)).toBe(...);                    // Zero\n  expect(calculate(-1)).toBe(...);                   // Negative\n  expect(calculate(Number.MAX_SAFE_INTEGER)).toBe(...); // Max\n  expect(calculate(0.1 + 0.2)).toBeCloseTo(0.3);   // Precision\n});`,
      });
    }

    // Check for string operations
    const stringOpsRegex = /\.split\(|\.replace\(|\.substring\(|\.slice\(|\.trim\(|\.toLowerCase\(|\.toUpperCase\(/g;
    const stringOpsCount = (code.match(stringOpsRegex) || []).length;

    if (stringOpsCount > 0) {
      recommendations.push({
        id: 'test-missing-string-edge-cases',
        title: `${stringOpsCount} String Operations Need Edge Case Tests`,
        description: 'Found string operations. Tests should cover: empty strings, whitespace, special characters, unicode.',
        severity: 'info',
        actionable: true,
        suggestedFix: 'Test: empty string, spaces, unicode, emojis, very long strings, null/undefined.',
        codeSnippet: `it('should handle string edge cases', () => {\n  expect(process('')).toBe(...);              // Empty\n  expect(process('   ')).toBe(...);           // Whitespace\n  expect(process('café')).toBe(...);         // Unicode\n  expect(process('😀')).toBe(...);           // Emoji\n});`,
      });
    }

    return recommendations;
  }

  /**
   * Analyze testability issues
   */
  private analyzeTestability(code: string): Recommendation[] {
    const recommendations: Recommendation[] = [];

    // Check for hard-coded dependencies
    const hardCodedDepsRegex = /new\s+\w+\(|require\s*\(['"]/g;
    const hardCodedCount = (code.match(hardCodedDepsRegex) || []).length;

    if (hardCodedCount > 2) {
      recommendations.push({
        id: 'test-hard-coded-dependencies',
        title: 'Hard-Coded Dependencies Make Testing Difficult',
        description: `Found ${hardCodedCount} hard-coded dependencies. These should be injected for easier mocking.`,
        severity: 'warning',
        actionable: true,
        suggestedFix: 'Use dependency injection constructor parameters instead of creating instances inline.',
        codeSnippet: `// Before (hard to test):\nclass Service {\n  private db = new Database();\n  async fetch() { return this.db.query(...); }\n}\n\n// After (testable):\nclass Service {\n  constructor(private db: Database) {}\n  async fetch() { return this.db.query(...); }\n}\n\n// Test:\nconst mockDb = createMock<Database>();\nconst service = new Service(mockDb);`,
      });
    }

    // Check for global state
    const globalStateRegex = /globalThis\.|global\.|process\.env|window\.|localStorage/g;
    const globalCount = (code.match(globalStateRegex) || []).length;

    if (globalCount > 0) {
      recommendations.push({
        id: 'test-global-state',
        title: 'Global State Access Prevents Test Isolation',
        description: `Found ${globalCount} global state access(es). These create test dependencies and flakiness.`,
        severity: 'warning',
        actionable: true,
        suggestedFix: 'Encapsulate global state in a service and inject it. Set up/tear down in test fixtures.',
        codeSnippet: `// Before:\nif (process.env.NODE_ENV === 'production') { ... }\n\n// After:\ninterface Config {\n  isProduction: boolean;\n}\nclass Service {\n  constructor(private config: Config) {}\n  execute() {\n    if (this.config.isProduction) { ... }\n  }\n}`,
      });
    }

    // Check for timing-dependent code
    const timingRegex = /setTimeout|setInterval|Date\.now\(\)|new Date\(\)|delay\(/g;
    const timingCount = (code.match(timingRegex) || []).length;

    if (timingCount > 0) {
      recommendations.push({
        id: 'test-timing-dependent',
        title: 'Timing-Dependent Code Creates Flaky Tests',
        description: `Found ${timingCount} timing-dependent call(s). These cause intermittent test failures.`,
        severity: 'warning',
        actionable: true,
        suggestedFix: 'Use fake timers (jest.useFakeTimers) and inject clock/time service.',
        codeSnippet: `// Before (flaky):\nasync function retry() {\n  for (let i = 0; i < 5; i++) {\n    try { return await attempt(); }\n    catch { await new Promise(r => setTimeout(r, 1000)); }\n  }\n}\n\n// After (testable):\nasync function retry(clock: Clock) {\n  for (let i = 0; i < 5; i++) {\n    try { return await attempt(); }\n    catch { await clock.sleep(1000); }\n  }\n}\n\n// Test:\njest.useFakeTimers();\nconst mockClock = { sleep: jest.fn() };`,
      });
    }

    return recommendations;
  }

  /**
   * Analyze mocking complexity
   */
  private analyzeMockingComplexity(code: string): Recommendation[] {
    const recommendations: Recommendation[] = [];

    // Check for complex objects being created inline
    const objectLiteralRegex = /{[^{}]*:[^{}]*,[^{}]*:[^{}]*,[^{}]*:[^{}]*/g;
    const complexObjectCount = (code.match(objectLiteralRegex) || []).length;

    if (complexObjectCount > 3) {
      recommendations.push({
        id: 'test-complex-test-setup',
        title: 'Complex Test Setup Objects Need Factories',
        description: `Found ${complexObjectCount} complex object literals. These should use test factories for reuse.`,
        severity: 'info',
        actionable: true,
        suggestedFix: 'Create test factory functions or builder pattern for complex test data.',
        codeSnippet: `// Before (repeated setup):\nconst user = { id: 1, name: 'Test', email: 'test@test.com', role: 'admin', ... };\n\n// After (factory):\nfnction createUser(overrides?: Partial<User>): User {\n  return { id: 1, name: 'Test', email: 'test@test.com', ...(overrides || {}) };\n}\n\nconst user = createUser({ role: 'admin' });`,
      });
    }

    return recommendations;
  }

  /**
   * Analyze opportunities for property-based testing
   */
  private analyzePropertyTesting(code: string): Recommendation[] {
    const recommendations: Recommendation[] = [];

    // Check for functions with mathematical properties
    const mathFuncsRegex = /\/\*.*(?:sort|filter|map|reduce|sum|min|max|average)\s*\*\/|function\s+(?:sort|filter|map|calculate|combine)/gi;
    const hasMathLogic = mathFuncsRegex.test(code);

    if (hasMathLogic) {
      recommendations.push({
        id: 'test-property-based-testing',
        title: 'Mathematical Properties Should Use Property-Based Testing',
        description: 'This code processes lists/numbers. Property-based testing can verify invariants across random inputs.',
        severity: 'info',
        actionable: true,
        suggestedFix: 'Use fast-check or similar library to test invariants (e.g., sort preserves length).',
        codeSnippet: `import fc from 'fast-check';\n\nit('sort maintains array length', () => {\n  fc.assert(\n    fc.property(fc.array(fc.integer()), (arr) => {\n      expect(sort(arr).length).toBe(arr.length);\n    })\n  );\n});\n\nit('sort output is sorted', () => {\n  fc.assert(\n    fc.property(fc.array(fc.integer()), (arr) => {\n      const sorted = sort(arr);\n      for (let i = 1; i < sorted.length; i++) {\n        expect(sorted[i]).toBeGreaterThanOrEqual(sorted[i - 1]);\n      }\n    })\n  );\n});`,
      });
    }

    return recommendations;
  }

  /**
   * Analyze error case testing
   */
  private analyzeErrorTesting(code: string): Recommendation[] {
    const recommendations: Recommendation[] = [];

    // Check for try-catch blocks
    const tryCatchRegex = /try\s*{([^}]+)}\s*catch\s*\(\s*(\w+)\s*\)\s*{/g;
    const tryCatchCount = (code.match(tryCatchRegex) || []).length;

    if (tryCatchCount > 0) {
      recommendations.push({
        id: 'test-missing-error-case-tests',
        title: `${tryCatchCount} Error Case(s) Should Have Dedicated Tests`,
        description: 'Found try-catch blocks. Every error path should have a test that verifies the error is caught and handled.',
        severity: 'warning',
        actionable: true,
        suggestedFix: 'Write tests that trigger each error condition and verify proper handling.',
        codeSnippet: `// Test error cases:\nit('should handle validation errors', async () => {\n  expect(async () => {\n    await process(invalidData);\n  }).rejects.toThrow(ValidationError);\n});\n\nit('should retry on transient errors', async () => {\n  const mockDb = { query: jest.fn().mockRejectedValueOnce(new Error()).mockResolvedValue([]) };\n  const result = await fetch(mockDb);\n  expect(result).toBeDefined();\n  expect(mockDb.query).toHaveBeenCalledTimes(2);\n});`,
      });
    }

    // Check for async functions
    if (code.includes('async ')) {
      recommendations.push({
        id: 'test-missing-async-error-tests',
        title: 'Async Functions Need Promise Rejection Tests',
        description: 'Async functions should test both successful and failed promise cases.',
        severity: 'info',
        actionable: true,
        suggestedFix: 'Test promise rejections with rejects.toThrow or expect().rejects.',
        codeSnippet: `// Test async failure:\nit('should reject on network error', async () => {\n  mockedFetch.mockRejectedValue(new Error('Network failed'));\n  await expect(fetchData()).rejects.toThrow('Network failed');\n});\n\n// Or:\nit('should handle rejection', async () => {\n  try {\n    await fetchData();\n    fail('Should have thrown');\n  } catch (error) {\n    expect(error.message).toContain('Network');\n  }\n});`,
      });
    }

    return recommendations;
  }

  /**
   * Analyze performance testing needs
   */
  private analyzePerformanceTesting(code: string): Recommendation[] {
    const recommendations: Recommendation[] = [];

    // Check for looping/iterative operations
    const loopRegex = /for\s*\(|while\s*\(|\.forEach|\.map\(|\.filter\(|\.reduce\(/g;
    const loopCount = (code.match(loopRegex) || []).length;

    // Check for algorithms that might have performance concerns
    const complexityRegex = /nested\s+loop|O\(n\^2\)|exponential|factorial|fibonacci/gi;
    const hasComplexityWarning = complexityRegex.test(code);

    if (loopCount > 2 || hasComplexityWarning) {
      recommendations.push({
        id: 'test-performance-testing',
        title: 'Performance-Critical Code Needs Benchmarks',
        description: hasComplexityWarning 
          ? 'Complex algorithm detected. Benchmark tests should verify performance doesn\'t degrade.' 
          : `Found ${loopCount} loop(s). Add performance tests for large input sizes.`,
        severity: 'info',
        actionable: true,
        suggestedFix: 'Use jest.measurePerformance or benchmark library to track performance.',
        codeSnippet: `it('should process large arrays efficiently', () => {\n  const largeArray = Array.from({ length: 10000 }, (_, i) => i);\n  const start = performance.now();\n  const result = process(largeArray);\n  const duration = performance.now() - start;\n  expect(duration).toBeLessThan(100); // 100ms threshold\n});\n\nit('should not exhibit quadratic behavior', () => {\n  const small = Array.from({ length: 100 }, (_, i) => i);\n  const large = Array.from({ length: 1000 }, (_, i) => i);\n  // If O(n²), large would be 100x slower\n  // If O(n), large would be 10x slower\n});`,
      });
    }

    return recommendations;
  }
}
