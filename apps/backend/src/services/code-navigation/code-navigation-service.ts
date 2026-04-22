/**
 * Intelligent Code Navigation Service
 * @file        apps/backend/src/services/code-navigation/code-navigation-service.ts
 * @module      services/code-navigation
 * @description Intelligent code navigation with symbols, references, and AI suggestions
 */

import { EventEmitter } from 'events';
import {
  CodeSymbol,
  SymbolReference,
  SymbolHierarchy,
  NavigationBreadcrumb,
  ReferenceWithContext,
  NavigationSuggestion,
  SearchResult,
  GoToDefinitionResult,
  FindAllReferencesResult,
  SymbolStatistics,
  NavigationStatistics,
  NavigationAuditEntry,
  NavigationContext,
  ICodeNavigationService,
  CodeNavigationConfig,
  SymbolKind,
} from './types.js';

/**
 * Intelligent Code Navigation Service
 */
export class CodeNavigationService extends EventEmitter implements ICodeNavigationService {
  private static instance: CodeNavigationService;

  private symbols: Map<string, CodeSymbol>;
  private symbolsByFile: Map<string, Set<string>>;
  private references: Map<string, SymbolReference>;
  private referencesBySymbol: Map<string, Set<string>>;
  private hierarchies: Map<string, SymbolHierarchy>;
  private navigationHistory: Map<string, string[]>;
  private auditLogs: Map<string, NavigationAuditEntry[]>;
  private config: CodeNavigationConfig;
  private navigationStats: NavigationStatistics;

  private constructor() {
    super();
    this.symbols = new Map();
    this.symbolsByFile = new Map();
    this.references = new Map();
    this.referencesBySymbol = new Map();
    this.hierarchies = new Map();
    this.navigationHistory = new Map();
    this.auditLogs = new Map();

    this.config = {
      maxSymbols: 50000,
      maxReferencesPerSymbol: 1000,
      searchResultLimit: 100,
      suggestionLimit: 10,
      enableAISuggestions: true,
      enableFuzzySearch: true,
      enableSemanticSearch: true,
      cacheNavigationHistory: true,
      maxNavigationHistory: 1000,
      maxAuditLogSize: 10000,
      retentionDays: 365,
    };

    this.navigationStats = {
      totalNavigations: 0,
      goToDefinitionCount: 0,
      findReferencesCount: 0,
      searchCount: 0,
      averageNavigationTime: 0,
      mostVisitedSymbols: [],
      mostUsedNavigationPaths: [],
      uniqueUsers: 0,
      uniqueFiles: 0,
    };

    this.initialize();
  }

  /**
   * Get or create service instance
   */
  static getInstance(config?: Partial<CodeNavigationConfig>): CodeNavigationService {
    if (!CodeNavigationService.instance) {
      CodeNavigationService.instance = new CodeNavigationService();
    }
    if (config) {
      CodeNavigationService.instance.updateConfig(config, 'system', '127.0.0.1', 'node');
    }
    return CodeNavigationService.instance;
  }

  /**
   * Reset instance for testing
   */
  static reset(): void {
    if (CodeNavigationService.instance) {
      CodeNavigationService.instance.shutdown();
    }
    CodeNavigationService.instance = null as any;
  }

  /**
   * Initialize service
   */
  private initialize(): void {
    this.emit('initialized', {
      data_object: { service: 'code-navigation', status: 'initialized' },
      timestamp: Date.now(),
    });
  }

  /**
   * Index symbol
   */
  indexSymbol(
    symbol: CodeSymbol,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; symbolId?: string; error?: string } {
    try {
      const symbolId = symbol.id || `sym-${Date.now()}-${Math.random().toString(16).slice(2)}`;
      const indexedSymbol: CodeSymbol = { ...symbol, id: symbolId };

      this.symbols.set(symbolId, indexedSymbol);

      if (!this.symbolsByFile.has(symbol.filePath)) {
        this.symbolsByFile.set(symbol.filePath, new Set());
      }
      this.symbolsByFile.get(symbol.filePath)!.add(symbolId);

      // Create hierarchy
      if (!this.hierarchies.has(symbolId)) {
        this.hierarchies.set(symbolId, {
          id: symbolId,
          childSymbolIds: [],
          depth: 0,
          ancestors: [],
          descendants: [],
        });
      }

      this.emit('symbol-indexed', {
        data_object: { symbolId, name: symbol.name, kind: symbol.kind },
        timestamp: Date.now(),
      });

      this.logAudit(
        userId,
        `${userId}@example.com`,
        ipAddress,
        userAgent,
        'symbol-indexed',
        symbol.filePath,
        symbolId,
        { name: symbol.name, kind: symbol.kind }
      );

      return { success: true, symbolId };
    } catch (error) {
      return { success: false, error: (error as Error).message };
    }
  }

