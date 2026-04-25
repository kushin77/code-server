/**
 * @file apps/copilot-engine/src/github-scanner.js
 * @module copilot-engine/github-scanner
 * @description GitHub GraphQL scanner with pagination, retries, and backoff.
 */

const DEFAULT_TIMEOUT_MS = 20_000;
const DEFAULT_MAX_RETRIES = 4;
const DEFAULT_BASE_BACKOFF_MS = 500;

/**
 * @typedef {{
 *   token: string,
 *   owner: string,
 *   perPage?: number,
 *   maxRetries?: number,
 *   baseBackoffMs?: number,
 *   timeoutMs?: number,
 *   fetchFn?: typeof fetch,
 *   sleepFn?: (ms: number) => Promise<void>,
 * }} ScannerOptions
 */

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function isRetryableStatus(status) {
  return status === 429 || status === 500 || status === 502 || status === 503 || status === 504;
}

function parseRateLimitReset(headers) {
  const reset = headers?.get?.("x-ratelimit-reset");
  if (!reset) return null;
  const asSeconds = Number(reset);
  if (!Number.isFinite(asSeconds)) return null;
  return asSeconds * 1000;
}

function computeBackoffMs(attempt, baseBackoffMs, rateLimitResetAtMs) {
  if (rateLimitResetAtMs && rateLimitResetAtMs > Date.now()) {
    return Math.max(rateLimitResetAtMs - Date.now(), baseBackoffMs);
  }
  const jitter = Math.floor(Math.random() * 100);
  return baseBackoffMs * Math.pow(2, attempt) + jitter;
}

/**
 * @param {ScannerOptions} options
 */
