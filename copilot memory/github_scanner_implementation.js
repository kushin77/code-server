/**
 * GitHub Repository Scanner → Copilot Memory Ingestion
 * Scans all repos, issues, PRs, code, and synthesizes into decision-locked goals
 * Model: Claude Sonnet 4 (for copilot turns)
 * Scanner: GitHub GraphQL API
 */

const Anthropic = require("@anthropic-ai/sdk");

// ============================================================================
// GITHUB API CLIENT
// ============================================================================

class GitHubScanner {
  constructor(token) {
    this.token = token;
    this.apiUrl = "https://api.github.com/graphql";
    this.callCount = 0;
    this.lastResetTime = Date.now();
  }

  async query(query, variables = {}) {
    // Rate limiting: 5000 points/hour for GraphQL
    // Rough cost: 1 point per query
    this.callCount++;

    const response = await fetch(this.apiUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${this.token}`,
      },
      body: JSON.stringify({ query, variables }),
    });

    if (!response.ok) {
      throw new Error(`GitHub API error: ${response.status} ${response.statusText}`);
    }

    const data = await response.json();
    if (data.errors) {
      console.error("GraphQL errors:", data.errors);
      throw new Error(`GraphQL error: ${data.errors[0].message}`);
    }

    return data.data;
  }

  async fetchAllRepos(owner) {
    console.log(`📦 Fetching all repos for ${owner}...`);
    const repos = [];
    let hasNextPage = true;
    let cursor = null;

    while (hasNextPage) {
      const query = `
        query($owner: String!, $after: String) {
          repositoryOwner(login: $owner) {
            repositories(first: 100, after: $after, orderBy: {field: PUSHED_AT, direction: DESC}) {
              pageInfo { hasNextPage, endCursor }
              nodes {
                name
                description
                url
                primaryLanguage { name }
                isArchived
                pushedAt
                defaultBranchRef { name }
              }
            }
          }
        }
      `;

      const data = await this.query(query, { owner, after: cursor });
      const repoData = data.repositoryOwner.repositories;

      repos.push(...repoData.nodes);
      hasNextPage = repoData.pageInfo.hasNextPage;
      cursor = repoData.pageInfo.endCursor;
    }

    console.log(`✓ Found ${repos.length} repos`);
    return repos;
  }

  async fetchIssuesAndPRs(owner, repo) {
    console.log(`  📋 Scanning ${repo} issues/PRs...`);

    const query = `
      query($owner: String!, $repo: String!) {
        repository(owner: $owner, name: $repo) {
          issues(first: 100, states: [OPEN, CLOSED], orderBy: {field: UPDATED_AT, direction: DESC}) {
            nodes {
              number
              title
              body
              state
              createdAt
              updatedAt
              closedAt
              labels(first: 20) { nodes { name } }
              assignees(first: 5) { nodes { login } }
              milestone { title, dueOn }
            }
          }
          pullRequests(first: 100, states: [OPEN, MERGED, CLOSED], orderBy: {field: UPDATED_AT, direction: DESC}) {
            nodes {
              number
              title
              state
              createdAt
              mergedAt
              updatedAt
              reviews(first: 10) { nodes { state } }
              commits(first: 100) { totalCount }
              additions
              deletions
              labels(first: 20) { nodes { name } }
            }
          }
        }
      }
    `;

    const data = await this.query(query, { owner, repo });
    return {
      issues: data.repository.issues.nodes,
      pullRequests: data.repository.pullRequests.nodes,
    };
  }

  async scanCodeForTODOs(owner, repo) {
    console.log(`  🔍 Scanning ${repo} for TODOs...`);
    // Simplified: use GitHub search API
    // In production, use REST API: GET /search/code?q=TODO+in:file+repo:owner/repo
    // For now, return empty array (you'd implement this with GitHub REST API)
    return [];
  }
}

// ============================================================================
// GITHUB DATA → MEMORY GOAL SYNTHESIZER
// ============================================================================

class GitHubMemorySynthesizer {
  constructor() {
    this.snapshot = null;
  }

  async synthesize(owner, scanner) {
    console.log("\n🔄 GITHUB SCANNING PHASE\n");

    const repos = await scanner.fetchAllRepos(owner);
    const repoSnapshot = [];
    const allGoals = [];
    let totalIssues = 0;
    let totalPRs = 0;

    for (const repo of repos) {
      if (repo.isArchived) continue; // Skip archived repos

      const { issues, pullRequests } = await scanner.fetchIssuesAndPRs(owner, repo.name);
      const todos = await scanner.scanCodeForTODOs(owner, repo.name);

      totalIssues += issues.length;
      totalPRs += pullRequests.length;

      // Synthesize into goals
      const repoGoals = this.synthesizeRepoGoals(repo, issues, pullRequests, todos);
      allGoals.push(...repoGoals);

      repoSnapshot.push({
        name: repo.name,
        description: repo.description,
        language: repo.primaryLanguage?.name || "unknown",
        pushedAt: repo.pushedAt,
        issues: issues.length,
        pullRequests: pullRequests.length,
        goals: repoGoals,
      });
    }

    this.snapshot = {
      scanned_at: new Date().toISOString(),
      org_or_user: owner,
      total_repos: repos.length,
      total_issues: totalIssues,
      total_prs: totalPRs,
      repos: repoSnapshot,
      all_goals: allGoals,
    };

    return this.snapshot;
  }

  synthesizeRepoGoals(repo, issues, pullRequests, todos) {
    const goals = [];

    // Domain inference (heuristic based on repo name/language)
    const domain = this.inferDomain(repo.name, repo.primaryLanguage?.name);

    // Process each issue
    for (const issue of issues) {
      const relatedPR = pullRequests.find((pr) => pr.title.includes(issue.number.toString()));
      const goal = {
        id: `goal_github_${repo.name}_${issue.number}`,
        domain,
        repo: repo.name,
        intent: issue.title,
        status: issue.state === "CLOSED" ? "completed" : "in_progress",
        github_issue: `#${issue.number}`,
        github_pr: relatedPR ? `#${relatedPR.number}` : null,
        created_at: issue.createdAt,
        updated_at: issue.updatedAt,
        closed_at: issue.closedAt,
        labels: issue.labels.map((l) => l.name),
        assignee: issue.assignees[0]?.login || null,
        milestone: issue.milestone?.title || null,
        days_open: Math.floor((Date.now() - new Date(issue.createdAt).getTime()) / (1000 * 60 * 60 * 24)),
        is_blocked:
          issue.state === "OPEN" &&
          (issue.labels.some((l) => l.name === "blocked") ||
            new Date(issue.updatedAt).getTime() < Date.now() - 30 * 24 * 60 * 60 * 1000), // No activity >30 days
      };
      goals.push(goal);
    }