  /**
   * Update symbol
   */
  updateSymbol(
    symbolId: string,
    updates: Partial<CodeSymbol>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; symbol?: CodeSymbol; error?: string } {
    try {
      const symbol = this.symbols.get(symbolId);
      if (!symbol) {
        return { success: false, error: 'Symbol not found' };
      }

      Object.assign(symbol, updates);

      this.emit('symbol-updated', {
        data_object: { symbolId, updates },
        timestamp: Date.now(),
      });

      this.logAudit(
        userId,
        `${userId}@example.com`,
        ipAddress,
        userAgent,
        'symbol-updated',
        symbol.filePath,
        symbolId,
        updates
      );

      return { success: true, symbol };
    } catch (error) {
      return { success: false, error: (error as Error).message };
    }
  }

  /**
   * Delete symbol
   */
  deleteSymbol(
    symbolId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; error?: string } {
    try {
      const symbol = this.symbols.get(symbolId);
      if (!symbol) {
        return { success: false, error: 'Symbol not found' };
      }

      this.symbols.delete(symbolId);
      this.symbolsByFile.get(symbol.filePath)?.delete(symbolId);
      this.hierarchies.delete(symbolId);
      this.referencesBySymbol.delete(symbolId);

      this.emit('symbol-deleted', {
        data_object: { symbolId },
        timestamp: Date.now(),
      });

      this.logAudit(
        userId,
        `${userId}@example.com`,
        ipAddress,
        userAgent,
        'symbol-deleted',
        symbol.filePath,
        symbolId,
        {}
      );

      return { success: true };
    } catch (error) {
      return { success: false, error: (error as Error).message };
    }
  }

  /**
   * Get symbol
   */
  getSymbol(symbolId: string): { success: boolean; symbol?: CodeSymbol; error?: string } {
    try {
      const symbol = this.symbols.get(symbolId);
      if (!symbol) {
        return { success: false, error: 'Symbol not found' };
      }
      return { success: true, symbol };
    } catch (error) {
      return { success: false, error: (error as Error).message };
    }
  }

  /**
   * Add reference
   */
  addReference(
    reference: SymbolReference,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; referenceId?: string; error?: string } {
    try {
      const refId = reference.id || `ref-${Date.now()}-${Math.random().toString(16).slice(2)}`;
      const newRef: SymbolReference = { ...reference, id: refId };

      this.references.set(refId, newRef);

      if (!this.referencesBySymbol.has(reference.symbolId)) {
        this.referencesBySymbol.set(reference.symbolId, new Set());
      }
      this.referencesBySymbol.get(reference.symbolId)!.add(refId);

      this.emit('reference-found', {
        data_object: { referenceId: refId, symbolId: reference.symbolId },
        timestamp: Date.now(),
      });

      this.logAudit(
        userId,
        `${userId}@example.com`,
        ipAddress,
        userAgent,
        'reference-found',
        reference.filePath,
        reference.symbolId,
        { referencedSymbolId: reference.referencedSymbolId }
      );

      return { success: true, referenceId: refId };
    } catch (error) {
      return { success: false, error: (error as Error).message };
    }
  }

  /**
   * Find all references
   */
  findAllReferences(symbolId: string): FindAllReferencesResult {
    try {
      const referenceIds = this.referencesBySymbol.get(symbolId) || new Set();
      const references: ReferenceWithContext[] = [];

      referenceIds.forEach((refId) => {
        const reference = this.references.get(refId);
        const symbol = this.symbols.get(reference?.referencedSymbolId || '');

        if (reference && symbol) {
          references.push({
            reference,
            symbol,
            snippet: `Line ${reference.lineNumber}: ${reference.context}`,
            beforeLines: [],
            afterLines: [],
          });
        }
      });

      this.navigationStats.findReferencesCount++;

      this.emit('definition-located', {
        data_object: { symbolId, referenceCount: references.length },
        timestamp: Date.now(),
      });

      return { success: true, references, count: references.length };
    } catch (error) {
      return { success: false, references: [], count: 0, error: (error as Error).message };
    }
  }

  /**
   * Go to definition
   */
  goToDefinition(symbolId: string): GoToDefinitionResult {
    try {
      const symbol = this.symbols.get(symbolId);
      if (!symbol) {
        return { success: false, error: 'Symbol not found' };
      }

      this.navigationStats.goToDefinitionCount++;

      return {
        success: true,
        symbol,
        filePath: symbol.filePath,
        lineNumber: symbol.lineNumber,
        columnNumber: symbol.columnNumber,
      };
    } catch (error) {
      return { success: false, error: (error as Error).message };
    }
  }