export function createGitHubScanner(options) {
  const {
    token,
    owner,
    perPage = 50,
    maxRetries = DEFAULT_MAX_RETRIES,
    baseBackoffMs = DEFAULT_BASE_BACKOFF_MS,
    timeoutMs = DEFAULT_TIMEOUT_MS,
    fetchFn = globalThis.fetch,
    sleepFn = sleep,
  } = options;

  if (!token) throw new Error("GitHub token is required");
  if (!owner) throw new Error("GitHub owner is required");
  if (typeof fetchFn !== "function") {
    throw new Error("fetch implementation is required");
  }

  /**
   * @param {string} query
   * @param {Record<string, any>} variables
   */
  async function graphql(query, variables) {
    let lastError = null;

    for (let attempt = 0; attempt <= maxRetries; attempt++) {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), timeoutMs);

      try {
        const response = await fetchFn("https://api.github.com/graphql", {
          method: "POST",
          headers: {
            Authorization: `Bearer ${token}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ query, variables }),
          signal: controller.signal,
        });

        const rateLimitResetAt = parseRateLimitReset(response.headers);

        if (!response.ok) {
          const text = await response.text();
          const err = new Error(`GitHub GraphQL HTTP ${response.status}: ${text.slice(0, 500)}`);
          err.status = response.status;
          err.rateLimitResetAt = rateLimitResetAt;

          if (attempt < maxRetries && isRetryableStatus(response.status)) {
            await sleepFn(computeBackoffMs(attempt, baseBackoffMs, rateLimitResetAt));
            continue;
          }

          throw err;
        }

        const payload = await response.json();

        if (Array.isArray(payload.errors) && payload.errors.length > 0) {
          const isRateLimit = payload.errors.some(
            (e) => /rate limit/i.test(e?.message ?? "") || e?.type === "RATE_LIMITED"
          );
          const err = new Error(`GitHub GraphQL error: ${payload.errors[0].message}`);
          err.rateLimit = isRateLimit;
          err.rateLimitResetAt = rateLimitResetAt;

          if (attempt < maxRetries && isRateLimit) {
            await sleepFn(computeBackoffMs(attempt, baseBackoffMs, rateLimitResetAt));
            continue;
          }

          throw err;
        }

        return payload.data;
      } catch (err) {
        lastError = err;
        const aborted = err?.name === "AbortError";
        const retryable = aborted || isRetryableStatus(err?.status);

        if (attempt < maxRetries && retryable) {
          await sleepFn(computeBackoffMs(attempt, baseBackoffMs, err?.rateLimitResetAt));
          continue;
        }
        throw err;
      } finally {
        clearTimeout(timeout);
      }
    }

    throw lastError ?? new Error("GraphQL call failed");
  }

  async function fetchAllRepositories() {
    const repos = [];
    let cursor = null;
    let hasNextPage = true;

    const query = `
      query($owner: String!, $perPage: Int!, $after: String) {
        repositoryOwner(login: $owner) {
          repositories(first: $perPage, after: $after, orderBy: { field: PUSHED_AT, direction: DESC }) {
            pageInfo { hasNextPage endCursor }
            nodes {
              name
              description
              isArchived
              pushedAt
              primaryLanguage { name }
            }
          }
        }
      }
    `;

    while (hasNextPage) {
      const data = await graphql(query, { owner, perPage, after: cursor });
      const conn = data?.repositoryOwner?.repositories;
      const pageNodes = Array.isArray(conn?.nodes) ? conn.nodes : [];
      repos.push(...pageNodes);
      hasNextPage = Boolean(conn?.pageInfo?.hasNextPage);
      cursor = conn?.pageInfo?.endCursor ?? null;
    }

    return repos;
  }

  async function fetchAllRepoIssuesAndPRs(repoName) {
    const issues = [];
    const pullRequests = [];

    // Issues pagination
    let issueCursor = null;
    let hasMoreIssues = true;
    const issueQuery = `
      query($owner: String!, $repo: String!, $perPage: Int!, $after: String) {
        repository(owner: $owner, name: $repo) {
          issues(first: $perPage, after: $after, states: [OPEN, CLOSED], orderBy: { field: UPDATED_AT, direction: DESC }) {
            pageInfo { hasNextPage endCursor }
            nodes {
              number
              title
              state
              createdAt
              updatedAt
              closedAt
              labels(first: 20) { nodes { name } }
            }
          }
        }
      }
    `;

    while (hasMoreIssues) {
      const data = await graphql(issueQuery, {
        owner,
        repo: repoName,
        perPage,
        after: issueCursor,
      });
      const conn = data?.repository?.issues;
      const nodes = Array.isArray(conn?.nodes) ? conn.nodes : [];
      issues.push(...nodes);
      hasMoreIssues = Boolean(conn?.pageInfo?.hasNextPage);
      issueCursor = conn?.pageInfo?.endCursor ?? null;
    }

    // PR pagination
    let prCursor = null;
    let hasMorePrs = true;
    const prQuery = `
      query($owner: String!, $repo: String!, $perPage: Int!, $after: String) {
        repository(owner: $owner, name: $repo) {
          pullRequests(first: $perPage, after: $after, states: [OPEN, CLOSED, MERGED], orderBy: { field: UPDATED_AT, direction: DESC }) {
            pageInfo { hasNextPage endCursor }
            nodes {
              number
              title
              state
              isDraft
              createdAt
              updatedAt
              mergedAt
              closingIssuesReferences(first: 20) { nodes { number } }
              labels(first: 20) { nodes { name } }
            }
          }
        }
      }
    `;

    while (hasMorePrs) {
      const data = await graphql(prQuery, {
        owner,
        repo: repoName,
        perPage,
        after: prCursor,
      });
      const conn = data?.repository?.pullRequests;
      const nodes = Array.isArray(conn?.nodes) ? conn.nodes : [];

      for (const pr of nodes) {
        pullRequests.push({
          ...pr,
          linkedIssues: (pr?.closingIssuesReferences?.nodes ?? [])
            .map((i) => Number(i?.number))
            .filter(Number.isFinite),
        });
      }

      hasMorePrs = Boolean(conn?.pageInfo?.hasNextPage);
      prCursor = conn?.pageInfo?.endCursor ?? null;
    }

    return { issues, pullRequests };
  }

  async function scan() {
    const startedAt = Date.now();
    const failures = [];

    const repos = await fetchAllRepositories();
    const repoResults = [];

    for (const repo of repos) {
      if (repo?.isArchived) continue;

      try {
        const result = await fetchAllRepoIssuesAndPRs(repo.name);
        repoResults.push({
          repo: repo.name,
          issues: result.issues,
          pullRequests: result.pullRequests,
        });
      } catch (error) {
        failures.push({
          repo: repo.name,
          error: error?.message ?? String(error),
        });
      }
    }

    const totalIssues = repoResults.reduce((acc, r) => acc + r.issues.length, 0);
    const totalPRs = repoResults.reduce((acc, r) => acc + r.pullRequests.length, 0);

    return {
      owner,
      started_at: new Date(startedAt).toISOString(),
      completed_at: new Date().toISOString(),
      duration_ms: Date.now() - startedAt,
      counts: {
        repositories: repoResults.length,
        issues: totalIssues,
        pull_requests: totalPRs,
        failures: failures.length,
      },
      failures,
      repositories: repoResults,
    };
  }

  return {
    scan,
    fetchAllRepositories,
    fetchAllRepoIssuesAndPRs,
  };
}
