/**
 * Real-time Code Lens Provider Types
 * @file        apps/backend/src/services/code-lens-provider/types.ts
 * @module      services/code-lens-provider
 * @description Type definitions for real-time code lens functionality
 */

/**
 * Code lens position in file
 */
export interface CodeLensPosition {
  line: number;
  column: number;
}

/**
 * Code lens metadata
 */
export interface CodeLensMetadata {
  lensId: string;
  fileId: string;
  position: CodeLensPosition;
  title: string;
  command?: string;
  arguments?: unknown[];
  tooltip?: string;
  isResolved: boolean;
  resolvedAt?: number;
  data?: Record<string, unknown>;
}

/**
 * Code lens reference
 */
export interface CodeLensReference {
  referenceId: string;
  lensId: string;
  referencingFile: string;
  referencingPosition: CodeLensPosition;
  referenceType: 'definition' | 'implementation' | 'reference' | 'type-definition';
  isWeakReference: boolean;
}

/**
 * Code lens statistics
 */
export interface CodeLensStatistics {
  totalLenses: number;
  resolvedLenses: number;
  unresolvedLenses: number;
  totalReferences: number;
  averageReferencesPerLens: number;
  lensCount: { [key: string]: number };
}

/**
 * Code lens range
 */
export interface CodeLensRange {
  startLine: number;
  endLine: number;
  startColumn?: number;
  endColumn?: number;
}

/**
 * Code lens batch update
 */
export interface CodeLensBatchUpdate {
  updateId: string;
  fileId: string;
  addedLenses: CodeLensMetadata[];
  removedLenses: string[]; // lensIds
  updatedLenses: CodeLensMetadata[];
  timestamp: number;
}

/**
 * Code lens command execution
 */
export interface CodeLensCommandExecution {
  executionId: string;
  lensId: string;
  command: string;
  arguments: unknown[];
  executedBy: string;
  executedAt: number;
  result?: unknown;
  error?: string;
}

/**
 * Code lens performance metric
 */
export interface CodeLensPerformanceMetric {
  lensId: string;
  resolutionTimeMs: number;
  referenceCountTime: number;
  totalComputeTime: number;
}

/**
 * Code lens invalidation
 */
export interface CodeLensInvalidation {
  invalidationId: string;
  fileId: string;
  reason: 'file-changed' | 'dependency-changed' | 'manual' | 'cache-expired';
  affectedLenses: string[];
  invalidatedAt: number;
}

/**
 * Code lens cache entry
 */
export interface CodeLensCacheEntry {
  lensId: string;
  lensMetadata: CodeLensMetadata;
  references: CodeLensReference[];
  computedAt: number;
  expiresAt: number;
  hitCount: number;
}

/**
 * Code lens audit entry
 */
export interface CodeLensAuditEntry {
  timestamp: number;
  userId: string;
  userEmail: string;
  action: string;
  fileId: string;
  details: Record<string, unknown>;
}

/**
 * Code Lens Provider configuration
 */
export interface CodeLensConfig {
  enableCodeLens: boolean;
  enableReferenceCounting: boolean;
  enableImplementationLens: boolean;
  cacheExpirationMs: number;
  batchUpdateThreshold: number;
  maxLensesPerFile: number;
  maxAuditEntries: number;
  performanceTrackingEnabled: boolean;
}

/**
 * Code Lens Provider Service interface
 */
export interface ICodeLensService {
  // Lens management
  createCodeLens(metadata: Omit<CodeLensMetadata, 'lensId' | 'isResolved'>, userId: string, ipAddress: string, userAgent: string): { success: boolean; lensId?: string };
  updateCodeLens(lensId: string, updates: Partial<CodeLensMetadata>, userId: string, ipAddress: string, userAgent: string): { success: boolean };
  deleteCodeLens(lensId: string, userId: string, ipAddress: string, userAgent: string): { success: boolean };
  getCodeLens(lensId: string): CodeLensMetadata | undefined;

  // Lens resolution
  resolveCodeLens(lensId: string, userId: string, ipAddress: string, userAgent: string): { success: boolean; metadata?: CodeLensMetadata };
  resolveLensesInFile(fileId: string, userId: string, ipAddress: string, userAgent: string): { success: boolean; resolvedCount?: number };
  unresolveCodeLens(lensId: string, userId: string, ipAddress: string, userAgent: string): { success: boolean };

  // Lens queries
  getCodeLensesInFile(fileId: string): CodeLensMetadata[];
  getCodeLensesInRange(fileId: string, range: CodeLensRange): CodeLensMetadata[];
  getUnresolvedLenses(fileId?: string): CodeLensMetadata[];

  // References
  addReference(reference: Omit<CodeLensReference, 'referenceId'>, userId: string, ipAddress: string, userAgent: string): { success: boolean; referenceId?: string };
  getReferencesForLens(lensId: string): CodeLensReference[];
  updateReferenceCounts(lensId: string, userId: string, ipAddress: string, userAgent: string): { success: boolean; count?: number };
  removeReference(referenceId: string, userId: string, ipAddress: string, userAgent: string): { success: boolean };

  // Batch operations
  batchUpdate(update: Omit<CodeLensBatchUpdate, 'updateId' | 'timestamp'>, userId: string, ipAddress: string, userAgent: string): { success: boolean; updateId?: string };
  getFileLenses(fileId: string): CodeLensMetadata[];

  // Command execution
  executeCommand(lensId: string, command: string, args: unknown[], userId: string, ipAddress: string, userAgent: string): { success: boolean; executionId?: string; result?: unknown };
  getCommandHistory(lensId?: string, limit?: number): CodeLensCommandExecution[];

  // Cache management
  invalidateCache(fileId: string, reason: string, userId: string, ipAddress: string, userAgent: string): { success: boolean };
  getCacheHitRate(): number;
  clearCache(userId: string, ipAddress: string, userAgent: string): { success: boolean };

  // Performance monitoring
  getPerformanceMetrics(lensId?: string): CodeLensPerformanceMetric[];
  recordPerformanceMetric(metric: CodeLensPerformanceMetric): void;

  // Statistics
  getStatistics(fileId?: string): CodeLensStatistics;
  getAuditLog(limit?: number): CodeLensAuditEntry[];

  // Configuration
  updateConfig(config: Partial<CodeLensConfig>): void;
  getConfig(): CodeLensConfig;

  // Lifecycle
  shutdown(): void;
}