  /**
   * Find symbols
   */
  findSymbols(
    query: string,
    options?: {
      kind?: SymbolKind[];
      filePath?: string;
      limit?: number;
      fuzzy?: boolean;
    }
  ): SearchResult[] {
    try {
      let candidates = Array.from(this.symbols.values());

      if (options?.filePath) {
        candidates = candidates.filter((s) => s.filePath === options.filePath);
      }

      if (options?.kind) {
        candidates = candidates.filter((s) => options.kind!.includes(s.kind));
      }

      const results = candidates
        .filter((s) => {
          if (options?.fuzzy) {
            return this.fuzzyMatch(query, s.name);
          }
          return s.name.includes(query);
        })
        .slice(0, options?.limit || this.config.searchResultLimit)
        .map((symbol) => ({
          id: `result-${Date.now()}-${Math.random().toString(16).slice(2)}`,
          symbol,
          references: Array.from(
            this.referencesBySymbol.get(symbol.id) || new Set()
          ).map((refId) => this.references.get(refId)!),
          relevanceScore: query === symbol.name ? 1.0 : 0.5,
          matchType: 'name' as const,
        }));

      this.navigationStats.searchCount++;

      return results;
    } catch (error) {
      return [];
    }
  }

  /**
   * Search symbols
   */
  searchSymbols(query: string, matchType: 'name' | 'fuzzy' | 'regex' | 'semantic'): SearchResult[] {
    try {
      let candidates = Array.from(this.symbols.values());

      switch (matchType) {
        case 'name':
          candidates = candidates.filter((s) => s.name === query);
          break;
        case 'fuzzy':
          candidates = candidates.filter((s) => this.fuzzyMatch(query, s.name));
          break;
        case 'regex':
          try {
            const regex = new RegExp(query);
            candidates = candidates.filter((s) => regex.test(s.name));
          } catch {
            // Invalid regex
          }
          break;
        case 'semantic':
          candidates = candidates.filter((s) => {
            const similarity = this.calculateSimilarity(query, s.name);
            return similarity > 0.6;
          });
          break;
      }

      const results = candidates
        .slice(0, this.config.searchResultLimit)
        .map((symbol) => ({
          id: `result-${Date.now()}-${Math.random().toString(16).slice(2)}`,
          symbol,
          references: Array.from(
            this.referencesBySymbol.get(symbol.id) || new Set()
          ).map((refId) => this.references.get(refId)!),
          relevanceScore: this.calculateSimilarity(query, symbol.name),
          matchType,
        }));

      return results;
    } catch (error) {
      return [];
    }
  }

  /**
   * Get symbol hierarchy
   */
  getSymbolHierarchy(
    symbolId: string
  ): { success: boolean; hierarchy?: SymbolHierarchy; error?: string } {
    try {
      const hierarchy = this.hierarchies.get(symbolId);
      if (!hierarchy) {
        return { success: false, error: 'Hierarchy not found' };
      }
      return { success: true, hierarchy };
    } catch (error) {
      return { success: false, error: (error as Error).message };
    }
  }

  /**
   * Get navigation breadcrumb
   */
  getNavigationBreadcrumb(
    symbolId: string
  ): { success: boolean; breadcrumb?: NavigationBreadcrumb; error?: string } {
    try {
      const symbol = this.symbols.get(symbolId);
      if (!symbol) {
        return { success: false, error: 'Symbol not found' };
      }

      const path = [symbol];
      const breadcrumb: NavigationBreadcrumb = {
        symbol,
        path,
        depth: 1,
      };

      return { success: true, breadcrumb };
    } catch (error) {
      return { success: false, error: (error as Error).message };
    }
  }

  /**
   * Get suggestions
   */
  getSuggestions(context: NavigationContext): NavigationSuggestion[] {
    try {
      const suggestions: NavigationSuggestion[] = [];

      Array.from(this.symbols.values())
        .slice(0, this.config.suggestionLimit)
        .forEach((symbol) => {
          suggestions.push({
            id: `sugg-${Date.now()}-${Math.random().toString(16).slice(2)}`,
            targetSymbolId: symbol.id,
            targetSymbol: symbol,
            confidence: 0.7,
            reason: 'same-module',
            distance: 1,
            recentlyVisited: context.recentlyVisitedSymbols.includes(symbol.id),
            frequentlyUsed: context.frequentlyUsedSymbols.includes(symbol.id),
            relatedToCurrentFile: symbol.filePath === context.currentFilePath,
          });
        });

      return suggestions;
    } catch (error) {
      return [];
    }
  }

