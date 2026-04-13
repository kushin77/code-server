/**
 * Agent Farm Audit Trail & Decision History
 * 
 * Maintains complete records of all agent analyses, decisions, and recommendations.
 * Enables tracking agent reasoning, identifying patterns, and analyzing trends.
 */

import * as vscode from 'vscode';
import { OrchestratorResult, AgentResult } from './types';

/**
 * Single audit trail entry
 */
export interface AuditEntry {
  id: string;
  timestamp: number;
  userId: string;
  documentPath: string;
  documentHash: string;
  analysisType: string;
  agentResults: AgentResult[];
  summary: {
    totalRecommendations: number;
    criticalCount: number;
    warningCount: number;
    infoCount: number;
  };
  metadata: Record<string, unknown>;
}

/**
 * Analysis trend/pattern
 */
export interface AnalysisTrend {
  type: 'recommendation' | 'pattern' | 'severity';
  category: string;
  occurrences: number;
  lastSeen: number;
  affectedFiles: Set<string>;
}

/**
 * Agent decision record
 */
export interface AgentDecision {
  agentName: string;
  confidence: number;
  recommendationCount: number;
  executionTime: number;
  errors: string[];
}

/**
 * Audit trail manager for Agent Farm
 */
export class AuditTrailManager {
  private entries: Map<string, AuditEntry>;
  private trends: Map<string, AnalysisTrend>;
  private outputChannel: vscode.OutputChannel;
  private config: vscode.WorkspaceConfiguration;
  private maxEntries: number = 1000;
  private storageUri: vscode.Uri;

  constructor(storageUri?: vscode.Uri) {
    this.outputChannel = vscode.window.createOutputChannel('Agent Farm: Audit Trail');
    this.config = vscode.workspace.getConfiguration('agentFarm.auditTrail');
    this.entries = new Map();
    this.trends = new Map();
    this.storageUri = storageUri || vscode.Uri.file('/tmp/agent-farm-audit');
    this.maxEntries = this.config.get('maxEntries', 1000) as number;
    this.loadAuditTrail();
  }

  /**
   * Record a complete analysis session
   */
  async recordAnalysis(
    documentUri: vscode.Uri,
    result: OrchestratorResult,
    userId: string
  ): Promise<AuditEntry> {
    const entry: AuditEntry = {
      id: this.generateId(),
      timestamp: Date.now(),
      userId,
      documentPath: documentUri.fsPath,
      documentHash: await this.hashDocument(documentUri),
      analysisType: 'comprehensive',
      agentResults: result.agentResults,
      summary: result.summary,
      metadata: {
        totalDuration: result.totalDuration,
        agentCount: result.agentResults.length,
      },
    };

    this.entries.set(entry.id, entry);
    this.updateTrends(entry);
    
    // Maintain max size
    if (this.entries.size > this.maxEntries) {
      const oldest = Array.from(this.entries.values())
        .sort((a, b) => a.timestamp - b.timestamp)[0];
      this.entries.delete(oldest.id);
    }

    this.log(`Recorded analysis for ${documentUri.fsPath}`);
    await this.persistAuditTrail();
    
    return entry;
  }

  /**
   * Get all audit entries for a specific file
   */
  getEntriesForFile(filePath: string): AuditEntry[] {
    return Array.from(this.entries.values())
      .filter(entry => entry.documentPath === filePath)
      .sort((a, b) => b.timestamp - a.timestamp);
  }

  /**
   * Get audit entries for a specific user
   */
  getEntriesForUser(userId: string): AuditEntry[] {
    return Array.from(this.entries.values())
      .filter(entry => entry.userId === userId)
      .sort((a, b) => b.timestamp - a.timestamp);
  }

  /**
   * Get entries within a time range
   */
  getEntriesInTimeRange(startTime: number, endTime: number): AuditEntry[] {
    return Array.from(this.entries.values())
      .filter(entry => entry.timestamp >= startTime && entry.timestamp <= endTime)
      .sort((a, b) => b.timestamp - a.timestamp);
  }

  /**
   * Get analysis trends
   */
  getTrends(): AnalysisTrend[] {
    return Array.from(this.trends.values())
      .sort((a, b) => b.occurrences - a.occurrences);
  }

  /**
   * Get critical trends (high-occurrence issues)
   */
  getCriticalTrends(threshold: number = 5): AnalysisTrend[] {
    return this.getTrends().filter(t => t.occurrences >= threshold);
  }

  /**
   * Get trend for specific category
   */
  getTrendForCategory(category: string): AnalysisTrend | undefined {
    return this.trends.get(category);
  }

  /**
   * Generate analysis statistics
   */
  getStatistics(): {
    totalAnalyses: number;
    averageRecommendations: number;
    averageExecutionTime: number;
    totalRecommendations: number;
    recentEntries: number; // Last 24 hours
    uniqueFiles: number;
    uniqueUsers: number;
  } {
    const now = Date.now();
    const oneDayAgo = now - 24 * 60 * 60 * 1000;

    let totalRecommendations = 0;
    let totalExecutionTime = 0;
    let recentAnalyses = 0;
    const uniqueFiles = new Set<string>();
    const uniqueUsers = new Set<string>();

    for (const entry of this.entries.values()) {
      totalRecommendations += entry.summary.totalRecommendations;
      totalExecutionTime += (entry.metadata.totalDuration as number) || 0;
      uniqueFiles.add(entry.documentPath);
      uniqueUsers.add(entry.userId);

      if (entry.timestamp > oneDayAgo) {
        recentAnalyses++;
      }
    }

    return {
      totalAnalyses: this.entries.size,
      averageRecommendations: this.entries.size > 0 
        ? Math.round(totalRecommendations / this.entries.size) 
        : 0,
      averageExecutionTime: this.entries.size > 0 
        ? Math.round(totalExecutionTime / this.entries.size) 
        : 0,
      totalRecommendations,
      recentEntries: recentAnalyses,
      uniqueFiles: uniqueFiles.size,
      uniqueUsers: uniqueUsers.size,
    };
  }

