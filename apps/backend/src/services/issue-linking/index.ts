#!/usr/bin/env node
// @file        apps/backend/src/services/issue-linking/index.ts
// @module      collaboration/issue-linking
// @description Linear/Jira ticket linking with context injection and auto-branch naming
// @owner       collab-9.2
// @status      active

import { EventEmitter } from 'events';
import { Pool } from 'pg';
import { getLogger } from '../../lib/logger';
import { AuditService } from '../audit/audit-service.js';

export type IssueProvider = 'linear' | 'jira';

export interface IssueTicket {
  id: string;
  provider: IssueProvider;
  key: string;
  title: string;
  description?: string;
  status: string;
  assignee?: string;
  priority?: string;
  labels?: string[];
  url: string;
  createdAt: Date;
  updatedAt: Date;
}

export interface LinkedIssue {
  id: string;
  ticketId: string;
  githubIssueNumber: number;
  linkedAt: Date;
  provider: IssueProvider;
}

export interface IssueContext {
  ticketKey: string;
  title: string;
  acceptanceCriteria?: string;
  linkedPRs: { number: number; title: string; url: string }[];
  relatedIssues: { key: string; title: string }[];
  estimatedEffort?: string;
}

export interface BranchNameConfig {
  prefix?: string;
  ticketKey: string;
  title: string;
  maxLength?: number;
  sanitize?: boolean;
}

export interface IssueLinkingConfig {
  linearApiToken?: string;
  jiraBaseUrl?: string;
  jiraUsername?: string;
  jiraApiToken?: string;
}

export interface SearchResult {
  provider: IssueProvider;
  tickets: IssueTicket[];
  query: string;
  totalCount: number;
}

export class IssueLinkingService extends EventEmitter {
  private pool: Pool;
  private auditService?: AuditService;
  private logger = getLogger('IssueLinkingService');
  private initialized = false;
  private config: IssueLinkingConfig;

  constructor(pool: Pool, auditService: AuditService, config?: IssueLinkingConfig);
  constructor(pool: Pool, config?: IssueLinkingConfig);

  constructor(
    pool: Pool,
    auditServiceOrConfig?: AuditService | IssueLinkingConfig,
    config: IssueLinkingConfig = {}
  ) {
    super();
    this.pool = pool;
    const hasAuditService = !!auditServiceOrConfig && typeof (auditServiceOrConfig as AuditService).emit === 'function';
    this.auditService = hasAuditService ? (auditServiceOrConfig as AuditService) : undefined;
    const resolvedConfig = hasAuditService ? config : (auditServiceOrConfig as IssueLinkingConfig | undefined) ?? {};
    this.config = {
      linearApiToken: process.env.LINEAR_API_TOKEN,
      jiraBaseUrl: process.env.JIRA_BASE_URL,
      jiraUsername: process.env.JIRA_USERNAME,
      jiraApiToken: process.env.JIRA_API_TOKEN,
      ...resolvedConfig,
    };
  }

  async initialize(): Promise<void> {
    if (this.initialized) return;

    try {
      await this.createTables();
      this.initialized = true;
      this.logger.info('Issue linking database schema initialized');
    } catch (error) {
      this.logger.error('Failed to initialize issue linking schema', { error });
      throw error;
    }
  }

  private async createTables(): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');

      // Issue tickets from Linear/Jira
      await client.query(`
        CREATE TABLE IF NOT EXISTS issue_tickets (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          provider TEXT NOT NULL CHECK (provider IN ('linear', 'jira')),
          external_id TEXT NOT NULL,
          ticket_key TEXT NOT NULL,
          title TEXT NOT NULL,
          description TEXT,
          status TEXT,
          assignee TEXT,
          priority TEXT,
          labels TEXT[],
          url TEXT NOT NULL,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          UNIQUE(provider, external_id)
        )
      `);

      // Linked issues (ticket <-> GitHub issue)
      await client.query(`
        CREATE TABLE IF NOT EXISTS linked_issues (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          ticket_id UUID NOT NULL REFERENCES issue_tickets(id) ON DELETE CASCADE,
          github_issue_number INTEGER NOT NULL,
          provider TEXT NOT NULL,
          linked_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        )
      `);

