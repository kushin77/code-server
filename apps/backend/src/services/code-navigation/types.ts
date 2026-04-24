/**
 * Intelligent Code Navigation - Type Definitions
 * @file        apps/backend/src/services/code-navigation/types.ts
 * @module      services/code-navigation
 * @description Intelligent code navigation with symbols, references, and AI suggestions
 */

import { EventEmitter } from 'events';

/**
 * Code symbol
 */
export interface CodeSymbol {
  id: string;
  name: string;
  kind: SymbolKind;
  filePath: string;
  lineNumber: number;
  columnNumber: number;
  scope?: string;
  documentation?: string;
  deprecated: boolean;
  exported: boolean;
  visibility: 'public' | 'protected' | 'private' | 'internal';
  tags: string[];
  relatedSymbols: string[];
}

/**
 * Symbol kind
 */
export type SymbolKind =
  | 'class'
  | 'interface'
  | 'function'
  | 'method'
  | 'property'
  | 'variable'
  | 'constant'
  | 'enum'
  | 'module'
  | 'namespace'
  | 'package'
  | 'type'
  | 'field'
  | 'constructor'
  | 'decorator';

/**
 * Symbol reference
 */
export interface SymbolReference {
  id: string;
  symbolId: string;
  referencedSymbolId: string;
  filePath: string;
  lineNumber: number;
  columnNumber: number;
  kind: ReferenceKind;
  context: string;
  isDefinition: boolean;
  isImport: boolean;
  importPath?: string;
}

/**
 * Reference kind
 */
export type ReferenceKind =
  | 'definition'
  | 'usage'
  | 'import'
  | 'export'
  | 'inheritance'
  | 'implementation'
  | 'call'
  | 'instantiation';

/**
 * Symbol hierarchy
 */
export interface SymbolHierarchy {
  id: string;
  parentSymbolId?: string;
  childSymbolIds: string[];
  depth: number;
  ancestors: string[];
  descendants: string[];
}

/**
 * Navigation breadcrumb
 */
export interface NavigationBreadcrumb {
  symbol: CodeSymbol;
  path: CodeSymbol[];
  depth: number;
}

/**
 * Code reference with context
 */
export interface ReferenceWithContext {
  reference: SymbolReference;
  symbol: CodeSymbol;
  snippet: string;
  beforeLines: string[];
  afterLines: string[];
}

/**
 * Quick navigation suggestion
 */
export interface NavigationSuggestion {
  id: string;
  targetSymbolId: string;
  targetSymbol: CodeSymbol;
  confidence: number;
  reason: SuggestionReason;
  distance: number;
  recentlyVisited: boolean;
  frequentlyUsed: boolean;
  relatedToCurrentFile: boolean;
}

/**
 * Suggestion reason
 */
export type SuggestionReason =
  | 'same-module'
  | 'same-package'
  | 'imported-dependency'
  | 'related-functionality'
  | 'type-reference'
  | 'method-override'
  | 'interface-implementation'
  | 'recent-access'
  | 'frequently-used'
  | 'ai-recommended';

/**
 * Navigation context
 */
export interface NavigationContext {
  currentFilePath: string;
  currentLine: number;
  currentColumn: number;
  currentSymbol?: CodeSymbol;
  recentlyVisitedSymbols: string[];
  frequentlyUsedSymbols: string[];
  openFiles: string[];
}

/**
 * Search result
 */
export interface SearchResult {
  id: string;
  symbol: CodeSymbol;
  references: SymbolReference[];
  relevanceScore: number;
  matchType: 'name' | 'fuzzy' | 'regex' | 'semantic';
}

/**
 * Go to definition result
 */
export interface GoToDefinitionResult {
  success: boolean;
  symbol?: CodeSymbol;
  filePath?: string;
  lineNumber?: number;
  columnNumber?: number;
  alternativeLocations?: CodeSymbol[];
  error?: string;
}

/**
 * Find all references result
 */
export interface FindAllReferencesResult {
  success: boolean;
  references: ReferenceWithContext[];
  count: number;
  error?: string;
}

/**
 * Symbol statistics
 */
export interface SymbolStatistics {
  totalSymbols: number;
  symbolsByKind: Map<SymbolKind, number>;
  totalReferences: number;
  averageReferencesPerSymbol: number;
  mostReferencedSymbols: string[];
  publicSymbols: number;
  deprecatedSymbols: number;
  undocumentedSymbols: number;
}

/**
 * Navigation statistics
 */
export interface NavigationStatistics {
  totalNavigations: number;
  goToDefinitionCount: number;
  findReferencesCount: number;
  searchCount: number;
  averageNavigationTime: number;
  mostVisitedSymbols: string[];
  mostUsedNavigationPaths: string[][];
  uniqueUsers: number;
  uniqueFiles: number;
}

/**
 * Audit entry for navigation operations
 */
export interface NavigationAuditEntry {
  timestamp: number;
  userId: string;
  userEmail: string;
  ipAddress: string;
  userAgent: string;
  operation: NavigationOperation;
  filePath?: string;
  symbolId?: string;
  status: 'success' | 'failure';
  details: Map<string, unknown>;
}

/**
 * Navigation operation type
 */
export type NavigationOperation =
  | 'symbol-indexed'
  | 'symbol-updated'
  | 'symbol-deleted'
  | 'reference-found'
  | 'definition-located'
  | 'navigation-performed'
  | 'search-executed'
  | 'breadcrumb-tracked'
  | 'suggestion-generated';

/**
 * Service configuration
 */
export interface CodeNavigationConfig {
  maxSymbols: number;
  maxReferencesPerSymbol: number;
  searchResultLimit: number;
  suggestionLimit: number;
  enableAISuggestions: boolean;
  enableFuzzySearch: boolean;
  enableSemanticSearch: boolean;
  cacheNavigationHistory: boolean;
  maxNavigationHistory: number;
  maxAuditLogSize: number;
  retentionDays: number;
}

/**
 * Service interface
 */
export interface ICodeNavigationService extends EventEmitter {
  indexSymbol(
    symbol: CodeSymbol,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; symbolId?: string; error?: string };

  updateSymbol(
    symbolId: string,
    updates: Partial<CodeSymbol>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; symbol?: CodeSymbol; error?: string };

  deleteSymbol(
    symbolId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; error?: string };

  getSymbol(symbolId: string): { success: boolean; symbol?: CodeSymbol; error?: string };

  addReference(
    reference: SymbolReference,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; referenceId?: string; error?: string };

  findAllReferences(
    symbolId: string
  ): FindAllReferencesResult;

  goToDefinition(
    symbolId: string
  ): GoToDefinitionResult;

  findSymbols(
    query: string,
    options?: {
      kind?: SymbolKind[];
      filePath?: string;
      limit?: number;
      fuzzy?: boolean;
    }
  ): SearchResult[];

  searchSymbols(
    query: string,
    matchType: 'name' | 'fuzzy' | 'regex' | 'semantic'
  ): SearchResult[];

  getSymbolHierarchy(
    symbolId: string
  ): { success: boolean; hierarchy?: SymbolHierarchy; error?: string };

  getNavigationBreadcrumb(
    symbolId: string
  ): { success: boolean; breadcrumb?: NavigationBreadcrumb; error?: string };

  getSuggestions(
    context: NavigationContext
  ): NavigationSuggestion[];

  trackNavigation(
    fromSymbolId: string,
    toSymbolId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; error?: string };

  getNavigationHistory(
    userId: string,
    limit?: number
  ): string[];

  getStatistics(): NavigationStatistics;

  updateConfig(
    config: Partial<CodeNavigationConfig>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): void;

  shutdown(): void;
}
