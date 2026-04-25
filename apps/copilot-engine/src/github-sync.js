/**
 * @file apps/copilot-engine/src/github-sync.js
 * @module copilot-engine/github-sync
 * @description Classify GitHub issues/PRs into normalized work statuses and
 *   extract issue-PR links for memory ingestion.
 */

const DEFAULT_STALLED_DAYS_ISSUE = 30;
const DEFAULT_STALLED_DAYS_PR = 14;
const DEFAULT_SCAN_PAGE_SIZE = 50;
const DEFAULT_SCAN_MAX_RETRIES = 3;
const DEFAULT_SCAN_BASE_DELAY_MS = 250;
const DEFAULT_SCAN_MAX_DELAY_MS = 4_000;

const ORG_REPOS_QUERY = `
query OrgRepos($org: String!, $after: String, $first: Int!) {
  organization(login: $org) {
    repositories(first: $first, after: $after, orderBy: { field: UPDATED_AT, direction: DESC }) {
      nodes {
        nameWithOwner
      }
      pageInfo {
        hasNextPage
        endCursor
      }
    }
  }
}`;

const REPO_ISSUES_QUERY = `
query RepoIssues($owner: String!, $name: String!, $after: String, $first: Int!) {
  repository(owner: $owner, name: $name) {
    issues(first: $first, after: $after, orderBy: { field: UPDATED_AT, direction: DESC }) {
      nodes {
        number
        state
        updatedAt
        labels(first: 20) {
          nodes {
            name
          }
        }
      }
      pageInfo {
        hasNextPage
        endCursor
      }
    }
  }
}`;

const REPO_PULLS_QUERY = `
query RepoPullRequests($owner: String!, $name: String!, $after: String, $first: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequests(first: $first, after: $after, orderBy: { field: UPDATED_AT, direction: DESC }) {
      nodes {
        number
        state
        merged
        updatedAt
        labels(first: 20) {
          nodes {
            name
          }
        }
        closingIssuesReferences(first: 20) {
          nodes {
            number
          }
        }
      }
      pageInfo {
        hasNextPage
        endCursor
      }
    }
  }
}`;

/**
 * @typedef {{
 *   issueStalledDays?: number,
 *   prStalledDays?: number,
 *   now?: Date
 * }} ClassificationConfig
 */

/**
 * @param {ClassificationConfig | undefined} config
 * @returns {{issueStalledDays: number, prStalledDays: number, now: Date}}
 */
function normalizeConfig(config = {}) {
  const issueStalledDays =
    Number.isFinite(config.issueStalledDays) && config.issueStalledDays > 0
      ? config.issueStalledDays
      : DEFAULT_STALLED_DAYS_ISSUE;
  const prStalledDays =
    Number.isFinite(config.prStalledDays) && config.prStalledDays > 0
      ? config.prStalledDays
      : DEFAULT_STALLED_DAYS_PR;
  const now = config.now instanceof Date ? config.now : new Date();
  return { issueStalledDays, prStalledDays, now };
}

/**
 * @param {string} value
 * @returns {string}
 */
function normalizeLabel(value) {
  return String(value ?? "")
    .trim()
    .toLowerCase();
}

/**
 * @param {unknown} labels
 * @returns {string[]}
 */
function extractLabels(labels) {
  if (!labels) return [];
  if (Array.isArray(labels)) {
    return labels
      .map((l) => (typeof l === "string" ? l : l?.name))
      .filter(Boolean)
      .map(normalizeLabel);
  }
  return [];
}

/**
 * @param {string | undefined | null} iso
 * @returns {Date | null}
 */
function parseDate(iso) {
  if (!iso) return null;
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? null : d;
}

/**
 * @param {Date | null} from
 * @param {Date} now
 * @returns {number}
 */
function daysSince(from, now) {
  if (!from) return Infinity;
  return Math.floor((now.getTime() - from.getTime()) / (1000 * 60 * 60 * 24));
}

/**
 * @param {number} ms
 * @returns {Promise<void>}
 */
function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * @param {unknown} err
 * @returns {boolean}
 */
function isRetryableError(err) {
  const message = String(err?.message ?? "").toLowerCase();
  const status = Number(err?.status ?? err?.statusCode);
  if (status === 429) return true;
  if (status >= 500 && status <= 599) return true;
  return (
    message.includes("rate limit") ||
    message.includes("timeout") ||
    message.includes("tempor") ||
    message.includes("econnreset")
  );
}