      // Issue context cache
      await client.query(`
        CREATE TABLE IF NOT EXISTS issue_context (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          ticket_key TEXT NOT NULL UNIQUE,
          title TEXT,
          acceptance_criteria TEXT,
          related_issues JSONB,
          linked_prs JSONB,
          estimated_effort TEXT,
          cached_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        )
      `);

      // Branch naming history
      await client.query(`
        CREATE TABLE IF NOT EXISTS branch_names (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          ticket_key TEXT NOT NULL,
          suggested_name TEXT NOT NULL,
          actual_name TEXT,
          created_by TEXT,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        )
      `);

      // Search cache
      await client.query(`
        CREATE TABLE IF NOT EXISTS issue_search_cache (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          query TEXT NOT NULL,
          provider TEXT NOT NULL,
          results JSONB,
          cached_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          expires_at TIMESTAMP WITH TIME ZONE,
          UNIQUE(query, provider)
        )
      `);

      // Indexes
      await client.query(`
        CREATE INDEX IF NOT EXISTS idx_issue_tickets_provider ON issue_tickets(provider);
        CREATE INDEX IF NOT EXISTS idx_issue_tickets_key ON issue_tickets(ticket_key);
        CREATE INDEX IF NOT EXISTS idx_linked_issues_ticket ON linked_issues(ticket_id);
        CREATE INDEX IF NOT EXISTS idx_linked_issues_github ON linked_issues(github_issue_number);
        CREATE INDEX IF NOT EXISTS idx_branch_names_ticket ON branch_names(ticket_key);
        CREATE INDEX IF NOT EXISTS idx_search_cache_expires ON issue_search_cache(expires_at);
      `);

      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  async searchTickets(query: string, provider?: IssueProvider): Promise<SearchResult[]> {
    const providers: IssueProvider[] = provider ? [provider] : ['linear', 'jira'];
    const results: SearchResult[] = [];

    for (const prov of providers) {
      try {
        // Check cache first
        const cached = await this.getSearchCache(query, prov);
        if (cached) {
          results.push({
            provider: prov,
            tickets: cached,
            query,
            totalCount: cached.length,
          });
          continue;
        }

        let tickets: IssueTicket[] = [];

        if (prov === 'linear' && this.config.linearApiToken) {
          tickets = await this.searchLinearTickets(query);
        } else if (prov === 'jira' && this.config.jiraBaseUrl) {
          tickets = await this.searchJiraTickets(query);
        } else {
          this.logger.warn('No credentials for provider', { provider: prov });
          continue;
        }

        // Cache the results
        await this.setSearchCache(query, prov, tickets);

        results.push({
          provider: prov,
          tickets,
          query,
          totalCount: tickets.length,
        });
      } catch (error) {
        this.logger.error('Failed to search tickets', { error, provider: prov, query });
      }
    }

    return results;
  }

  private async searchLinearTickets(query: string): Promise<IssueTicket[]> {
    // In production, call Linear API:
    // const response = await fetch('https://api.linear.app/graphql', {
    //   method: 'POST',
    //   headers: { Authorization: `Bearer ${this.config.linearApiToken}` },
    //   body: JSON.stringify({ query: ... })
    // });

    this.logger.info('Searching Linear tickets', { query });

    // Mock implementation
    return [
      {
        id: 'linear-1',
        provider: 'linear',
        key: 'ENG-123',
        title: 'Implement user authentication',
        description: 'Add OAuth2 support',
        status: 'In Progress',
        assignee: 'alice@example.com',
        priority: 'High',
        labels: ['feature', 'backend'],
        url: 'https://linear.app/...',
        createdAt: new Date(),
        updatedAt: new Date(),
      },
    ];
  }

  private async searchJiraTickets(query: string): Promise<IssueTicket[]> {
    // In production, call Jira API:
    // const response = await fetch(`${this.config.jiraBaseUrl}/rest/api/3/search`, {
    //   headers: { Authorization: `Basic ${Buffer.from(...).toString('base64')}` },
    //   query: `text ~ "${query}"`
    // });

    this.logger.info('Searching Jira tickets', { query });

    // Mock implementation
    return [
      {
        id: 'jira-1',
        provider: 'jira',
        key: 'PROJ-456',
        title: 'Setup CI/CD pipeline',
        description: 'Implement GitHub Actions workflow',
        status: 'To Do',
        assignee: 'bob@example.com',
        priority: 'Medium',
        labels: ['devops', 'automation'],
        url: 'https://jira.example.com/...',
        createdAt: new Date(),
        updatedAt: new Date(),
      },
    ];
  }

