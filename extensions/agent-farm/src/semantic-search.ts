/**
 * Semantic Code Search
 * 
 * Enables finding code by meaning/intent rather than just text patterns.
 * Indexes code elements and supports queries like "find error handling" or "find data validation".
 */

import * as vscode from 'vscode';
import { CodeElement, CodeElementType, CodeIndex } from './types';

interface SemanticSearchResult {
  element: CodeElement;
  relevanceScore: number; // 0-100
  matchType: 'name' | 'documentation' | 'context' | 'pattern';
  explanation: string;
}

/**
 * Semantic code search using meaning-based matching
 */
export class SemanticCodeSearchEngine {
  private semanticPatterns: Map<string, RegExp[]>;
  private intentPatterns: Map<string, string[]>;
  private outputChannel: vscode.OutputChannel;

  constructor() {
    this.outputChannel = vscode.window.createOutputChannel('Agent Farm: Semantic Search');
    this.semanticPatterns = this.initializePatterns();
    this.intentPatterns = this.initializeIntents();
  }

  /**
   * Search for code matching a semantic query
   */
  search(
    codeIndex: CodeIndex,
    query: string,
    limit: number = 10
  ): SemanticSearchResult[] {
    const normalizedQuery = query.toLowerCase();
    const results: SemanticSearchResult[] = [];

    // Search through all code elements
    for (const element of codeIndex.elements) {
      const score = this.scoreElement(element, normalizedQuery);
      if (score > 0) {
        results.push({
          element,
          relevanceScore: score,
          matchType: this.determineMatchType(element, normalizedQuery),
          explanation: this.generateExplanation(element, query),
        });
      }
    }

    // Sort by relevance and return top results
    results.sort((a, b) => b.relevanceScore - a.relevanceScore);
    
    this.log(`Search for "${query}" found ${results.length} results`);
    return results.slice(0, limit);
  }

  /**
   * Find patterns of a specific semantic category
   */
  findPattern(
    code: string,
    pattern: 'error-handling' | 'validation' | 'async-operations' | 'type-guards' | 'data-transformation'
  ): Array<{ line: number; code: string; explanation: string }> {
    const patterns = this.semanticPatterns.get(pattern) || [];
    const results: Array<{ line: number; code: string; explanation: string }> = [];

    const lines = code.split('\n');
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      
      for (const regex of patterns) {
        if (regex.test(line)) {
          results.push({
            line: i + 1,
            code: line.trim(),
            explanation: `Found ${pattern.replace('-', ' ')}: ${line.trim().substring(0, 60)}...`,
          });
        }
      }
    }