    // Add technical debt goals for each TODO
    for (const todo of todos) {
      goals.push({
        id: `goal_debt_${repo.name}_todo_${Math.random().toString(36).slice(7)}`,
        domain,
        repo: repo.name,
        intent: `Technical debt: ${todo.description}`,
        status: "deferred",
        type: "technical_debt",
        severity: "medium",
        created_at: new Date().toISOString(),
      });
    }

    return goals;
  }

  inferDomain(repoName, language) {
    const name = repoName.toLowerCase();
    const lang = (language || "").toLowerCase();

    if (
      name.includes("flowci") ||
      name.includes("gitpeak") ||
      lang.includes("javascript") ||
      lang.includes("typescript")
    ) {
      return "code";
    }
    if (
      name.includes("elevated") ||
      name.includes("vault") ||
      name.includes("terraform") ||
      lang.includes("hcl")
    ) {
      return "infra";
    }
    if (name.includes("exposed") || name.includes("real-estate")) {
      return "product";
    }
    if (name.includes("anim") || name.includes("media")) {
      return "product";
    }
    return "code"; // default
  }
}

// ============================================================================
// MEMORY INTEGRATION
// ============================================================================

class CopilotMemoryWithGitHub {
  constructor(baseMemory) {
    this.baseMemory = baseMemory;
    this.githubSnapshot = null;
  }