/**
 * @param {unknown} err
 * @returns {number | null}
 */
function retryAfterMs(err) {
  const v = Number(err?.retryAfterMs ?? err?.retry_after_ms ?? err?.retryAfter);
  return Number.isFinite(v) && v > 0 ? v : null;
}

/**
 * @param {number} attempt
 * @param {number} baseDelayMs
 * @param {number} maxDelayMs
 * @param {number | null} retryAfter
 * @returns {number}
 */
function computeBackoffMs(attempt, baseDelayMs, maxDelayMs, retryAfter) {
  if (retryAfter !== null) return Math.min(retryAfter, maxDelayMs);
  const exp = Math.min(baseDelayMs * Math.pow(2, attempt), maxDelayMs);
  const jitter = Math.floor(Math.random() * Math.max(1, Math.floor(exp * 0.2)));
  return Math.min(exp + jitter, maxDelayMs);
}

/**
 * @param {() => Promise<any>} operation
 * @param {{
 *  maxRetries: number,
 *  baseDelayMs: number,
 *  maxDelayMs: number,
 *  sleepFn?: (ms: number) => Promise<void>
 * }} options
 */
async function withRetry(operation, options) {
  const {
    maxRetries,
    baseDelayMs,
    maxDelayMs,
    sleepFn = sleep,
  } = options;

  let lastError;
  for (let attempt = 0; attempt <= maxRetries; attempt += 1) {
    try {
      return await operation();
    } catch (err) {
      lastError = err;
      if (attempt >= maxRetries || !isRetryableError(err)) {
        throw err;
      }
      const delayMs = computeBackoffMs(
        attempt,
        baseDelayMs,
        maxDelayMs,
        retryAfterMs(err)
      );
      await sleepFn(delayMs);
    }
  }

  throw lastError;
}

/**
 * @param {string} nameWithOwner
 * @returns {{owner: string, name: string} | null}
 */
function splitRepoName(nameWithOwner) {
  const [owner, ...rest] = String(nameWithOwner ?? "").split("/");
  const name = rest.join("/");
  if (!owner || !name) return null;
  return { owner, name };
}

/**
 * @param {{nodes?: any[], pageInfo?: {hasNextPage?: boolean, endCursor?: string | null}} | null | undefined} conn
 * @returns {{nodes: any[], hasNextPage: boolean, endCursor: string | null}}
 */
function normalizeConnection(conn) {
  return {
    nodes: Array.isArray(conn?.nodes) ? conn.nodes : [],
    hasNextPage: Boolean(conn?.pageInfo?.hasNextPage),
    endCursor: conn?.pageInfo?.endCursor ?? null,
  };
}

/**
 * Scan GitHub org repos/issues/PRs using GraphQL with pagination and retries.
 *
 * @param {{
 *  org: string,
 *  executeQuery: (query: string, variables: Record<string, unknown>) => Promise<any>,
 *  pageSize?: number,
 *  maxRetries?: number,
 *  baseDelayMs?: number,
 *  maxDelayMs?: number,
 *  sleepFn?: (ms: number) => Promise<void>,
 *  now?: Date,
 * }} options
 * @returns {Promise<{
 *  repos: Array<{nameWithOwner: string}>,
 *  issues: any[],
 *  pullRequests: any[],
 *  issue_pr_links: Array<{issue_number: number, pr_number: number}>,
 *  summary: {
 *    repo_count: number,
 *    issue_count: number,
 *    pull_request_count: number,
 *    duration_ms: number,
 *    retries: number,
 *    failures: Array<{scope: string, repository?: string, message: string}>
 *  }
 * }>} 
 */
