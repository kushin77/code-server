#!/usr/bin/env node
// @file        apps/backend/src/services/ticket-linking/ticket-detector.ts
// @module      integrations/ticket-linking
// @description Detects and resolves Linear/Jira ticket references in code with auto-context injection
// @owner       collab-9
// @status      active

import { EventEmitter } from 'events';

/**
 * Ticket pattern matchers for common issue tracking systems
 */
export interface TicketPattern {
  name: string;
  regex: RegExp;
  workspace: string; // Linear workspace or Jira instance key
  apiBase: string;
}

/**
 * Detected ticket reference with context
 */
export interface TicketReference {
  id: string;
  system: string;
  workspace: string;
  line: number;
  column: number;
  filePath: string;
  context: {
    precedingLines: string[];
    succeedingLines: string[];
    functionName?: string;
    currentLine: string;
  };
}

/**
 * Resolved ticket metadata from API
 */
export interface ResolvedTicket {
  id: string;
  title: string;
  status: string;
  assignee?: string;
  priority?: string;
  project: string;
  url: string;
  lastUpdated: Date;
}

/**
 * Ticket Detector - Scans code for ticket references and resolves metadata
 *
 * Features:
 * - Pattern-based detection (Linear, Jira, GitHub, etc.)
 * - Auto-context injection (captures surrounding code, function context)
 * - Metadata caching (1-hour TTL for API calls)
 * - Side panel integration (broadcasts detected tickets to IDE)
 */
export class TicketDetector extends EventEmitter {
  private patterns: Map<string, TicketPattern> = new Map();
  private cache: Map<string, { ticket: ResolvedTicket; timestamp: number }> = new Map();
  private cacheExpiry = 3600 * 1000; // 1 hour

  constructor(private apiCredentials: Map<string, string> = new Map()) {
    super();
    this.initializePatterns();
  }

  /**
   * Initialize default ticket patterns for common platforms
   */
  private initializePatterns() {
    // Linear pattern: e.g., "PROJ-123" or "LINEAR-456"
    this.registerPattern({
      name: 'linear',
      regex: /([A-Z][A-Z0-9]*-\d+)/g,
      workspace: process.env.LINEAR_WORKSPACE || '',
      apiBase: process.env.LINEAR_API_URL || 'https://api.linear.app/graphql',
    });

    // Jira pattern: e.g., "JIRA-123" or "PROJ-456"
    this.registerPattern({
      name: 'jira',
      regex: /([A-Z][A-Z0-9]*-\d+)/g,
      workspace: process.env.JIRA_INSTANCE || '',
      apiBase: process.env.JIRA_API_URL || 'https://jira.atlassian.net/rest/api/3',
    });

    // GitHub issue pattern: e.g., "#123" or "GH-456"
    this.registerPattern({
      name: 'github',
      regex: /#(\d+)|GH-(\d+)/g,
      workspace: process.env.GITHUB_REPO || '',
      apiBase: 'https://api.github.com',
    });
  }

  /**
   * Register a custom ticket pattern
   */
  registerPattern(pattern: TicketPattern): void {
    this.patterns.set(pattern.name, pattern);
  }

  /**
   * Scan text content for ticket references with context
   */
  async scanContent(
    content: string,
    filePath: string,
    functionContext?: string
  ): Promise<TicketReference[]> {
    const lines = content.split('\n');
    const references: TicketReference[] = [];
    const seen = new Set<string>(); // Track duplicates by line:column:id

    for (const [systemName, pattern] of this.patterns) {
      let match;
      const regex = new RegExp(pattern.regex.source, pattern.regex.flags);

      while ((match = regex.exec(content)) !== null) {
        const ticketId = match[1] || match[0];

        // Calculate line and column
        const precedingText = content.substring(0, match.index);
        const lineNum = precedingText.split('\n').length - 1;
        const column = match.index - precedingText.lastIndexOf('\n');

        // Deduplicate by location and ID
        const key = `${lineNum}:${column}:${ticketId}`;
        if (seen.has(key)) {
          continue;
        }
        seen.add(key);

        // Capture context
        const contextWindow = 3; // lines before and after
        const startLine = Math.max(0, lineNum - contextWindow);
        const endLine = Math.min(lines.length, lineNum + contextWindow + 1);

        references.push({
          id: ticketId,
          system: systemName,
          workspace: pattern.workspace,
          line: lineNum,
          column,
          filePath,
          context: {
            precedingLines: lines.slice(startLine, lineNum),
            succeedingLines: lines.slice(lineNum + 1, endLine),
            functionName: functionContext,
            currentLine: lines[lineNum],
          },
        });
      }
    }

    return references;
  }

