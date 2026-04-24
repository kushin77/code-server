// @file apps/extensions/team-hub/src/copilot-context-engine.ts
// @module ide/copilot-autonomy
// @description P2-1539 Phase 2: Copilot context engine for autonomous task execution
// @governance GOV-002: All context building immutable, logged, and traceable

import * as vscode from 'vscode';
import * as fs from 'fs';
import * as path from 'path';

export interface DocumentContext {
  filename: string;
  content: string;
  relevanceScore: number;
}

export interface IssueContext {
  number: number;
  title: string;
  body: string;
  labels: string[];
  relevanceScore: number;
}

export interface ContextQueryResult {
  query: string;
  timestamp: string;
  sources: {
    docs: DocumentContext[];
    issues: IssueContext[];
    logs: string[];
  };
  totalRelevance: number;
}

export class CopilotContextEngine {
  private workspaceRoot: string;
  private docsPath: string;
  private logsPath: string;

  constructor(workspaceRoot: string = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath || '.') {
    this.workspaceRoot = workspaceRoot;
    this.docsPath = path.join(this.workspaceRoot, 'docs');
    this.logsPath = path.join(this.workspaceRoot, 'logs');
  }

  /**
   * Query documentation files for relevant context
   */
  async queryDocumentation(query: string): Promise<DocumentContext[]> {
    const results: DocumentContext[] = [];

    try {
      if (!fs.existsSync(this.docsPath)) {
        return results;
      }

      const files = fs.readdirSync(this.docsPath).filter(f => f.endsWith('.md'));

      for (const file of files) {
        const filepath = path.join(this.docsPath, file);
        const content = fs.readFileSync(filepath, 'utf-8');

        // Calculate relevance score based on keyword matches
        const relevanceScore = this.calculateRelevance(content, query);

        if (relevanceScore > 0) {
          results.push({
            filename: file,
            content: content.substring(0, 2000), // First 2000 chars
            relevanceScore
          });
        }
      }
    } catch (error) {
      console.error('[CopilotContextEngine] Documentation query failed:', error);
    }

    // Sort by relevance
    return results.sort((a, b) => b.relevanceScore - a.relevanceScore);
  }

  /**
   * Query logs for relevant execution context
   */
  async queryLogs(query: string, maxLines: number = 50): Promise<string[]> {
    const results: string[] = [];

    try {
      if (!fs.existsSync(this.logsPath)) {
        return results;
      }

      const files = fs.readdirSync(this.logsPath).filter(f => f.endsWith('.log'));

      for (const file of files) {
        const filepath = path.join(this.logsPath, file);
        const lines = fs.readFileSync(filepath, 'utf-8').split('\n');

        // Find lines matching query
        const matchingLines = lines.filter(line =>
          query.toLowerCase().split(' ').some(term => line.toLowerCase().includes(term))
        ).slice(-maxLines);

        results.push(...matchingLines);
      }
    } catch (error) {
      console.error('[CopilotContextEngine] Log query failed:', error);
    }

    return results;
  }

  /**
   * Query GitHub issues (if GitHub API available)
   * This will be populated when GitHub integration is added (Phase 5)
   */
  async queryGitHubIssues(query: string): Promise<IssueContext[]> {
    // TODO: Implement in Phase 5 - GitHub Account Integration
    // For now, return empty to maintain idempotency
    return [];
  }

  /**
   * Build comprehensive context for Copilot prompt
   */
  async buildContext(query: string): Promise<ContextQueryResult> {
    const timestamp = new Date().toISOString();

    const [docs, logs, issues] = await Promise.all([
      this.queryDocumentation(query),
      this.queryLogs(query),
      this.queryGitHubIssues(query)
    ]);

    const totalRelevance = docs.reduce((sum, d) => sum + d.relevanceScore, 0) +
                          issues.reduce((sum, i) => sum + i.relevanceScore, 0);

    return {
      query,
      timestamp,
      sources: {
        docs: docs.slice(0, 5), // Top 5 docs
        issues: issues.slice(0, 5), // Top 5 issues
        logs: logs.slice(0, 10) // Last 10 matching log lines
      },
      totalRelevance
    };
  }

  /**
   * Format context for Copilot prompt
   */
  formatContextForPrompt(context: ContextQueryResult): string {
    let formatted = `# Context for Query: "${context.query}"\n`;
    formatted += `# Generated: ${context.timestamp}\n\n`;

    if (context.sources.docs.length > 0) {
      formatted += `## Relevant Documentation\n`;
      for (const doc of context.sources.docs) {
        formatted += `### ${doc.filename} (relevance: ${doc.relevanceScore.toFixed(2)})\n`;
        formatted += `\`\`\`\n${doc.content}\n\`\`\`\n\n`;
      }
    }

    if (context.sources.issues.length > 0) {
      formatted += `## Related Issues\n`;
      for (const issue of context.sources.issues) {
        formatted += `- #${issue.number}: ${issue.title} [${issue.labels.join(', ')}]\n`;
      }
      formatted += '\n';
    }

    if (context.sources.logs.length > 0) {
      formatted += `## Recent Logs\n`;
      formatted += `\`\`\`\n${context.sources.logs.join('\n')}\n\`\`\`\n`;
    }

    return formatted;
  }

  /**
   * Calculate relevance score for a document
   * Simple keyword matching — can be enhanced with semantic search
   */
  private calculateRelevance(content: string, query: string): number {
    const queryTerms = query.toLowerCase().split(/\s+/).filter(t => t.length > 2);
    if (queryTerms.length === 0) return 0;

    const contentLower = content.toLowerCase();
    let score = 0;

    for (const term of queryTerms) {
      const matches = (contentLower.match(new RegExp(term, 'g')) || []).length;
      score += matches;
    }

    // Boost if query terms appear in title/headings
    const headings = content.match(/^#+\s+(.+)$/gm) || [];
    for (const heading of headings) {
      if (queryTerms.some(term => heading.toLowerCase().includes(term))) {
        score += 10;
      }
    }

    return score;
  }
}

export async function createCopilotContextEngine(): Promise<CopilotContextEngine> {
  const root = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath;
  if (!root) {
    throw new Error('No workspace folder open');
  }
  return new CopilotContextEngine(root);
}