  async saveTicket(ticket: IssueTicket): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query(
        `INSERT INTO issue_tickets (provider, external_id, ticket_key, title, description, status, assignee, priority, labels, url)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
         ON CONFLICT (provider, external_id) DO UPDATE SET
           title = $4, description = $5, status = $6, assignee = $7, priority = $8, labels = $9, updated_at = NOW()`,
        [
          ticket.provider,
          ticket.id,
          ticket.key,
          ticket.title,
          ticket.description || null,
          ticket.status,
          ticket.assignee || null,
          ticket.priority || null,
          ticket.labels || null,
          ticket.url,
        ]
      );

      this.logger.info('Ticket saved', { provider: ticket.provider, key: ticket.key });
    } catch (error) {
      this.logger.error('Failed to save ticket', { error, ticketKey: ticket.key });
      throw error;
    } finally {
      client.release();
    }
  }

  // SOC2: Audit ticket linking
  private auditTicketLink(ticketId: string, githubIssueNumber: number): void {
    this.auditService?.emit({
      userId: 'system',
      action: 'allow',
      resource: 'ticket-link:' + ticketId,
      reason: 'Linked ticket ' + ticketId + ' to GitHub issue #' + githubIssueNumber
    });
  }

  async linkIssue(ticketId: string, githubIssueNumber: number, provider: IssueProvider): Promise<void> {
    const client = await this.pool.connect();
    try {
      // First get the ticket ID from external_id
      const ticketResult = await client.query(
        'SELECT id FROM issue_tickets WHERE external_id = $1 AND provider = $2',
        [ticketId, provider]
      );

      if (ticketResult.rows.length === 0) {
        throw new Error(`Ticket not found: ${ticketId}`);
      }

      const dbTicketId = ticketResult.rows[0].id;

      await client.query(
        `INSERT INTO linked_issues (ticket_id, github_issue_number, provider)
         VALUES ($1, $2, $3)`,
        [dbTicketId, githubIssueNumber, provider]
      );

      this.logger.info('Issue linked', { ticketId, githubIssueNumber, provider });
    } catch (error) {
      this.logger.error('Failed to link issue', { error, ticketId, githubIssueNumber });
      throw error;
    } finally {
      client.release();
    }
  }

  async getIssueContext(ticketKey: string): Promise<IssueContext | null> {
    const client = await this.pool.connect();
    try {
      // Check cache first
      const cached = await client.query(
        'SELECT * FROM issue_context WHERE ticket_key = $1',
        [ticketKey]
      );

      if (cached.rows.length > 0) {
        const row = cached.rows[0];
        return {
          ticketKey: row.ticket_key,
          title: row.title,
          acceptanceCriteria: row.acceptance_criteria,
          linkedPRs: row.linked_prs || [],
          relatedIssues: row.related_issues || [],
          estimatedEffort: row.estimated_effort,
        };
      }

      return null;
    } catch (error) {
      this.logger.error('Failed to get issue context', { error, ticketKey });
      throw error;
    } finally {
      client.release();
    }
  }

  async saveIssueContext(context: IssueContext): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query(
        `INSERT INTO issue_context (ticket_key, title, acceptance_criteria, related_issues, linked_prs, estimated_effort)
         VALUES ($1, $2, $3, $4, $5, $6)
         ON CONFLICT (ticket_key) DO UPDATE SET
           title = $2, acceptance_criteria = $3, related_issues = $4, linked_prs = $5, estimated_effort = $6, updated_at = NOW()`,
        [
          context.ticketKey,
          context.title,
          context.acceptanceCriteria || null,
          JSON.stringify(context.relatedIssues),
          JSON.stringify(context.linkedPRs),
          context.estimatedEffort || null,
        ]
      );

      this.logger.info('Issue context saved', { ticketKey: context.ticketKey });
    } catch (error) {
      this.logger.error('Failed to save issue context', { error, ticketKey: context.ticketKey });
      throw error;
    } finally {
      client.release();
    }
  }

  generateBranchName(config: BranchNameConfig): string {
    const { prefix = '', ticketKey, title, maxLength = 50, sanitize = true } = config;

    // Clean title: remove special chars, lowercase, replace spaces with hyphens
    let cleanTitle = title
      .toLowerCase()
      .replace(/[^a-z0-9\s-]/g, '')
      .replace(/\s+/g, '-')
      .replace(/-+/g, '-')
      .replace(/^-|-$/g, '');

    // Truncate if needed
    const availableLength = Math.max(20, maxLength - prefix.length - ticketKey.length - 2);
    cleanTitle = cleanTitle.substring(0, availableLength);

    // Build branch name
    const parts = [prefix, ticketKey.toLowerCase(), cleanTitle].filter(p => p);
    const branchName = parts.join('/');

    return sanitize ? branchName.replace(/[^a-z0-9/-]/g, '') : branchName;
  }

  async saveBranchName(ticketKey: string, suggestedName: string, actualName?: string, createdBy?: string): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query(
        `INSERT INTO branch_names (ticket_key, suggested_name, actual_name, created_by)
         VALUES ($1, $2, $3, $4)`,
        [ticketKey, suggestedName, actualName || null, createdBy || null]
      );

      this.logger.info('Branch name saved', { ticketKey, suggestedName });
    } catch (error) {
      this.logger.error('Failed to save branch name', { error, ticketKey });
      throw error;
    } finally {
      client.release();
    }
  }

  async getBranchNames(ticketKey: string): Promise<{ suggested: string; actual?: string }[]> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        'SELECT suggested_name, actual_name FROM branch_names WHERE ticket_key = $1 ORDER BY created_at DESC',
        [ticketKey]
      );

      return result.rows.map(row => ({
        suggested: row.suggested_name,
        actual: row.actual_name,
      }));
    } catch (error) {
      this.logger.error('Failed to get branch names', { error, ticketKey });
      throw error;
    } finally {
      client.release();
    }
  }

  private async getSearchCache(query: string, provider: IssueProvider): Promise<IssueTicket[] | null> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        'SELECT results FROM issue_search_cache WHERE query = $1 AND provider = $2 AND expires_at > NOW()',
        [query, provider]
      );

      if (result.rows.length === 0) {
        return null;
      }

      return result.rows[0].results || [];
    } catch (error) {
      this.logger.error('Failed to get search cache', { error });
      return null;
    } finally {
      client.release();
    }
  }

  private async setSearchCache(query: string, provider: IssueProvider, tickets: IssueTicket[]): Promise<void> {
    const client = await this.pool.connect();
    try {
      // Cache for 1 hour
      const expiresAt = new Date(Date.now() + 60 * 60 * 1000);

      await client.query(
        `INSERT INTO issue_search_cache (query, provider, results, expires_at)
         VALUES ($1, $2, $3, $4)
         ON CONFLICT (query, provider) DO UPDATE SET
           results = $3, expires_at = $4, cached_at = NOW()`,
        [query, provider, JSON.stringify(tickets), expiresAt]
      );

      this.logger.info('Search cache set', { query, provider, count: tickets.length });
    } catch (error) {
      this.logger.error('Failed to set search cache', { error });
      // Don't throw - caching failure shouldn't break the feature
    } finally {
      client.release();
    }
  }

  formatContextForCopilot(context: IssueContext): string {
    const lines = [
      `## Ticket: ${context.ticketKey}`,
      `**Title**: ${context.title}`,
    ];

    if (context.acceptanceCriteria) {
      lines.push('');
      lines.push('**Acceptance Criteria**:');
      lines.push(context.acceptanceCriteria);
    }

    if (context.linkedPRs && context.linkedPRs.length > 0) {
      lines.push('');
      lines.push('**Linked PRs**:');
      context.linkedPRs.forEach(pr => {
        lines.push(`- [#${pr.number}](${pr.url}): ${pr.title}`);
      });
    }

    if (context.relatedIssues && context.relatedIssues.length > 0) {
      lines.push('');
      lines.push('**Related Issues**:');
      context.relatedIssues.forEach(issue => {
        lines.push(`- ${issue.key}: ${issue.title}`);
      });
    }

    if (context.estimatedEffort) {
      lines.push('');
      lines.push(`**Estimated Effort**: ${context.estimatedEffort}`);
    }

    return lines.join('\n');
  }
}