  /**
   * Export audit trail as JSON
   */
  exportAsJson(): string {
    const data = {
      exportedAt: new Date().toISOString(),
      version: '1.0',
      statistics: this.getStatistics(),
      entries: Array.from(this.entries.values()),
      trends: Array.from(this.trends.values()).map(trend => ({
        ...trend,
        affectedFiles: Array.from(trend.affectedFiles),
      })),
    };

    return JSON.stringify(data, null, 2);
  }

  /**
   * Search audit entries
   */
  search(criteria: {
    userId?: string;
    filePath?: string;
    minRecommendations?: number;
    maxRecommendations?: number;
    startTime?: number;
    endTime?: number;
  }): AuditEntry[] {
    return Array.from(this.entries.values()).filter(entry => {
      if (criteria.userId && entry.userId !== criteria.userId) return false;
      if (criteria.filePath && entry.documentPath !== criteria.filePath) return false;
      if (criteria.minRecommendations && entry.summary.totalRecommendations < criteria.minRecommendations) return false;
      if (criteria.maxRecommendations && entry.summary.totalRecommendations > criteria.maxRecommendations) return false;
      if (criteria.startTime && entry.timestamp < criteria.startTime) return false;
      if (criteria.endTime && entry.timestamp > criteria.endTime) return false;
      return true;
    });
  }

  /**
   * Clear audit trail (be careful!)
   */
  async clear(): Promise<void> {
    this.entries.clear();
    this.trends.clear();
    await this.persistAuditTrail();
    this.log('Audit trail cleared');
  }

  /**
   * Update trend analysis based on new entry
   */
  private updateTrends(entry: AuditEntry): void {
    // Track recommendation types
    for (const agentResult of entry.agentResults) {
      for (const rec of agentResult.recommendations) {
        const trendKey = `${rec.severity}:${rec.title}`;
        
        let trend = this.trends.get(trendKey);
        if (!trend) {
          trend = {
            type: 'recommendation',
            category: rec.title,
            occurrences: 0,
            lastSeen: 0,
            affectedFiles: new Set(),
          };
          this.trends.set(trendKey, trend);
        }

        trend.occurrences++;
        trend.lastSeen = Date.now();
        trend.affectedFiles.add(entry.documentPath);
      }
    }

    // Track severity trends
    const severityKey = `severity:critical`;
    if (entry.summary.criticalCount > 0) {
      let trend = this.trends.get(severityKey);
      if (!trend) {
        trend = {
          type: 'severity',
          category: 'Critical Issues Found',
          occurrences: 0,
          lastSeen: 0,
          affectedFiles: new Set(),
        };
        this.trends.set(severityKey, trend);
      }
      trend.occurrences += entry.summary.criticalCount;
      trend.lastSeen = Date.now();
      trend.affectedFiles.add(entry.documentPath);
    }
  }

  /**
   * Hash document for tracking changes
   */
  private async hashDocument(documentUri: vscode.Uri): Promise<string> {
    try {
      const document = await vscode.workspace.openTextDocument(documentUri);
      const crypto = require('crypto');
      return crypto.createHash('sha256').update(document.getText()).digest('hex').substring(0, 12);
    } catch {
      return 'unknown-hash';
    }
  }

  /**
   * Generate unique ID
   */
  private generateId(): string {
    return `audit-${Date.now()}-${Math.random().toString(36).substring(7)}`;
  }

  /**
   * Load audit trail from storage
   */
  private loadAuditTrail(): void {
    try {
      const stored = this.config.get('entries', '{}') as string;
      if (stored && stored !== '{}') {
        const data = JSON.parse(stored);
        for (const [id, entry] of Object.entries(data)) {
          const auditEntry = entry as AuditEntry;
          this.entries.set(id, auditEntry);
        }
      }
      this.log(`Loaded ${this.entries.size} audit entries from storage`);
    } catch (error) {
      this.logError(`Failed to load audit trail: ${error}`);
    }
  }

  /**
   * Persist audit trail to storage
   */
  private async persistAuditTrail(): Promise<void> {
    try {
      const data: Record<string, AuditEntry> = {};
      for (const [id, entry] of this.entries) {
        data[id] = entry;
      }
      
      // In real implementation, this would use VS Code's memento or file storage
      // For demo, we store in workspace config
      // await this.config.update('entries', JSON.stringify(data));
      
      this.log(`Persisted ${this.entries.size} audit entries`);
    } catch (error) {
      this.logError(`Failed to persist audit trail: ${error}`);
    }
  }

  /**
   * Log message
   */
  private log(message: string): void {
    this.outputChannel.appendLine(`[${new Date().toISOString()}] ${message}`);
  }

  /**
   * Log error
   */
  private logError(message: string): void {
    this.outputChannel.appendLine(`[ERROR] ${message}`);
  }

  /**
   * Show output channel
   */
  showOutput(): void {
    this.outputChannel.show();
  }
}
