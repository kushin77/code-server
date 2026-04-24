// @file apps/extensions/team-hub/src/github-account-manager.ts
// @module ide/github-integration
// @description P2-1539 Phase 5: Manage GitHub user accounts and repository access
// @governance GOV-002: Account data immutable, permissions audited, revocation tracked

import * as vscode from 'vscode';

export interface GitHubRepository {
  id: string;
  name: string;
  fullName: string;
  description: string;
  url: string;
  private: boolean;
  archived: boolean;
  stargazersCount: number;
  language?: string;
}

export interface GitHubUserAccount {
  id: string;
  login: string;
  name: string;
  email: string;
  bio?: string;
  company?: string;
  location?: string;
  avatarUrl: string;
  followers: number;
  following: number;
  publicRepos: number;
  createdAt: string;
  updatedAt: string;
}

export interface AccountPermission {
  userId: string;
  repositoryId: string;
  accessLevel: 'read' | 'write' | 'admin';
  grantedAt: string;
  grantedBy: string;
}

/**
 * Manage GitHub user accounts and repository access
 */
export class GitHubAccountManager {
  private outputChannel: vscode.OutputChannel;
  private accounts: Map<string, GitHubUserAccount> = new Map();
  private repositories: Map<string, GitHubRepository> = new Map();
  private permissions: AccountPermission[] = [];
  private accessLog: Array<{ timestamp: string; action: string; userId: string; details: string }> = [];

  constructor() {
    this.outputChannel = vscode.window.createOutputChannel('KC IDE GitHub Accounts');
  }

  /**
   * Register authenticated user account
   */
  async registerAccount(user: GitHubUserAccount): Promise<boolean> {
    try {
      this.accounts.set(user.id, user);
      this.log(`✓ Account registered: ${user.login}`);
      this.logAccess('account_registered', user.id, `User: ${user.name}`);
      return true;
    } catch (error) {
      this.log(`Account registration error: ${error}`, 'error');
      return false;
    }
  }

  /**
   * Fetch user's repositories
   */
  async fetchUserRepositories(userId: string): Promise<GitHubRepository[]> {
    try {
      const user = this.accounts.get(userId);
      if (!user) {
        this.log(`User not found: ${userId}`, 'error');
        return [];
      }

      // In production, would call GitHub API: GET https://api.github.com/user/repos
      const mockRepos: GitHubRepository[] = [
        {
          id: 'repo_' + Math.random().toString(36).substring(7),
          name: 'code-server',
          fullName: `${user.login}/code-server`,
          description: 'VS Code running on remote machines via the browser',
          url: `https://github.com/${user.login}/code-server`,
          private: false,
          archived: false,
          stargazersCount: 0,
          language: 'TypeScript'
        },
        {
          id: 'repo_' + Math.random().toString(36).substring(7),
          name: 'paperclip',
          fullName: `${user.login}/paperclip`,
          description: 'Enterprise IDE platform',
          url: `https://github.com/${user.login}/paperclip`,
          private: true,
          archived: false,
          stargazersCount: 0,
          language: 'TypeScript'
        }
      ];

      // Store repositories
      mockRepos.forEach(repo => this.repositories.set(repo.id, repo));

      this.log(`✓ Fetched ${mockRepos.length} repositories for ${user.login}`);
      this.logAccess('repos_fetched', userId, `Count: ${mockRepos.length}`);
      return mockRepos;
    } catch (error) {
      this.log(`Repository fetch error: ${error}`, 'error');
      return [];
    }
  }

  /**
   * Grant repository access to user
   */
  async grantRepositoryAccess(
    userId: string,
    repositoryId: string,
    accessLevel: 'read' | 'write' | 'admin'
  ): Promise<boolean> {
    try {
      const user = this.accounts.get(userId);
      if (!user) {
        this.log(`User not found: ${userId}`, 'error');
        return false;
      }

      const repo = this.repositories.get(repositoryId);
      if (!repo) {
        this.log(`Repository not found: ${repositoryId}`, 'error');
        return false;
      }

      // Check for existing permission
      const existing = this.permissions.find(
        p => p.userId === userId && p.repositoryId === repositoryId
      );

      if (existing) {
        existing.accessLevel = accessLevel;
        existing.grantedAt = new Date().toISOString();
      } else {
        this.permissions.push({
          userId,
          repositoryId,
          accessLevel,
          grantedAt: new Date().toISOString(),
          grantedBy: 'admin' // In production, would use current user
        });
      }

      this.log(`✓ Granted ${accessLevel} access to ${repo.name} for ${user.login}`);
      this.logAccess('access_granted', userId, `Repo: ${repo.name}, Level: ${accessLevel}`);
      return true;
    } catch (error) {
      this.log(`Access grant error: ${error}`, 'error');
      return false;
    }
  }

  /**
   * Revoke repository access
   */
  async revokeRepositoryAccess(userId: string, repositoryId: string): Promise<boolean> {
    try {
      const index = this.permissions.findIndex(
        p => p.userId === userId && p.repositoryId === repositoryId
      );

      if (index === -1) {
        this.log(`Permission not found for ${userId}`, 'error');
        return false;
      }

      const permission = this.permissions[index];
      const user = this.accounts.get(userId);
      const repo = this.repositories.get(repositoryId);

      this.permissions.splice(index, 1);

      this.log(`✓ Revoked access to ${repo?.name} for ${user?.login}`);
      this.logAccess('access_revoked', userId, `Repo: ${repo?.name}`);
      return true;
    } catch (error) {
      this.log(`Access revocation error: ${error}`, 'error');
      return false;
    }
  }

  /**
   * Check user's permission for repository
   */
  canAccessRepository(userId: string, repositoryId: string): boolean {
    return this.permissions.some(
      p => p.userId === userId && p.repositoryId === repositoryId
    );
  }

  /**
   * Get user's account details
   */
  getAccount(userId: string): GitHubUserAccount | undefined {
    return this.accounts.get(userId);
  }

  /**
   * Get all registered accounts
   */
  getAllAccounts(): GitHubUserAccount[] {
    return Array.from(this.accounts.values());
  }

  /**
   * Get user's permissions
   */
  getUserPermissions(userId: string): AccountPermission[] {
    return this.permissions.filter(p => p.userId === userId);
  }

  /**
   * Get access audit log
   */
  getAccessLog(): Array<{ timestamp: string; action: string; userId: string; details: string }> {
    return [...this.accessLog];
  }

  /**
   * Log access event
   */
  private logAccess(action: string, userId: string, details: string): void {
    this.accessLog.push({
      timestamp: new Date().toISOString(),
      action,
      userId,
      details
    });

    // Bounded log (keep last 5,000 entries)
    if (this.accessLog.length > 10000) {
      this.accessLog = this.accessLog.slice(-5000);
    }
  }

  /**
   * Generate account summary
   */
  generateAccountSummary(): {
    totalAccounts: number;
    totalRepositories: number;
    totalPermissions: number;
    accounts: string[];
  } {
    return {
      totalAccounts: this.accounts.size,
      totalRepositories: this.repositories.size,
      totalPermissions: this.permissions.length,
      accounts: Array.from(this.accounts.values()).map(a => a.login)
    };
  }

  /**
   * Log to output channel
   */
  private log(message: string, severity: 'info' | 'error' = 'info'): void {
    const prefix = severity.toUpperCase();
    this.outputChannel.appendLine(`[${new Date().toISOString()}] [${prefix}] ${message}`);
  }
}

export function createGitHubAccountManager(): GitHubAccountManager {
  return new GitHubAccountManager();
}
