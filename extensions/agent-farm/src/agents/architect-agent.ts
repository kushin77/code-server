/**
 * Architect Agent - System Design and Architecture Analysis
 * 
 * Specializes in analyzing system design, architecture patterns, scalability,
 * and API contracts. Provides strategic recommendations for enterprise-scale systems.
 */

import * as vscode from 'vscode';
import { Agent } from '../agent';
import { AgentSpecialization, TaskType, Recommendation } from '../types';

export class ArchitectAgent extends Agent {
  constructor() {
    super(
      'ArchitectAgent',
      AgentSpecialization.ARCHITECT,
      [
        TaskType.ARCHITECTURE,
        TaskType.PERFORMANCE,
        TaskType.REFACTORING,
      ]
    );
  }

  /**
   * Analyze code for architectural patterns and system design issues
   */
  async analyze(
    documentUri: vscode.Uri,
    code: string,
    context?: Record<string, unknown>
  ): Promise<Recommendation[]> {
    const recommendations: Recommendation[] = [];

    // Check for God Object pattern (class too large)
    const godObjectAnalysis = this.analyzeGodObject(code);
    recommendations.push(...godObjectAnalysis);

    // Check for circular dependencies and coupling
    const couplingAnalysis = this.analyzeCoupling(code);
    recommendations.push(...couplingAnalysis);

    // Check for missing abstraction layers
    const abstractionAnalysis = this.analyzeAbstraction(code);
    recommendations.push(...abstractionAnalysis);

    // Check for API contract issues
    const apiAnalysis = this.analyzeApiDesign(code);
    recommendations.push(...apiAnalysis);

    // Check for scalability concerns
    const scalabilityAnalysis = this.analyzeScalability(code);
    recommendations.push(...scalabilityAnalysis);

    // Check for separation of concerns
    const socAnalysis = this.analyzeSeparationOfConcerns(code);
    recommendations.push(...socAnalysis);

    // Check for error handling strategy
    const errorHandlingAnalysis = this.analyzeErrorHandling(code);
    recommendations.push(...errorHandlingAnalysis);

    return recommendations;
  }

  /**
   * Detect God Object pattern (classes doing too much)
   */
  private analyzeGodObject(code: string): Recommendation[] {
    const recommendations: Recommendation[] = [];
    
    // Match class definitions
    const classRegex = /class\s+(\w+)\s*(?:extends\s+\w+)?(?:implements\s+[\w,\s]+)?\s*{([^{}]*(?:{[^{}]*}[^{}]*)*)?}/g;
    let match;

    while ((match = classRegex.exec(code)) !== null) {
      const className = match[1];
      const classBody = match[2] || '';
      
      // Count public methods
      const methodRegex = /(?:public\s+)?(?:async\s+)?\w+\s*\([^)]*\)\s*(?::\s*[\w<>,\s]+)?\s*{/g;
      const methodCount = (classBody.match(methodRegex) || []).length;
      
      // Count properties
      const propertyRegex = /(?:private\s+|protected\s+|public\s+)?(?:readonly\s+)?\w+\s*(?::\s*[\w<>,\s]+|=)/g;
      const propertyCount = (classBody.match(propertyRegex) || []).length;
      
      const totalMembers = methodCount + propertyCount;
      
      // Flag if too many responsibilities
      if (totalMembers > 15) {
        recommendations.push({
          id: `arch-god-object-${className}`,
          title: 'God Object Pattern Detected',
          description: `Class "${className}" has ${totalMembers} members (methods + properties). This suggests too many responsibilities.`,
          severity: totalMembers > 25 ? 'critical' : 'warning',
          actionable: true,
          suggestedFix: `Break "${className}" into smaller, focused classes:\n- Extract related methods into dedicated classes\n- Use composition instead of inheritance\n- Apply Single Responsibility Principle`,
          codeSnippet: `// Instead of one large class:\nclass ${className} { /* ${totalMembers} members */ }\n\n// Consider:\nclass ${className}Manager { /* core logic */ }\nclass ${className}Validator { /* validation */ }\nclass ${className}Formatter { /* formatting */ }`,
          documentationUrl: 'https://refactoring.guru/smells/large-class',
        });
      }
    }
    
    return recommendations;
  }