    return results;
  }

  /**
   * Find intent-based concepts (things things the code tries to do)
   */
  findIntent(code: string, intent: string): Array<{ line: number; reason: string }> {
    const normalizedIntent = intent.toLowerCase();
    const keywords = this.intentPatterns.get(normalizedIntent) || [];
    const results: Array<{ line: number; reason: string }> = [];

    const lines = code.split('\n');
    const foundLines = new Set<number>();

    for (const keyword of keywords) {
      const regex = new RegExp(`\\b${keyword}\\b`, 'gi');
      for (let i = 0; i < lines.length; i++) {
        if (regex.test(lines[i]) && !foundLines.has(i)) {
          foundLines.add(i);
          results.push({
            line: i + 1,
            reason: `Detected by keyword: "${keyword}" (intent: ${normalizedIntent})`,
          });
        }
      }
    }

    return results;
  }

  /**
   * Score element relevance to query
   */
  private scoreElement(element: CodeElement, query: string): number {
    let score = 0;

    // Exact name match
    if (element.name.toLowerCase() === query) {
      score += 100;
    }
    // Partial name match
    else if (element.name.toLowerCase().includes(query)) {
      score += 70;
    }

    // Documentation match
    if (element.documentation) {
      const docLower = element.documentation.toLowerCase();
      if (docLower.includes(query)) {
        score += 50;
      }
      // Semantic matching on documentation
      const semanticScore = this.scoreSemanticSimilarity(docLower, query);
      score += semanticScore * 20;
    }

    // Type/context relevance
    if (element.type === CodeElementType.FUNCTION && query.includes('function')) {
      score += 15;
    }

    return Math.min(100, score);
  }

  /**
   * Calculate semantic similarity between two text strings
   */
  private scoreSemanticSimilarity(text: string, query: string): number {
    const words = new Set(text.split(/\W+/).filter(w => w.length > 2));
    const queryWords = new Set(query.split(/\W+/).filter(w => w.length > 2));

    let matches = 0;
    for (const word of queryWords) {
      if (words.has(word)) {
        matches++;
      }
    }

    return matches / Math.max(1, queryWords.size);
  }

  /**
   * Determine what type of match occurred
   */
  private determineMatchType(
    element: CodeElement,
    query: string
  ): 'name' | 'documentation' | 'context' | 'pattern' {
    if (element.name.toLowerCase().includes(query)) {
      return 'name';
    }
    if (element.documentation?.toLowerCase().includes(query)) {
      return 'documentation';
    }
    return 'pattern';
  }

  /**
   * Generate human-readable explanation of match
   */
  private generateExplanation(element: CodeElement, query: string): string {
    const type = element.type === CodeElementType.FUNCTION ? 'function' : 
                 element.type === CodeElementType.CLASS ? 'class' : 
                 element.type;

    return `${type} "${element.name}" matches query "${query}"${
      element.documentation ? ` - ${element.documentation.substring(0, 50)}...` : ''
    }`;
  }

  /**
   * Initialize semantic pattern detection
   */
  private initializePatterns(): Map<string, RegExp[]> {
    return new Map([
      ['error-handling', [
        /try\s*{/g,
        /catch\s*\(/g,
        /throw\s+(new\s+)?\w+Error/g,
        /\.catch\(/g,
        /\.then\(\s*\w+\s*,\s*\w+\)/g,
        /if\s*\(\s*!?\w+\s*instanceof\s+Error\)/g,
      ]],
      ['validation', [
        /if\s*\(\s*!?\w+\s*\)/g,
        /validate|validate|schema|constraint/gi,
        /assert|check|verify/gi,
        /typeof\s+\w+\s*===|instanceof/g,
        /throw.*Error.*(?:invalid|required|malformed)/gi,
      ]],
      ['async-operations', [
        /async\s+(?:function|\w+\s*\()/g,
        /await\s+\w+/g,
        /Promise\s*</g,
        /\.\s*then\(/g,
        /\.\s*finally\(/g,
      ]],
      ['type-guards', [
        /typeof\s+\w+\s*===\s*['"](?:string|number|boolean|object|undefined)['"]/, 
        /Array\.isArray\(/g,
        /\w+\s+instanceof\s+\w+/g,
        /in\s+\w+/g,
        /hasOwnProperty/g,
      ]],
      ['data-transformation', [
        /\.map\(/g,
        /\.filter\(/g,
        /\.reduce\(/g,
        /\.flatMap\(/g,
        /Object\.keys|Object\.values|Object\.entries/g,
        /JSON\.(stringify|parse)/g,
      ]],
    ]);
  }

  /**
   * Initialize intent-based keyword matching
   */
  private initializeIntents(): Map<string, string[]> {
    return new Map([
      ['error handling', [
        'try', 'catch', 'throw', 'error', 'exception', 'handle', 'recover'
      ]],
      ['validation', [
        'validate', 'check', 'verify', 'assert', 'require', 'constraint', 'schema'
      ]],
      ['async processing', [
        'async', 'await', 'promise', 'then', 'catch', 'finally', 'resolve'
      ]],
      ['logging', [
        'log', 'debug', 'info', 'warn', 'error', 'trace', 'logger'
      ]],
      ['caching', [
        'cache', 'memoize', 'memo', 'store', 'lookup', 'fetch'
      ]],
      ['performance', [
        'optimize', 'performance', 'efficient', 'fast', 'slow', 'benchmark', 'profile'
      ]],
      ['security', [
        'authenticate', 'authorize', 'permission', 'role', 'token', 'credential', 'encrypt', 'sanitize'
      ]],
    ]);
  }

  /**
   * Log message to output channel
   */
  private log(message: string): void {
    this.outputChannel.appendLine(`[${new Date().toISOString()}] ${message}`);
  }

  /**
   * Show output channel
   */
  showOutput(): void {
    this.outputChannel.show();
  }
}