  /**
   * Track navigation
   */
  trackNavigation(
    fromSymbolId: string,
    toSymbolId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; error?: string } {
    try {
      if (!this.navigationHistory.has(userId)) {
        this.navigationHistory.set(userId, []);
      }

      const history = this.navigationHistory.get(userId)!;
      history.push(toSymbolId);

      if (history.length > this.config.maxNavigationHistory) {
        history.shift();
      }

      this.navigationStats.totalNavigations++;

      this.emit('navigation-performed', {
        data_object: { fromSymbolId, toSymbolId, userId },
        timestamp: Date.now(),
      });

      return { success: true };
    } catch (error) {
      return { success: false, error: (error as Error).message };
    }
  }

  /**
   * Get navigation history
   */
  getNavigationHistory(userId: string, limit?: number): string[] {
    try {
      const history = this.navigationHistory.get(userId) || [];
      return history.slice(-(limit || 50));
    } catch {
      return [];
    }
  }

  /**
   * Get statistics
   */
  getStatistics(): NavigationStatistics {
    const symbolsByKind = new Map<SymbolKind, number>();
    Array.from(this.symbols.values()).forEach((s) => {
      symbolsByKind.set(s.kind, (symbolsByKind.get(s.kind) || 0) + 1);
    });

    const uniqueFiles = new Set(Array.from(this.symbols.values()).map((s) => s.filePath))
      .size;

    return {
      totalNavigations: this.navigationStats.totalNavigations,
      goToDefinitionCount: this.navigationStats.goToDefinitionCount,
      findReferencesCount: this.navigationStats.findReferencesCount,
      searchCount: this.navigationStats.searchCount,
      averageNavigationTime: 0,
      mostVisitedSymbols: [],
      mostUsedNavigationPaths: [],
      uniqueUsers: this.navigationHistory.size,
      uniqueFiles,
    };
  }

  /**
   * Update configuration
   */
  updateConfig(
    config: Partial<CodeNavigationConfig>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): void {
    this.config = { ...this.config, ...config };

    this.emit('config-updated', {
      data_object: { userId, config },
      timestamp: Date.now(),
    });

    this.logAudit(userId, `${userId}@example.com`, ipAddress, userAgent, 'symbol-indexed', '', '', {
      configUpdate: config,
    });
  }

  /**
   * Fuzzy match
   */
  private fuzzyMatch(query: string, text: string): boolean {
    let queryIndex = 0;
    let textIndex = 0;

    while (queryIndex < query.length && textIndex < text.length) {
      if (query[queryIndex].toLowerCase() === text[textIndex].toLowerCase()) {
        queryIndex++;
      }
      textIndex++;
    }

    return queryIndex === query.length;
  }

  /**
   * Calculate similarity
   */
  private calculateSimilarity(a: string, b: string): number {
    const len = Math.max(a.length, b.length);
    const matches = a.split('').filter((char, i) => char === b[i]).length;
    return matches / len;
  }

  /**
   * Log audit entry
   */
  private logAudit(
    userId: string,
    userEmail: string,
    ipAddress: string,
    userAgent: string,
    operation: any,
    filePath: string | undefined,
    symbolId: string | undefined,
    details: any
  ): void {
    const entry: NavigationAuditEntry = {
      timestamp: Date.now(),
      userId,
      userEmail,
      ipAddress,
      userAgent,
      operation,
      filePath,
      symbolId,
      status: 'success',
      details: new Map(Object.entries(details)),
    };

    if (!this.auditLogs.has(userId)) {
      this.auditLogs.set(userId, []);
    }

    const logs = this.auditLogs.get(userId)!;
    logs.push(entry);

    if (logs.length > this.config.maxAuditLogSize) {
      logs.splice(0, logs.length - this.config.maxAuditLogSize);
    }

    this.emit('audit-logged', {
      data_object: { userId, operation, status: 'success' },
      timestamp: Date.now(),
    });
  }

  /**
   * Shutdown service
   */
  shutdown(): void {
    this.symbols.clear();
    this.symbolsByFile.clear();
    this.references.clear();
    this.referencesBySymbol.clear();
    this.hierarchies.clear();
    this.navigationHistory.clear();
    this.auditLogs.clear();

    this.emit('shutdown', {
      data_object: { service: 'code-navigation', status: 'shutdown' },
      timestamp: Date.now(),
    });

    this.removeAllListeners();
  }
}