export async function scanGitHubGraphQL(options) {
  const {
    org,
    executeQuery,
    pageSize = DEFAULT_SCAN_PAGE_SIZE,
    maxRetries = DEFAULT_SCAN_MAX_RETRIES,
    baseDelayMs = DEFAULT_SCAN_BASE_DELAY_MS,
    maxDelayMs = DEFAULT_SCAN_MAX_DELAY_MS,
    sleepFn = sleep,
    now = new Date(),
  } = options ?? {};

  if (!org || typeof org !== "string") {
    throw new Error("scanGitHubGraphQL requires a non-empty org");
  }
  if (typeof executeQuery !== "function") {
    throw new Error("scanGitHubGraphQL requires executeQuery(query, variables)");
  }

  const startedAt = now.getTime();
  let retryCount = 0;
  /** @type {Array<{scope: string, repository?: string, message: string}>} */
  const failures = [];
  const repos = [];
  const issues = [];
  const pullRequests = [];

  const safeExecute = async (scope, query, variables, repository) => {
    return withRetry(
      async () => executeQuery(query, variables),
      {
        maxRetries,
        baseDelayMs,
        maxDelayMs,
        sleepFn: async (ms) => {
          retryCount += 1;
          return sleepFn(ms);
        },
      }
    ).catch((err) => {
      failures.push({
        scope,
        repository,
        message: String(err?.message ?? err),
      });
      return null;
    });
  };

  let repoCursor = null;
  do {
    const response = await safeExecute(
      "org_repositories",
      ORG_REPOS_QUERY,
      { org, first: pageSize, after: repoCursor },
      undefined
    );
    if (!response) break;

    const conn = normalizeConnection(
      response?.data?.organization?.repositories
    );
    repos.push(...conn.nodes.map((r) => ({ nameWithOwner: r?.nameWithOwner })));
    repoCursor = conn.hasNextPage ? conn.endCursor : null;
  } while (repoCursor);

  for (const repo of repos) {
    const parsed = splitRepoName(repo.nameWithOwner);
    if (!parsed) {
      failures.push({
        scope: "repository_parse",
        repository: repo.nameWithOwner,
        message: "Invalid repository identifier",
      });
      continue;
    }

    let issueCursor = null;
    do {
      const response = await safeExecute(
        "repository_issues",
        REPO_ISSUES_QUERY,
        {
          owner: parsed.owner,
          name: parsed.name,
          first: pageSize,
          after: issueCursor,
        },
        repo.nameWithOwner
      );
      if (!response) break;

      const conn = normalizeConnection(response?.data?.repository?.issues);
      for (const node of conn.nodes) {
        issues.push({
          repository: repo.nameWithOwner,
          number: node?.number,
          state: normalizeLabel(node?.state),
          updatedAt: node?.updatedAt,
          labels: (node?.labels?.nodes ?? []).map((l) => l?.name),
        });
      }
      issueCursor = conn.hasNextPage ? conn.endCursor : null;
    } while (issueCursor);

    let prCursor = null;
    do {
      const response = await safeExecute(
        "repository_pull_requests",
        REPO_PULLS_QUERY,
        {
          owner: parsed.owner,
          name: parsed.name,
          first: pageSize,
          after: prCursor,
        },
        repo.nameWithOwner
      );
      if (!response) break;

      const conn = normalizeConnection(response?.data?.repository?.pullRequests);
      for (const node of conn.nodes) {
        pullRequests.push({
          repository: repo.nameWithOwner,
          number: node?.number,
          state: node?.merged ? "merged" : normalizeLabel(node?.state),
          updatedAt: node?.updatedAt,
          labels: (node?.labels?.nodes ?? []).map((l) => l?.name),
          linkedIssues: (node?.closingIssuesReferences?.nodes ?? []).map(
            (i) => i?.number
          ),
        });
      }
      prCursor = conn.hasNextPage ? conn.endCursor : null;
    } while (prCursor);
  }

  const links = extractIssuePrLinks(issues, pullRequests);

  return {
    repos,
    issues,
    pullRequests,
    issue_pr_links: links,
    summary: {
      repo_count: repos.length,
      issue_count: issues.length,
      pull_request_count: pullRequests.length,
      duration_ms: Math.max(0, Date.now() - startedAt),
      retries: retryCount,
      failures,
    },
  };
}

/**
 * Classify one issue.
 * @param {any} issue
 * @param {Map<number, any>} prByIssueNumber
 * @param {{issueStalledDays: number, now: Date}} config
 * @returns {{status: "completed"|"in_progress"|"blocked"|"deferred", reason: string, days_stalled?: number}}
 */
