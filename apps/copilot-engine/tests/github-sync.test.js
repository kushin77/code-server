import test from "node:test";
import assert from "node:assert/strict";

import {
  classifyGitHubWork,
  classifyIssue,
  classifyPullRequest,
  scanGitHubGraphQL,
} from "../src/github-sync.js";
import { CopilotMemory } from "../src/memory.js";

test("classifyIssue marks closed issue with merged PR as completed", () => {
  const issue = { number: 42, state: "closed", labels: [], updatedAt: "2026-04-20T00:00:00Z" };
  const prByIssue = new Map([[42, { number: 100, state: "merged" }]]);
  const result = classifyIssue(issue, prByIssue, {
    issueStalledDays: 30,
    now: new Date("2026-04-25T00:00:00Z"),
  });

  assert.equal(result.status, "completed");
  assert.equal(result.reason, "closed_with_merged_pr");
});

test("classifyPullRequest uses configurable stalled threshold", () => {
  const pr = { number: 10, state: "open", labels: [], updatedAt: "2026-04-20T00:00:00Z" };

  const blocked = classifyPullRequest(pr, {
    prStalledDays: 2,
    now: new Date("2026-04-25T00:00:00Z"),
  });
  assert.equal(blocked.status, "blocked");
  assert.equal(blocked.reason, "stalled_pr_threshold");

  const inProgress = classifyPullRequest(pr, {
    prStalledDays: 10,
    now: new Date("2026-04-25T00:00:00Z"),
  });
  assert.equal(inProgress.status, "in_progress");
});

test("classifyGitHubWork extracts and persists issue-PR linkage in memory context", () => {
  const classified = classifyGitHubWork(
    {
      issues: [
        { number: 1, state: "open", labels: [], updatedAt: "2026-04-24T00:00:00Z" },
        { number: 2, state: "closed", labels: ["wontfix"], updatedAt: "2026-04-24T00:00:00Z" },
      ],
      pullRequests: [
        {
          number: 11,
          state: "open",
          labels: [],
          updatedAt: "2026-04-24T00:00:00Z",
          linkedIssues: [1],
        },
      ],
    },
    {
      issueStalledDays: 30,
      prStalledDays: 14,
      now: new Date("2026-04-25T00:00:00Z"),
    }
  );

  assert.deepEqual(classified.issue_pr_links, [{ issue_number: 1, pr_number: 11 }]);

  const memory = new CopilotMemory();
  memory.ingestGitHubClassification(classified);
  const snapshot = memory.exportSnapshot();

  assert.deepEqual(snapshot.github_context.issue_pr_links, [
    { issue_number: 1, pr_number: 11 },
  ]);
  assert.equal(snapshot.github_context.thresholds.issue_stalled_days, 30);
  assert.equal(snapshot.github_context.thresholds.pr_stalled_days, 14);
  assert.equal(snapshot.github_context.summary.deferred, 1);
});