  async importGitHubSnapshot(snapshot) {
    this.githubSnapshot = snapshot;
    console.log(`\n📥 Importing ${snapshot.all_goals.length} goals from GitHub...`);

    // Merge GitHub goals into session goals
    for (const goal of snapshot.all_goals) {
      // Check if goal already exists (by repo + issue number)
      const exists = this.baseMemory.intentMap.session_goals.some(
        (g) => g.github_issue === goal.github_issue && g.repo === goal.repo
      );

      if (!exists) {
        this.baseMemory.intentMap.session_goals.push(goal);
      }
    }

    // Update active context with GitHub stats
    this.baseMemory.intentMap.active_context.github_stats = {
      total_repos: snapshot.total_repos,
      total_issues: snapshot.total_issues,
      total_prs: snapshot.total_prs,
      last_scan: snapshot.scanned_at,
    };

    console.log(`✓ Imported GitHub snapshot`);
  }

  exportMemoryContextWithGitHub() {
    const baseContext = this.baseMemory.exportMemoryContext();

    // Add GitHub-specific context
    if (this.githubSnapshot) {
      const inProgressGoals = this.baseMemory.intentMap.session_goals.filter(
        (g) => g.status === "in_progress"
      );
      const blockedGoals = this.baseMemory.intentMap.session_goals.filter((g) => g.is_blocked);

      baseContext.github_context = {
        repos_scanned: this.githubSnapshot.total_repos,
        issues_total: this.githubSnapshot.total_issues,
        issues_in_progress: inProgressGoals.length,
        issues_blocked: blockedGoals.length,
        issues_completed: this.baseMemory.intentMap.session_goals.filter(
          (g) => g.status === "completed"
        ).length,
        last_scan: this.githubSnapshot.scanned_at,
      };
    }

    return baseContext;
  }
}

// ============================================================================
// ENHANCED COPILOT WITH GITHUB AWARENESS
// ============================================================================

const client = new Anthropic();

const GITHUB_AWARE_SYSTEM_PROMPT = `You are an autonomous enterprise copilot with deep expertise across:
- Code/DevOps: FlowCI, GitPeak, CI/CD, Terraform, Kubernetes, Git governance
- Cloud/Infrastructure: ElevatedIQ.ai, VaultOS, cloud security, compliance, storage
- Sales/GTM: LinkedIn/Google Ads, email nurture, Chrome extensions, conversion funnels
- Product: AnimForge, EXPOSED.ai, real estate intelligence, AI video production

GITHUB INTEGRATION:
You now have access to a comprehensive GitHub snapshot of all repositories:
- Completed goals (merged PRs, closed issues)
- In-progress work (open PRs, active issues, days stalled)
- Blockers (issues marked 'blocked' or inactive >30 days)
- Technical debt (TODOs, deprecated patterns)

WHEN USER ASKS ABOUT PRIORITIES/STATUS:
1. Reference specific GitHub issue/PR numbers (#123)
2. Surface in-progress goals and their status (PR awaiting review, days stalled)
3. Flag blockers and cross-repo dependencies
4. Recommend technical debt consolidation if quick wins exist

GITHUB-AWARE TRIGGERS:
- "What should I prioritize next?" → show in-progress + blocked goals from GitHub
- "What's the status of X?" → look up GitHub issue #X
- "Any quick wins?" → recommend technical debt fixes or stalled PRs needing review
- "Refresh GitHub status" → scan GitHub immediately (user-initiated)

CORE MANDATE (unchanged):
1. Never repeat yourself. Check GitHub history.
2. Expose conflicts. If suggesting something that contradicts a prior decision, ask first.
3. Lock decisions. Once committed, future advice aligns with it.
4. Tag everything. Every suggestion goes into memory with timestamp and domain.
5. Assume nothing. State all assumptions upfront.`;

