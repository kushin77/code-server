/**
 * Code Indexer - Semantic Code Analysis
 * 
 * Indexes code structure for intelligent agent routing and semantic search.
 * Identifies functions, classes, patterns, and complexity metrics.
 */

import { CodeElementType, CodeElement, CodeIndex } from './types';

/**
 * Semantic code indexer
 */
export class CodeIndexer {
  /**
   * Index code and extract structural information
   */
  static index(code: string, fileName: string): CodeIndex {
    const lines = code.split('\n');
    const elements: CodeElement[] = [];

    // Extract functions
    elements.push(...this.extractFunctions(code, lines));

    // Extract classes
    elements.push(...this.extractClasses(code, lines));

    // Extract interfaces/types
    elements.push(...this.extractInterfaces(code, lines));

    // Extract imports/exports
    elements.push(...this.extractImports(code, lines));
    elements.push(...this.extractExports(code, lines));

    // Calculate statistics
    const statistics = this.calculateStatistics(elements, code);

    return {
      fileName,
      totalLines: lines.length,
      elements,
      statistics,
    };
  }

  /**
   * Extract functions from code
   */
  private static extractFunctions(code: string, lines: string[]): CodeElement[] {
    const functions: CodeElement[] = [];
    const functionRegex = /(?:async\s+)?function\s+(\w+)|const\s+(\w+)\s*=\s*(?:async\s*)?\(/g;
    let match;

    while ((match = functionRegex.exec(code)) !== null) {
      const name = match[1] || match[2];
      const lineNumber = code.substring(0, match.index).split('\n').length;
      const functionBody = this.extractBlock(code, match.index);
      const endLine = code.substring(0, match.index + functionBody.length).split('\n').length;

      functions.push({
        type: CodeElementType.FUNCTION,
        name,
        lineStart: lineNumber,
        lineEnd: endLine,
        complexity: this.estimateComplexity(functionBody),
        hasTests: this.hasTestCoverage(name, code),
        isExported: this.isExported(name, code),
        documentation: this.extractDocumentation(code, match.index),
        children: [],
      });
    }

    return functions;
  }

  /**
   * Extract classes from code
   */
  private static extractClasses(code: string, lines: string[]): CodeElement[] {
    const classes: CodeElement[] = [];
    const classRegex = /class\s+(\w+)(?:\s+extends\s+(\w+))?\s*\{/g;
    let match;

    while ((match = classRegex.exec(code)) !== null) {
      const name = match[1];
      const lineNumber = code.substring(0, match.index).split('\n').length;
      const classBody = this.extractBlock(code, match.index);
      const endLine = code.substring(0, match.index + classBody.length).split('\n').length;

      // Extract methods from class body
      const methods = this.extractMethodsFromClass(classBody);

      classes.push({
        type: CodeElementType.CLASS,
        name,
        lineStart: lineNumber,
        lineEnd: endLine,
        complexity: this.estimateComplexity(classBody),
        hasTests: this.hasTestCoverage(name, code),
        isExported: this.isExported(name, code),
        documentation: this.extractDocumentation(code, match.index),
        children: methods,
      });
    }

    return classes;
  }

  /**
   * Extract interfaces/types from code
   */
  private static extractInterfaces(code: string, lines: string[]): CodeElement[] {
    const elements: CodeElement[] = [];
    const interfaceRegex = /(?:interface|type)\s+(\w+)\s*(?:extends|=)?\s*\{/g;
    let match;

    while ((match = interfaceRegex.exec(code)) !== null) {
      const name = match[1];
      const lineNumber = code.substring(0, match.index).split('\n').length;
      const block = this.extractBlock(code, match.index);
      const endLine = code.substring(0, match.index + block.length).split('\n').length;

      elements.push({
        type: CodeElementType.INTERFACE,
        name,
        lineStart: lineNumber,
        lineEnd: endLine,
        complexity: 1,
        hasTests: false,
        isExported: this.isExported(name, code),
        documentation: this.extractDocumentation(code, match.index),
        children: [],
      });
    }

    return elements;
  }

  /**
   * Extract imports from code
   */
  private static extractImports(code: string, lines: string[]): CodeElement[] {
    const imports: CodeElement[] = [];
    const importRegex = /import\s+(?:(?:\{|.*?\}|.*?)\s+from\s+)?['"](.*?)['"];/g;
    let match;
    let lineNumber = 1;

    while ((match = importRegex.exec(code)) !== null) {
      lineNumber = code.substring(0, match.index).split('\n').length;
      
      imports.push({
        type: CodeElementType.IMPORT,
        name: match[1],
        lineStart: lineNumber,
        lineEnd: lineNumber,
        complexity: 0,
        hasTests: false,
        isExported: false,
        documentation: undefined,
        children: [],
      });
    }

    return imports;
  }

  /**
   * Extract exports from code
   */
  private static extractExports(code: string, lines: string[]): CodeElement[] {
    const exports: CodeElement[] = [];
    const exportRegex = /export\s+(?:default\s+)?(?:function|class|const|type|interface)\s+(\w+)/g;
    let match;

    while ((match = exportRegex.exec(code)) !== null) {
      const lineNumber = code.substring(0, match.index).split('\n').length;
      
      exports.push({
        type: CodeElementType.EXPORT,
        name: match[1],
        lineStart: lineNumber,
        lineEnd: lineNumber,
        complexity: 0,
        hasTests: false,
        isExported: true,
        documentation: undefined,
        children: [],
      });
    }

    return exports;
  }

  /**
   * Extract methods from a class body
   */
  private static extractMethodsFromClass(classBody: string): CodeElement[] {
    const methods: CodeElement[] = [];
    const methodRegex = /(?:async\s+)?(\w+)\s*\(.*?\)\s*\{/g;
    let match;

    while ((match = methodRegex.exec(classBody)) !== null) {
      const name = match[1];
      // Skip constructor-like patterns
      if (name === 'constructor' || name === 'class') continue;

      methods.push({
        type: CodeElementType.FUNCTION,
        name,
        lineStart: 0, // Relative to class
        lineEnd: 0,
        complexity: this.estimateComplexity(match[0]),
        hasTests: false,
        isExported: false,
        documentation: undefined,
        children: [],
      });
    }

    return methods;
  }

  /**
   * Extract block content starting from a given position
   */
  private static extractBlock(code: string, startIndex: number): string {
    let braceCount = 0;
    let inBlock = false;
    let i = startIndex;

    while (i < code.length) {
      const char = code[i];
      
      if (char === '{') {
        inBlock = true;
        braceCount++;
      } else if (char === '}') {
        braceCount--;
        if (inBlock && braceCount === 0) {
          return code.substring(startIndex, i + 1);
        }
      }
      
      i++;
    }

    return code.substring(startIndex);
  }

  /**
   * Estimate cyclomatic complexity
   */
  private static estimateComplexity(code: string): number {
    let complexity = 1; // Base complexity
    
    // Count decision points
    const decisions = (code.match(/if|else|case|catch|for|while|switch|\?\s*:/g) || []).length;
    complexity += decisions;
    
    // Count logical operators
    const logicalOps = (code.match(/&&|\|\||!/g) || []).length;
    complexity += Math.ceil(logicalOps / 2);

    return Math.min(complexity, 10); // Cap at 10
  }

  /**
   * Check if code element has test coverage
   */
  private static hasTestCoverage(elementName: string, code: string): boolean {
    const testPatterns = [
      `test('${elementName}'`,
      `it('${elementName}'`,
      `describe('${elementName}'`,
      `${elementName}.spec`,
      `${elementName}.test`,
    ];

    return testPatterns.some(pattern => code.includes(pattern));
  }

  /**
   * Check if element is exported
   */
  private static isExported(name: string, code: string): boolean {
    return new RegExp(`export\\s+(?:default\\s+)?(?:function|class|const)?\\s*${name}`).test(code);
  }

  /**
   * Extract JSDoc comment
   */
  private static extractDocumentation(code: string, beforeIndex: number): string | undefined {
    const jsdocRegex = /\/\*\*[\s\S]*?\*\//;
    const beforeCode = code.substring(Math.max(0, beforeIndex - 500), beforeIndex);
    const match = beforeCode.match(jsdocRegex);
    
    return match ? match[0] : undefined;
  }

  /**
   * Calculate code statistics
   */
  private static calculateStatistics(
    elements: CodeElement[],
    code: string
  ): CodeIndex['statistics'] {
    const functions = elements.filter(e => e.type === CodeElementType.FUNCTION);
    const classes = elements.filter(e => e.type === CodeElementType.CLASS);
    const documented = elements.filter(e => e.documentation !== undefined);

    const totalComplexity = elements.reduce((sum, e) => sum + e.complexity, 0);
    const averageComplexity = elements.length > 0 ? totalComplexity / elements.length : 0;

    return {
      totalFunctions: functions.length,
      totalClasses: classes.length,
      averageComplexity: Math.round(averageComplexity * 10) / 10,
      hasTests: !!code.match(/describe|test|it\(/),
      documentationRatio: elements.length > 0 ? documented.length / elements.length : 0,
    };
  }
}
