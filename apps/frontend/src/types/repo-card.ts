/**
 * @file        apps/frontend/src/types/repo-card.ts
 * @module      frontend/types
 * @description Type contracts for the Multi-Repo Home View repo cards. Closes #719.
 */

/**
 * Identity and status data for a single repository card.
 * Refreshed at the interval configured by policy `home_view_refresh_interval_seconds`.
 */
export interface RepoCard {
  /** Stable repo identifier (sha256 of canonical_path[:12]) */
  repoId: string;
  /** Display name of the repository (basename of canonical path) */
  name: string;
  /** Canonical absolute path to repo root */
  canonicalPath: string;
  /** Git remote origin URL (optional) */
  remoteUrl?: string;
  /** Active branch / ref */
  branch: string;
  /** Whether working tree has uncommitted changes */
  isDirty: boolean;
  /** CI pipeline status for the current branch */
  ciStatus: 'passing' | 'failing' | 'pending' | 'unknown';
  /** ISO 8601 timestamp of last git commit in this repo */
  lastActivity: string;
  /** Whether this repo is pinned/favourited by the user */
  isPinned: boolean;
  /** Whether this repo is currently active in the workspace */
  isActive: boolean;
  /** Error state if repo is unreachable or auth has failed */
  error?: RepoCardError;
  /** Timestamp when this card data was last refreshed */
  refreshedAt: string;
}

export interface RepoCardError {
  /** Error category */
  type: 'offline' | 'auth_failure' | 'path_missing' | 'git_error' | 'unknown';
  /** Human-readable error description */
  message: string;
  /** Suggested remediation hint for display */
  remediationHint: string;
}

/**
 * Actions available on each repo card.
 * All actions respect the user's repo access permissions.
 */
export type RepoCardAction =
  | 'switch'        // Switch active workspace to this repo
  | 'open_new_tab'  // Open repo in a new workspace tab
  | 'pull'          // git pull on this repo
  | 'open_prs'      // Open PR list for this repo
  | 'open_issues'   // Open issue list for this repo
  | 'open_runbook'  // Open repo runbook if present
  | 'pin'           // Pin/favourite this repo
  | 'unpin';        // Unpin/unfavourite this repo

/**
 * Actions available on each repo card.
 * All actions respect the user's repo access permissions.
 */  /** Show error cards for unreachable repos (default: true) */
  showErrors: boolean;
}