async function chatWithGitHub(userMessage, memory, domain = null) {
  console.log("\n--- GITHUB-AWARE COPILOT TURN ---");

  // Check for duplicates (existing logic)
  const dupCheck = await checkForDuplicates(userMessage, memory);
  if (dupCheck.isDuplicate) {
    console.log(`⚠️  DUPLICATE DETECTED`);
    return {
      type: "duplicate_flag",
      message: dupCheck.message,
    };
  }

  // NEW: Check if user is asking for GitHub status
  if (
    userMessage.toLowerCase().includes("refresh") &&
    userMessage.toLowerCase().includes("github")
  ) {
    return {
      type: "action_required",
      message: "GitHub refresh requested. Run: await scanAndUpdate()",
    };
  }

  // Inject GitHub-aware memory context
  const memoryContext = memory.exportMemoryContextWithGitHub();
  const enrichedSystemPrompt = `${GITHUB_AWARE_SYSTEM_PROMPT}

[GITHUB MEMORY CONTEXT]
Repos scanned: ${memoryContext.github_context?.repos_scanned || 0}
Issues in progress: ${memoryContext.github_context?.issues_in_progress || 0}
Issues blocked: ${memoryContext.github_context?.issues_blocked || 0}
Issues completed: ${memoryContext.github_context?.issues_completed || 0}
Last scan: ${memoryContext.github_context?.last_scan || "never"}

[SESSION GOALS FROM GITHUB]
${memoryContext.active_goals
  .filter((g) => g.github_issue)
  .slice(0, 10)
  .map((g) => `- ${g.github_issue}: ${g.intent} (${g.status})`)
  .join("\n")}`;

  // Call Claude
  const response = await client.messages.create({
    model: "claude-sonnet-4-20250514",
    max_tokens: 2000,
    temperature: 0.7,
    system: enrichedSystemPrompt,
    messages: [
      {
        role: "user",
        content: userMessage,
      },
    ],
  });

  const assistantMessage = response.content[0].type === "text" ? response.content[0].text : "";

  return {
    type: "response",
    message: assistantMessage,
    github_context: memoryContext.github_context,
  };
}

// ============================================================================
// FULL WORKFLOW
// ============================================================================

async function scanAndUpdateMemory(org, githubToken, baseMemory) {
  console.log("\n🚀 STARTING GITHUB SCAN → MEMORY UPDATE\n");

  const scanner = new GitHubScanner(githubToken);
  const synthesizer = new GitHubMemorySynthesizer();

  // Phase 1: Scan GitHub
  const snapshot = await synthesizer.synthesize(org, scanner);
  console.log(`\n✓ Scan complete:`);
  console.log(`  Repos: ${snapshot.total_repos}`);
  console.log(`  Issues: ${snapshot.total_issues}`);
  console.log(`  PRs: ${snapshot.total_prs}`);
  console.log(`  Goals extracted: ${snapshot.all_goals.length}`);

  // Phase 2: Import into memory
  const enhancedMemory = new CopilotMemoryWithGitHub(baseMemory);
  await enhancedMemory.importGitHubSnapshot(snapshot);

  console.log(`\n✓ Memory updated with GitHub goals`);
  return enhancedMemory;
}

// ============================================================================
// EXAMPLE USAGE
// ============================================================================

async function demo() {
  const githubOrg = "your-github-org"; // e.g., "anthropics"
  const githubToken = process.env.GITHUB_TOKEN;

  if (!githubToken) {
    console.error("Set GITHUB_TOKEN environment variable");
    return;
  }

  // Initialize base memory
  const baseMemory = new CopilotMemory();

  // Scan GitHub and import
  const enhancedMemory = await scanAndUpdateMemory(githubOrg, githubToken, baseMemory);

  // Now use the copilot with GitHub awareness
  console.log("\n💬 COPILOT TURN 1: Ask about priorities\n");
  let result = await chatWithGitHub("What should I prioritize next?", enhancedMemory);
  console.log("Copilot:", result.message.slice(0, 300) + "...");
  console.log("GitHub context:", result.github_context);

  // Second turn
  console.log("\n💬 COPILOT TURN 2: Ask about status\n");
  result = await chatWithGitHub("What's the status of GitPeak?", enhancedMemory);
  console.log("Copilot:", result.message.slice(0, 300) + "...");
}

// Uncomment to run demo:
// demo().catch(console.error);

module.exports = {
  GitHubScanner,
  GitHubMemorySynthesizer,
  CopilotMemoryWithGitHub,
  chatWithGitHub,
  scanAndUpdateMemory,
};