test("scanGitHubGraphQL paginates repositories and nested issues/prs", async () => {
  const calls = [];
  const executeQuery = async (query, variables) => {
    calls.push({ query, variables });

    if (query.includes("query OrgRepos")) {
      if (!variables.after) {
        return {
          data: {
            organization: {
              repositories: {
                nodes: [{ nameWithOwner: "acme/repo-a" }],
                pageInfo: { hasNextPage: true, endCursor: "repo-cursor-1" },
              },
            },
          },
        };
      }
      return {
        data: {
          organization: {
            repositories: {
              nodes: [{ nameWithOwner: "acme/repo-b" }],
              pageInfo: { hasNextPage: false, endCursor: null },
            },
          },
        },
      };
    }

    if (query.includes("query RepoIssues") && variables.name === "repo-a") {
      return {
        data: {
          repository: {
            issues: {
              nodes: [
                {
                  number: 1,
                  state: "OPEN",
                  updatedAt: "2026-04-25T00:00:00Z",
                  labels: { nodes: [{ name: "bug" }] },
                },
              ],
              pageInfo: { hasNextPage: false, endCursor: null },
            },
          },
        },
      };
    }

    if (query.includes("query RepoIssues") && variables.name === "repo-b") {
      return {
        data: {
          repository: {
            issues: {
              nodes: [
                {
                  number: 2,
                  state: "OPEN",
                  updatedAt: "2026-04-25T00:00:00Z",
                  labels: { nodes: [] },
                },
              ],
              pageInfo: { hasNextPage: false, endCursor: null },
            },
          },
        },
      };
    }

    if (query.includes("query RepoPullRequests") && variables.name === "repo-a") {
      return {
        data: {
          repository: {
            pullRequests: {
              nodes: [
                {
                  number: 10,
                  state: "OPEN",
                  merged: false,
                  updatedAt: "2026-04-25T00:00:00Z",
                  labels: { nodes: [] },
                  closingIssuesReferences: { nodes: [{ number: 1 }] },
                },
              ],
              pageInfo: { hasNextPage: false, endCursor: null },
            },
          },
        },
      };
    }

    if (query.includes("query RepoPullRequests") && variables.name === "repo-b") {
      return {
        data: {
          repository: {
            pullRequests: {
              nodes: [],
              pageInfo: { hasNextPage: false, endCursor: null },
            },
          },
        },
      };
    }

    throw new Error("Unexpected query");
  };

  const result = await scanGitHubGraphQL({
    org: "acme",
    executeQuery,
    pageSize: 1,
    maxRetries: 1,
    sleepFn: async () => {},
  });

  assert.equal(result.summary.repo_count, 2);
  assert.equal(result.summary.issue_count, 2);
  assert.equal(result.summary.pull_request_count, 1);
  assert.deepEqual(result.issue_pr_links, [{ issue_number: 1, pr_number: 10 }]);
  assert.equal(
    calls.filter((c) => String(c.query).includes("query OrgRepos")).length,
    2
  );
});

test("scanGitHubGraphQL retries transient failures with backoff", async () => {
  let attempts = 0;
  const sleepCalls = [];
  const executeQuery = async (query) => {
    if (!String(query).includes("query OrgRepos")) {
      return {
        data: {
          repository: {
            issues: { nodes: [], pageInfo: { hasNextPage: false, endCursor: null } },
            pullRequests: { nodes: [], pageInfo: { hasNextPage: false, endCursor: null } },
          },
        },
      };
    }

    attempts += 1;
    if (attempts === 1) {
      const err = new Error("rate limit exceeded");
      err.status = 429;
      err.retryAfterMs = 10;
      throw err;
    }
    return {
      data: {
        organization: {
          repositories: {
            nodes: [{ nameWithOwner: "acme/repo-a" }],
            pageInfo: { hasNextPage: false, endCursor: null },
          },
        },
      },
    };
  };

  const result = await scanGitHubGraphQL({
    org: "acme",
    executeQuery,
    maxRetries: 2,
    sleepFn: async (ms) => {
      sleepCalls.push(ms);
    },
  });

  assert.equal(result.summary.retries, 1);
  assert.equal(sleepCalls.length, 1);
  assert.equal(result.summary.failures.length, 0);
  assert.equal(result.summary.repo_count, 1);
});

test("scanGitHubGraphQL reports failures in summary", async () => {
  const executeQuery = async (query, variables) => {
    if (String(query).includes("query OrgRepos")) {
      return {
        data: {
          organization: {
            repositories: {
              nodes: [{ nameWithOwner: "acme/repo-a" }],
              pageInfo: { hasNextPage: false, endCursor: null },
            },
          },
        },
      };
    }
    if (String(query).includes("query RepoIssues")) {
      throw new Error(`issues unavailable for ${variables.name}`);
    }
    return {
      data: {
        repository: {
          pullRequests: {
            nodes: [],
            pageInfo: { hasNextPage: false, endCursor: null },
          },
        },
      },
    };
  };

  const result = await scanGitHubGraphQL({
    org: "acme",
    executeQuery,
    maxRetries: 0,
    sleepFn: async () => {},
  });

  assert.equal(result.summary.repo_count, 1);
  assert.equal(result.summary.issue_count, 0);
  assert.equal(result.summary.pull_request_count, 0);
  assert.equal(result.summary.failures.length, 1);
  assert.equal(result.summary.failures[0].scope, "repository_issues");
  assert.equal(result.summary.failures[0].repository, "acme/repo-a");
  assert.ok(result.summary.duration_ms >= 0);
});