  /**
   * Detect high coupling and circular dependencies
   */
  private analyzeCoupling(code: string): Recommendation[] {
    const recommendations: Recommendation[] = [];
    
    // Detect import patterns that suggest tight coupling
    const importRegex = /import\s*{([^}]+)}\s*from\s*['"]([^'"]+)['"]/g;
    const imports = new Map<string, string[]>();
    let match;

    while ((match = importRegex.exec(code)) !== null) {
      const items = match[1].split(',').map(s => s.trim());
      const source = match[2];
      imports.set(source, items);
    }

    // Check for multiple imports from same implementation module (not interfaces)
    for (const [source, items] of imports) {
      if (items.length > 5 && !source.includes('types') && !source.includes('interface')) {
        recommendations.push({
          id: `arch-tight-coupling-${source}`,
          title: 'Tight Coupling to Implementation Module',
          description: `Importing ${items.length} items from "${source}". This suggests tight coupling to a specific implementation.`,
          severity: 'warning',
          actionable: true,
          suggestedFix: `Define and depend on interfaces instead of implementations:\n${items.slice(0, 3).join(', ')}, etc. → Consider creating interfaces.${items.length > 3 ? `(+${items.length - 3} more)` : ''}`,
          codeSnippet: `// Before:\nimport { ${items.join(', ')} } from '${source}';\n\n// After:\nimport { ${items.slice(0, 2).join(', ')} } from '${source}/types';`,
        });
      }
    }

