// @file        commitlint.config.cjs
// @module      ci/commitlint
// @description Conventional Commits enforcement for PR linting
// @governance  GOV-002: Git hygiene, standardized commit messages
// Issue #1534: Repository Governance — Git Hygiene, SSOT

/** @type {import('@commitlint/types').UserConfig} */
module.exports = {
  extends: ["@commitlint/config-conventional"],

  // Extend with project-specific commit types
  rules: {
    "type-enum": [
      2,
      "always",
      [
        // Standard conventional commit types
        "feat",       // New feature
        "fix",        // Bug fix
        "docs",       // Documentation only
        "style",      // Formatting (no logic change)
        "refactor",   // Code change that neither fixes nor adds feature
        "perf",       // Performance improvement
        "test",       // Adding/fixing tests
        "build",      // Build system changes (docker, npm, etc.)
        "ci",         // CI/CD changes
        "chore",      // Maintenance tasks
        "revert",     // Revert a commit

        // Project-specific types
        "ops",        // Operational changes (runbooks, scripts)
        "infra",      // Infrastructure as Code (Terraform, Compose)
        "security",   // Security fixes or hardening
        "iac",        // Infrastructure as Code changes (GOV-002)
      ],
    ],

    // Scope must be lowercase alphanumeric with hyphens
    "scope-case": [2, "always", "lower-case"],

    // Subject line: 10-100 characters
    "subject-min-length": [2, "always", 10],
    "subject-max-length": [2, "always", 120],

    // No period at end of subject
    "subject-full-stop": [2, "never", "."],

    // Header max 140 chars (type + scope + subject)
    "header-max-length": [2, "always", 140],

    // Body lines max 100 chars
    "body-max-line-length": [1, "always", 100],  // warn, not error
  },

  // Ignore merge commits and automated commits
  ignores: [
    (commit) => commit.startsWith("Merge "),
    (commit) => commit.startsWith("Revert "),
    (commit) => /^chore\(release\):/.test(commit),
  ],
};
