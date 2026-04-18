#!/usr/bin/env node
// @file        scripts/lib/merge-settings.js
// @module      ide/policy
// @description Merge enterprise code-server settings into user settings while preserving locked T1 keys.

const fs = require("fs");

const LOCKED_KEYS = new Set([
  "__policy_version",
  "__policy_date",
  "__policy_tier_legend",
  "editor.formatOnSave",
  "editor.formatOnPaste",
  "files.trimTrailingWhitespace",
  "files.insertFinalNewline",
  "files.trimFinalNewlines",
  "editor.renderWhitespace",
  "editor.tabSize",
  "editor.insertSpaces",
  "editor.detectIndentation",
  "editor.rulers",
  "files.exclude",
  "search.exclude",
  "telemetry.telemetryLevel",
  "extensions.autoCheckUpdates",
  "extensions.autoUpdate",
  "update.mode",
  "security.workspace.trust.enabled",
  "security.workspace.trust.startupPrompt",
  "git.requireGitUserConfig",
  "git.branchProtection",
  "git.branchProtectionPrompt",
  "git.enableCommitSigning",
  "git.autofetch",
  "git.confirmSync",
  "git.allowForcePush",
  "git.rebaseWhenSync",
  "git.mergeEditor",
  "git.enableSmartCommit",
  "git.postCommitCommand",
  "github.branchProtection",
  "terminal.integrated.env.linux"
]);

function stripJsonComments(input) {
  let output = "";
  let inString = false;
  let inLineComment = false;
  let inBlockComment = false;
  let escaped = false;

  for (let index = 0; index < input.length; index += 1) {
    const current = input[index];
    const next = input[index + 1];

    if (inLineComment) {
      if (current === "\n") {
        inLineComment = false;
        output += current;
      }
      continue;
    }

    if (inBlockComment) {
      if (current === "*" && next === "/") {
        inBlockComment = false;
        index += 1;
      }
      continue;
    }

    if (!inString && current === "/" && next === "/") {
      inLineComment = true;
      index += 1;
      continue;
    }

    if (!inString && current === "/" && next === "*") {
      inBlockComment = true;
      index += 1;
      continue;
    }

    output += current;

    if (current === '"' && !escaped) {
      inString = !inString;
    }

    escaped = current === "\\" && !escaped;
    if (current !== "\\") {
      escaped = false;
    }
  }

  return output;
}

function readJsonc(filePath) {
  if (!filePath || !fs.existsSync(filePath)) {
    return {};
  }

  const raw = fs.readFileSync(filePath, "utf8").trim();
  if (!raw) {
    return {};
  }

  return JSON.parse(stripJsonComments(raw));
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function clone(value) {
  if (Array.isArray(value)) {
    return value.map(clone);
  }
  if (isPlainObject(value)) {
    return Object.fromEntries(Object.entries(value).map(([key, nested]) => [key, clone(nested)]));
  }
  return value;
}

function deepMerge(base, overlay) {
  const result = clone(base);

  for (const [key, value] of Object.entries(overlay)) {
    if (isPlainObject(result[key]) && isPlainObject(value)) {
      result[key] = deepMerge(result[key], value);
      continue;
    }
    result[key] = clone(value);
  }

  return result;
}

function applyLockedKeys(merged, enterprise) {
  for (const key of LOCKED_KEYS) {
    if (Object.prototype.hasOwnProperty.call(enterprise, key)) {
      merged[key] = clone(enterprise[key]);
    }
  }
  return merged;
}

function main() {
  const [, , enterprisePath, userPath, outputPath] = process.argv;
  if (!enterprisePath || !userPath || !outputPath) {
    console.error("Usage: merge-settings.js <enterprise-settings> <user-settings> <output>");
    process.exit(1);
  }

  const enterprise = readJsonc(enterprisePath);
  const user = readJsonc(userPath);
  const merged = applyLockedKeys(deepMerge(enterprise, user), enterprise);
  fs.writeFileSync(outputPath, `${JSON.stringify(merged, null, 2)}\n`, "utf8");
}

main();