    return recommendations;
  }

  /**
   * Analyze missing abstraction layers and leaky abstractions
   */
  private analyzeAbstraction(code: string): Recommendation[] {
    const recommendations: Recommendation[] = [];

    // Check for direct error codes/strings (should be abstracted)
    const magicErrorRegex = /(['"])([A-Z_0-9]{3,})(['"])|error:\s*(['"])([^'"]+)(['"])/g;
    const errors = new Set<string>();
    let match;

    while ((match = magicErrorRegex.exec(code)) !== null) {
      errors.add(match[2] || match[5] || '');
    }

    if (errors.size > 3) {
      recommendations.push({
        id: 'arch-magic-errors',
        title: 'Magic Error Codes/Messages Should Be Constants',
        description: `Found ${errors.size} hardcoded error codes/messages. These should be abstracted as constants.`,
        severity: 'info',
        actionable: true,
        suggestedFix: 'Create an ErrorCodes enum or ERRORS constant object to centralize error definitions.',
        codeSnippet: `enum ErrorCodes {\n  INVALID_INPUT = 'INVALID_INPUT',\n  NOT_FOUND = 'NOT_FOUND',\n  INTERNAL_ERROR = 'INTERNAL_ERROR',\n}\n\n// Use: throw new Error(ErrorCodes.INVALID_INPUT);`,
      });
    }

    // Check for missing interface/contract definitions
    const functionRegex = /(?:export\s+)?(?:async\s+)?function\s+(\w+)\s*\([^)]*\)\s*(?::\s*[\w<>,\s]+)?\s*{/g;
    const functions: string[] = [];

    while ((match = functionRegex.exec(code)) !== null) {
      functions.push(match[1]);
    }

    // If many exported functions without clear interface, suggest abstraction
    const exportRegex = /export\s+/g;
    const exportCount = (code.match(exportRegex) || []).length;

    if (exportCount > 5 && !code.includes('interface') && !code.includes('type ')) {
      recommendations.push({
        id: 'arch-missing-contract',
        title: 'Missing Public Interface/Contract',
        description: `Module exports ${exportCount} items without a clear public contract (no interface or type definition).`,
        severity: 'warning',
        actionable: true,
        suggestedFix: 'Define a public interface that documents what this module provides to consumers.',
        codeSnippet: `interface ModuleContract {\n  // Public API\n}\n\nexport class ModuleImpl implements ModuleContract {\n  // Implementation\n}`,
      });
    }

    return recommendations;
  }

  /**
   * Analyze API design and contract issues
   */
  private analyzeApiDesign(code: string): Recommendation[] {
    const recommendations: Recommendation[] = [];

    // Check for any/unknown types (weak contracts)
    const anyTypeRegex = /:\s*(any|unknown)\s*[,;)=>]/g;
    const anyCount = (code.match(anyTypeRegex) || []).length;

    if (anyCount > 2) {
      recommendations.push({
        id: 'arch-weak-types',
        title: 'Weak Type Contracts (any/unknown)',
        description: `Found ${anyCount} uses of 'any' or 'unknown'. These weaken your API contract and reduce type safety.`,
        severity: 'warning',
        actionable: true,
        suggestedFix: 'Replace any/unknown with specific types or use generics for flexibility.',
        codeSnippet: `// Before:\nfunction process(data: any): unknown\n\n// After:\nfunction process<T extends Record<string, unknown>>(data: T): ProcessResult<T>`,
      });
    }

    // Check for boolean trap (multiple boolean parameters)
    const functionRegex = /(?:function|method|=>\s*)|(?:\w+\s*\()/g;
    const boolParamRegex = /\(\s*[^)]*:\s*boolean\s*,\s*[^)]*:\s*boolean/g;
    const boolTrapCount = (code.match(boolParamRegex) || []).length;

    if (boolTrapCount > 0) {
      recommendations.push({
        id: 'arch-boolean-trap',
        title: 'Boolean Trap API Anti-Pattern',
        description: 'Function parameters include multiple booleans. This creates unclear APIs (e.g., process(true, false) - what do these mean?)',
        severity: 'info',
        actionable: true,
        suggestedFix: 'Use named options object instead of boolean flags for clarity.',
        codeSnippet: `// Before:\nfunction process(validate: boolean, transform: boolean): void\nprocess(true, false); // What does this mean?\n\n// After:\nfunction process(options: { validate: boolean; transform: boolean }): void\nprocess({ validate: true, transform: false }); // Clear intent`,
      });
    }

    return recommendations;
  }

  /**
   * Analyze scalability concerns
   */
  private analyzeScalability(code: string): Recommendation[] {
    const recommendations: Recommendation[] = [];

    // Check for synchronous operations that should be async
    const syncOpsRegex = /require\s*\(|fs\.(readFileSync|writeFileSync|statSync)|JSON\.(stringify|parse)|\.sort\(\)|\.filter\(\)/g;
    const syncOps = (code.match(syncOpsRegex) || []).length;

    if (syncOps > 2 && code.includes('export')) {
      recommendations.push({
        id: 'arch-blocking-ops',
        title: 'Synchronous Operations Block Event Loop',
        description: `Found ${syncOps} blocking operations. In Node.js, these prevent other requests from being processed.`,
        severity: 'warning',
        actionable: true,
        suggestedFix: 'Use async versions or offload to worker threads for CPU-heavy operations.',
        codeSnippet: `// Before (blocking):\nconst data = fs.readFileSync('./large-file.json');\n\n// After (non-blocking):\nconst data = await fs.promises.readFile('./large-file.json');`,
      });
    }

    // Check for unbounded loops/recursion
    const unboundedLoopRegex = /while\s*\(\s*true\s*\)|for\s*\(\s*;\s*;\s*\)/g;
    const unboundedCount = (code.match(unboundedLoopRegex) || []).length;

    if (unboundedCount > 0) {
      recommendations.push({
        id: 'arch-unbounded-iteration',
        title: 'Unbounded Iteration May Never Terminate',
        description: 'Found infinite loop(s) without clear exit conditions. This can cause memory leaks or total system hang.',
        severity: 'critical',
        actionable: true,
        suggestedFix: 'Add explicit termination conditions and ensure proper cleanup on exit.',
        codeSnippet: `// Before:\nwhile (true) {\n  // Do work\n}\n\n// After:\nlet running = true;\nwhile (running) {\n  // Do work\n  if (exitCondition) running = false;\n}`,
      });
    }

    return recommendations;
  }

  /**
   * Analyze separation of concerns
   */
  private analyzeSeparationOfConcerns(code: string): Recommendation[] {
    const recommendations: Recommendation[] = [];

    // Check if business logic is mixed with infrastructure
    const infraPatterns = /console\.|fs\.|http\.|fetch\(|db\.|query\(|execute\(/g;
    const infraCount = (code.match(infraPatterns) || []).length;

    const businessLogicRegex = /if\s*\(|for\s*\(|while\s*\(|map\(|filter\(|reduce\(/g;
    const businessLogicCount = (code.match(businessLogicRegex) || []).length;

    if (infraCount > 0 && businessLogicCount > 5) {
      recommendations.push({
        id: 'arch-mixed-concerns',
        title: 'Business Logic Mixed with Infrastructure',
        description: `This module mixes infrastructure (${infraCount} calls) with business logic (${businessLogicCount})`,
        severity: 'warning',
        actionable: true,
        suggestedFix: 'Separate business logic from infrastructure concerns using dependency injection.',
        codeSnippet: `// Before: Mixed concerns\nclass Service {\n  process() {\n    const data = fs.readFileSync('...');\n    // Business logic\n    console.log(result);\n  }\n}\n\n// After: Separated concerns\nclass Service {\n  constructor(private storage: Storage, private logger: Logger) {}\n  process(data: Data) {\n    // Pure business logic\n    const result = this.businessLogic(data);\n    this.logger.info(result);\n  }\n}`,
      });
    }

    return recommendations;
  }

  /**
   * Analyze error handling strategy
   */
  private analyzeErrorHandling(code: string): Recommendation[] {
    const recommendations: Recommendation[] = [];

    // Check for generic error catches
    const genericCatchRegex = /catch\s*\(\s*(\w+)\s*\)\s*{([^}]*console\.log|[^}]*return\s+null|[^}]*\/\/\s*ignore)/g;
    const genericCatchCount = (code.match(genericCatchRegex) || []).length;

    if (genericCatchCount > 0) {
      recommendations.push({
        id: 'arch-generic-error-handling',
        title: 'Generic Error Handling (Log and Ignore)',
        description: `Found ${genericCatchCount} catch block(s) that just log or ignore errors. This hides problems.`,
        severity: 'warning',
        actionable: true,
        suggestedFix: 'Implement proper error handling: recover, retry, or propagate with context.',
        codeSnippet: `// Before:\ntry {\n  // Do work\n} catch (error) {\n  console.log(error); // Ignored!\n}\n\n// After:\ntry {\n  // Do work\n} catch (error) {\n  if (isRetryable(error)) {\n    return retry();\n  }\n  throw new ServiceError('Failed to process', { cause: error });\n}`,
      });
    }

    // Check for missing error typing
    if (!code.includes('Error') && code.includes('throw ')) {
      recommendations.push({
        id: 'arch-untyped-errors',
        title: 'Missing Error Type Definitions',
        description: 'No custom error classes defined. Errors should be strongly typed.',
        severity: 'info',
        actionable: true,
        suggestedFix: 'Define custom error classes for different failure scenarios.',
        codeSnippet: `class ValidationError extends Error {\n  constructor(message: string, public fields: string[]) {\n    super(message);\n    this.name = 'ValidationError';\n  }\n}`,
      });
    }

    return recommendations;
  }
}