export function classifyIssue(issue, prByIssueNumber, config) {
  const labels = extractLabels(issue?.labels);
  const state = normalizeLabel(issue?.state);
  const linkedPr = prByIssueNumber.get(Number(issue?.number));

  if (state === "closed") {
    if (linkedPr && normalizeLabel(linkedPr.state) === "merged") {
      return { status: "completed", reason: "closed_with_merged_pr" };
    }
    if (labels.includes("wontfix") || labels.includes("duplicate")) {
      return { status: "deferred", reason: "closed_with_deferred_label" };
    }
    return { status: "deferred", reason: "closed_without_merged_pr" };
  }

  if (labels.includes("blocked")) {
    return { status: "blocked", reason: "blocked_label" };
  }

  const staleDays = daysSince(parseDate(issue?.updatedAt), config.now);
  if (staleDays > config.issueStalledDays) {
    return {
      status: "blocked",
      reason: "stalled_issue_threshold",
      days_stalled: staleDays,
    };
  }

  if (linkedPr) {
    return { status: "in_progress", reason: "linked_open_pr" };
  }

  return { status: "in_progress", reason: "open_issue_active" };
}

/**
 * Classify one pull request.
 * @param {any} pr
 * @param {{prStalledDays: number, now: Date}} config
 * @returns {{status: "completed"|"in_progress"|"blocked"|"deferred", reason: string, days_stalled?: number}}
 */
export function classifyPullRequest(pr, config) {
  const state = normalizeLabel(pr?.state);
  const labels = extractLabels(pr?.labels);

  if (state === "merged") {
    return { status: "completed", reason: "merged" };
  }

  if (state === "closed") {
    return { status: "deferred", reason: "closed_unmerged" };
  }

  const staleDays = daysSince(parseDate(pr?.updatedAt), config.now);
  if (labels.includes("blocked") || staleDays > config.prStalledDays) {
    return {
      status: "blocked",
      reason: labels.includes("blocked")
        ? "blocked_label"
        : "stalled_pr_threshold",
      days_stalled: staleDays,
    };
  }

  return { status: "in_progress", reason: "open_pr_active" };
}

/**
 * Build issue↔PR links from explicit references.
 *
 * Expected input shape:
 * - issue.number
 * - pr.number
 * - pr.linkedIssues?: Array<number>
 *
 * @param {any[]} issues
 * @param {any[]} prs
 * @returns {{issue_number: number, pr_number: number}[]}
 */
export function extractIssuePrLinks(issues, prs) {
  const validIssueNumbers = new Set(
    (issues ?? []).map((i) => Number(i?.number)).filter(Number.isFinite)
  );
  const links = [];

  for (const pr of prs ?? []) {
    const prNumber = Number(pr?.number);
    if (!Number.isFinite(prNumber)) continue;
    const linkedIssues = Array.isArray(pr?.linkedIssues) ? pr.linkedIssues : [];

    for (const issueNo of linkedIssues) {
      const issueNumber = Number(issueNo);
      if (!Number.isFinite(issueNumber)) continue;
      if (!validIssueNumbers.has(issueNumber)) continue;
      links.push({ issue_number: issueNumber, pr_number: prNumber });
    }
  }

  return links;
}

/**
 * Normalize GitHub work into classified issue/PR sets and persisted linkage.
 * @param {{issues?: any[], pullRequests?: any[]}} input
 * @param {ClassificationConfig} [config]
 */
export function classifyGitHubWork(input, config = {}) {
  const normalized = normalizeConfig(config);
  const issues = Array.isArray(input?.issues) ? input.issues : [];
  const pullRequests = Array.isArray(input?.pullRequests)
    ? input.pullRequests
    : [];

  const links = extractIssuePrLinks(issues, pullRequests);
  const prByIssueNumber = new Map();

  for (const link of links) {
    const pr = pullRequests.find((p) => Number(p?.number) === link.pr_number);
    if (!pr) continue;
    const state = normalizeLabel(pr.state);
    if (state === "open" || state === "merged") {
      prByIssueNumber.set(link.issue_number, pr);
    }
  }

  const classifiedIssues = issues.map((issue) => ({
    ...issue,
    classification: classifyIssue(issue, prByIssueNumber, normalized),
  }));

  const classifiedPullRequests = pullRequests.map((pr) => ({
    ...pr,
    classification: classifyPullRequest(pr, normalized),
  }));

  return {
    thresholds: {
      issue_stalled_days: normalized.issueStalledDays,
      pr_stalled_days: normalized.prStalledDays,
    },
    issue_pr_links: links,
    issues: classifiedIssues,
    pullRequests: classifiedPullRequests,
  };
}
