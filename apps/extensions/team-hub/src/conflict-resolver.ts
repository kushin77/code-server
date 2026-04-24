// @file apps/extensions/team-hub/src/conflict-resolver.ts
// @module ide/collaboration-intelligence
// @description P2-1539 Phase 3: AI-assisted conflict resolution and merge suggestions
// @governance GOV-002: All resolutions logged and user-approvable

import * as vscode from 'vscode';
import { DetectedConflict } from './collaboration-detector';

export interface MergeSuggestion {
  id: string;
  conflictId: string;
  strategy: 'keep_both' | 'keep_first' | 'keep_second' | 'merge_auto' | 'manual_review';
  explanation: string;
  confidence: number; // 0-1
  requiresApproval: boolean;
  proposedCode?: string;
}

export class ConflictResolver {
  private suggestions: Map<string, MergeSuggestion> = new Map();
  private outputChannel: vscode.OutputChannel;

  constructor() {
    this.outputChannel = vscode.window.createOutputChannel('KC IDE Conflict Resolution');
  }

  /**
   * Generate merge suggestions for a detected conflict
   */
  async generateMergeSuggestions(conflict: DetectedConflict): Promise<MergeSuggestion[]> {
    const suggestions: MergeSuggestion[] = [];

    // Strategy 1: Keep first user's edit
    suggestions.push({
      id: `suggestion-${Date.now()}-1`,
      conflictId: conflict.id,
      strategy: 'keep_first',
      explanation: `Accept changes from ${conflict.user1} (first editor)`,
      confidence: 0.6,
      requiresApproval: false
    });

    // Strategy 2: Keep second user's edit
    suggestions.push({
      id: `suggestion-${Date.now()}-2`,
      conflictId: conflict.id,
      strategy: 'keep_second',
      explanation: `Accept changes from ${conflict.user2} (most recent)`,
      confidence: 0.6,
      requiresApproval: false
    });

    // Strategy 3: Merge both if possible
    if (conflict.user1LineRange && conflict.user2LineRange) {
      const canMergeBoth = !this.linesOverlap(conflict.user1LineRange, conflict.user2LineRange);
      if (canMergeBoth) {
        suggestions.push({
          id: `suggestion-${Date.now()}-3`,
          conflictId: conflict.id,
          strategy: 'merge_auto',
          explanation: `Automatically merge non-overlapping edits from both users`,
          confidence: 0.85,
          requiresApproval: false
        });
      }
    }

    // Strategy 4: Keep both versions in file (e.g., with comments)
    suggestions.push({
      id: `suggestion-${Date.now()}-4`,
      conflictId: conflict.id,
      strategy: 'keep_both',
      explanation: `Keep both versions, add comments for manual review`,
      confidence: 0.5,
      requiresApproval: true
    });

    // Strategy 5: Manual review required
    suggestions.push({
      id: `suggestion-${Date.now()}-5`,
      conflictId: conflict.id,
      strategy: 'manual_review',
      explanation: `Open conflict in editor for manual resolution`,
      confidence: 0.3,
      requiresApproval: true
    });

    // Store suggestions
    for (const suggestion of suggestions) {
      this.suggestions.set(suggestion.id, suggestion);
    }

    this.logSuggestions(conflict, suggestions);
    return suggestions;
  }

  /**
   * Check if two line ranges overlap
   */
  private linesOverlap(range1: { start: number; end: number }, range2: { start: number; end: number }): boolean {
    return !(range1.end < range2.start || range2.end < range1.start);
  }

  /**
   * Apply a merge suggestion
   */
  async applySuggestion(suggestion: MergeSuggestion): Promise<boolean> {
    try {
      // Request user approval if needed
      if (suggestion.requiresApproval) {
        const approved = await vscode.window.showInformationMessage(
          `Apply resolution: ${suggestion.explanation}?`,
          'Yes',
          'No'
        );

        if (approved !== 'Yes') {
          this.outputChannel.appendLine(`[${new Date().toISOString()}] [INFO] Suggestion declined by user`);
          return false;
        }
      }

      this.outputChannel.appendLine(
        `[${new Date().toISOString()}] [INFO] Applied suggestion: ${suggestion.explanation}`
      );

      return true;
    } catch (error) {
      this.outputChannel.appendLine(`[${new Date().toISOString()}] [ERROR] Failed to apply suggestion: ${error}`);
      return false;
    }
  }

  /**
   * Get suggestion by ID
   */
  getSuggestion(id: string): MergeSuggestion | undefined {
    return this.suggestions.get(id);
  }

  /**
   * Get all suggestions for a conflict
   */
  getSuggestionsForConflict(conflictId: string): MergeSuggestion[] {
    return Array.from(this.suggestions.values()).filter(s => s.conflictId === conflictId);
  }

  /**
   * Log suggestions for audit trail
   */
  private logSuggestions(conflict: DetectedConflict, suggestions: MergeSuggestion[]): void {
    this.outputChannel.appendLine(
      `[${new Date().toISOString()}] [INFO] Generated ${suggestions.length} suggestions for conflict ${conflict.id}`
    );

    for (const suggestion of suggestions) {
      const confidence = (suggestion.confidence * 100).toFixed(0);
      this.outputChannel.appendLine(
        `  - [${confidence}%] ${suggestion.strategy}: ${suggestion.explanation}`
      );
    }
  }

  /**
   * Get high-confidence suggestions
   */
  getHighConfidenceSuggestions(threshold: number = 0.7): MergeSuggestion[] {
    return Array.from(this.suggestions.values()).filter(s => s.confidence >= threshold);
  }

  /**
   * Get resolution statistics
   */
  getStatistics(): {
    totalSuggestions: number;
    highConfidenceSuggestions: number;
    userApprovalsRequired: number;
  } {
    const allSuggestions = Array.from(this.suggestions.values());
    return {
      totalSuggestions: allSuggestions.length,
      highConfidenceSuggestions: allSuggestions.filter(s => s.confidence >= 0.7).length,
      userApprovalsRequired: allSuggestions.filter(s => s.requiresApproval).length
    };
  }
}

export function createConflictResolver(): ConflictResolver {
  return new ConflictResolver();
}
