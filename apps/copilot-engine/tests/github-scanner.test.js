import test from "node:test";
import assert from "node:assert/strict";

import { createGitHubScanner } from "../src/github-scanner.js";

function createMockResponse({ ok = true, status = 200, body = {}, headers = {} }) {
  return {
    ok,
    status,
    headers: {
      get(name) {
        return headers[name.toLowerCase()] ?? null;
      },
    },
    async json() {
      return body;
    },
    async text() {
      return JSON.stringify(body);
    },
  };
}

test("scanner paginates repositories and returns summary counts", async () => {
  const calls = [];
  const fetchFn = async (_url, init) => {
    const payload = JSON.parse(init.body);
    calls.push(payload);

    if (payload.variables.repo === "repo-a" && payload.query.includes("issues(first")) {
      if (!payload.variables.after) {
        return createMockResponse({
          body: {
            data: {
              repository: {
                issues: {
                  pageInfo: { hasNextPage: false, endCursor: null },
                  nodes: [{ number: 1, state: "OPEN", updatedAt: "2026-04-25T00:00:00Z" }],
                },
              },
            },
          },
        });
      }
    }

    if (payload.variables.repo === "repo-b") {
      if (payload.query.includes("issues(first")) {
        return createMockResponse({
          body: {
            data: {
              repository: {
                issues: {
                  pageInfo: { hasNextPage: false, endCursor: null },
                  nodes: [],
                },
              },
            },
          },
        });
      }
      return createMockResponse({
        body: {
          data: {
            repository: {
              pullRequests: {
                pageInfo: { hasNextPage: false, endCursor: null },
                nodes: [],
              },
            },
          },
        },
      });
    }

    // Repo listing pagination
    if (!payload.variables.repo && !payload.variables.after) {
      return createMockResponse({
        body: {
          data: {
            repositoryOwner: {
              repositories: {
                pageInfo: { hasNextPage: true, endCursor: "cursor-2" },
                nodes: [{ name: "repo-a", isArchived: false }],
              },
            },
          },
        },
      });
    }

    if (!payload.variables.repo && payload.variables.after === "cursor-2") {
      return createMockResponse({
        body: {
          data: {
            repositoryOwner: {
              repositories: {
                pageInfo: { hasNextPage: false, endCursor: null },
                nodes: [{ name: "repo-b", isArchived: false }],
              },
            },
          },
        },
      });
    }

    if (payload.variables.repo === "repo-a" && payload.query.includes("pullRequests(first")) {
      return createMockResponse({
        body: {
          data: {
            repository: {
              pullRequests: {
                pageInfo: { hasNextPage: false, endCursor: null },
                nodes: [
                  {
                    number: 10,
                    state: "OPEN",
                    updatedAt: "2026-04-25T00:00:00Z",
                    closingIssuesReferences: { nodes: [{ number: 1 }] },
                  },
                ],
              },
            },
          },
        },
      });
    }

    throw new Error(`Unexpected query payload: ${JSON.stringify(payload)}`);
  };

  const scanner = createGitHubScanner({
    token: "t",
    owner: "o",
    perPage: 1,
    fetchFn,
    sleepFn: async () => {},
  });

  const out = await scanner.scan();

  assert.equal(out.counts.repositories, 2);
  assert.equal(out.counts.issues, 1);
  assert.equal(out.counts.pull_requests, 1);
  assert.equal(out.counts.failures, 0);
  assert.equal(Array.isArray(out.failures), true);
  assert.ok(out.duration_ms >= 0);

  // Confirm linked issue was normalized into linkedIssues array
  const repoA = out.repositories.find((r) => r.repo === "repo-a");
  assert.deepEqual(repoA.pullRequests[0].linkedIssues, [1]);
  assert.ok(calls.length >= 5);
});

test("scanner retries and backs off on transient/rate-limit errors", async () => {
  let attempts = 0;
  const sleeps = [];

  const fetchFn = async (_url, _init) => {
    attempts += 1;
    if (attempts === 1) {
      return createMockResponse({
        ok: false,
        status: 429,
        headers: { "x-ratelimit-reset": String(Math.floor((Date.now() + 5) / 1000)) },
        body: { message: "rate limited" },
      });
    }

    return createMockResponse({
      body: {
        data: {
          repositoryOwner: {
            repositories: {
              pageInfo: { hasNextPage: false, endCursor: null },
              nodes: [],
            },
          },
        },
      },
    });
  };

  const scanner = createGitHubScanner({
    token: "t",
    owner: "o",
    fetchFn,
    sleepFn: async (ms) => {
      sleeps.push(ms);
    },
  });

  const repos = await scanner.fetchAllRepositories();
  assert.deepEqual(repos, []);
  assert.ok(attempts >= 2);
  assert.equal(sleeps.length, 1);
  assert.ok(sleeps[0] >= 1);
});