  /**
   * Resolve ticket metadata from API with caching
   */
  async resolveTicket(reference: TicketReference): Promise<ResolvedTicket | null> {
    const cacheKey = `${reference.system}:${reference.id}`;

    // Check cache
    const cached = this.cache.get(cacheKey);
    if (cached && Date.now() - cached.timestamp < this.cacheExpiry) {
      return cached.ticket;
    }

    try {
      const ticket = await this.fetchTicketMetadata(reference);
      if (ticket) {
        this.cache.set(cacheKey, { ticket, timestamp: Date.now() });
        return ticket;
      }
    } catch (error) {
      console.error(`Failed to resolve ticket ${cacheKey}:`, error);
    }

    return null;
  }

  /**
   * Fetch ticket metadata from external API
   */
  private async fetchTicketMetadata(reference: TicketReference): Promise<ResolvedTicket | null> {
    const { system, id, workspace } = reference;

    switch (system) {
      case 'linear':
        return this.fetchLinearTicket(id);
      case 'jira':
        return this.fetchJiraTicket(id, workspace);
      case 'github':
        return this.fetchGitHubIssue(id, workspace);
      default:
        return null;
    }
  }

  /**
   * Fetch from Linear GraphQL API
   */
  private async fetchLinearTicket(ticketId: string): Promise<ResolvedTicket | null> {
    const apiKey = this.apiCredentials.get('linear');
    if (!apiKey) {
      console.warn('Linear API key not configured');
      return null;
    }

    try {
      const query = `
        query {
          issueByIdentifier(identifier: "${ticketId}") {
            id
            title
            state { name }
            assignee { name }
            priority { name }
            team { key }
            url
            updatedAt
          }
        }
      `;

      const response = await fetch('https://api.linear.app/graphql', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${apiKey}`,
        },
        body: JSON.stringify({ query }),
      });

      const data = await response.json();

      if (data.data?.issueByIdentifier) {
        const issue = data.data.issueByIdentifier;
        return {
          id: ticketId,
          title: issue.title,
          status: issue.state.name,
          assignee: issue.assignee?.name,
          priority: issue.priority?.name,
          project: issue.team.key,
          url: issue.url,
          lastUpdated: new Date(issue.updatedAt),
        };
      }
    } catch (error) {
      console.error(`Linear API error for ${ticketId}:`, error);
    }

    return null;
  }

  /**
   * Fetch from Jira REST API
   */
  private async fetchJiraTicket(ticketId: string, workspace: string): Promise<ResolvedTicket | null> {
    const apiKey = this.apiCredentials.get('jira');
    if (!apiKey) {
      console.warn('Jira API key not configured');
      return null;
    }

    try {
      const response = await fetch(
        `${workspace}/rest/api/3/search?jql=key=${ticketId}&fields=summary,status,assignee,priority`,
        {
          headers: {
            Authorization: `Bearer ${apiKey}`,
            'Content-Type': 'application/json',
          },
        }
      );

      const data = await response.json();

      if (data.issues?.length > 0) {
        const issue = data.issues[0];
        return {
          id: ticketId,
          title: issue.fields.summary,
          status: issue.fields.status.name,
          assignee: issue.fields.assignee?.displayName,
          priority: issue.fields.priority?.name,
          project: issue.key.split('-')[0],
          url: `${workspace}/browse/${ticketId}`,
          lastUpdated: new Date(),
        };
      }
    } catch (error) {
      console.error(`Jira API error for ${ticketId}:`, error);
    }

    return null;
  }

  /**
   * Fetch from GitHub REST API
   */
  private async fetchGitHubIssue(issueId: string, repo: string): Promise<ResolvedTicket | null> {
    const token = this.apiCredentials.get('github');
    if (!token) {
      console.warn('GitHub token not configured');
      return null;
    }

    try {
      const [owner, repoName] = repo.split('/');
      const response = await fetch(
        `https://api.github.com/repos/${owner}/${repoName}/issues/${issueId}`,
        {
          headers: {
            Authorization: `Bearer ${token}`,
            Accept: 'application/vnd.github+json',
          },
        }
      );

      const issue = await response.json();

      return {
        id: issueId,
        title: issue.title,
        status: issue.state,
        assignee: issue.assignee?.login,
        priority: issue.labels
          .filter((l: any) => l.name.startsWith('P'))
          .map((l: any) => l.name)
          .join(','),
        project: repo,
        url: issue.html_url,
        lastUpdated: new Date(issue.updated_at),
      };
    } catch (error) {
      console.error(`GitHub API error for ${issueId}:`, error);
    }

    return null;
  }

  /**
   * Get all resolved tickets for a file
   */
  async getResolvedTicketsForFile(filePath: string, content: string): Promise<ResolvedTicket[]> {
    const references = await this.scanContent(content, filePath);
    const resolved: ResolvedTicket[] = [];

    for (const ref of references) {
      const ticket = await this.resolveTicket(ref);
      if (ticket) {
        resolved.push(ticket);
      }
    }

    return resolved;
  }

  /**
   * Clear expired cache entries
   */
  clearExpiredCache(): void {
    const now = Date.now();
    for (const [key, value] of this.cache.entries()) {
      if (now - value.timestamp > this.cacheExpiry) {
        this.cache.delete(key);
      }
    }
  }
}

export default TicketDetector;
