#!/usr/bin/env bash
# @file        scripts/ci/validate-pnpm-workspace-catalog.sh
# @module      ci/monorepo
# @description Validates pnpm workspace membership, catalog usage, and internal
#              workspace protocol enforcement.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

require_file "$ROOT_DIR/pnpm-workspace.yaml" "pnpm workspace file is required"
require_file "$ROOT_DIR/.npmrc" "pnpm npmrc is required"
require_file "$ROOT_DIR/package.json" "root package.json is required"
NODE_CMD=""

if command -v node >/dev/null 2>&1; then
  NODE_CMD="node"
else
  log_fatal "node is required for pnpm catalog validation"
fi

NODE_ROOT_DIR="$ROOT_DIR"

log_info "Validating pnpm workspace catalog and protocol policy"

"$NODE_CMD" --input-type=module - "$NODE_ROOT_DIR" <<'NODE'
import fs from "fs";
import path from "path";

const rootDir = process.argv[2] ?? process.env.ROOT_DIR;
const errors = [];

function addError(message) {
  errors.push(message);
}

function readText(relativePath) {
  const resolvedPath = path.isAbsolute(relativePath) ? relativePath : path.join(rootDir, relativePath);
  return fs.readFileSync(resolvedPath, "utf8");
}

function readJson(relativePath) {
  return JSON.parse(readText(relativePath));
}

function collectPackageFiles(startDir) {
  const files = [];
  if (!fs.existsSync(startDir)) {
    return files;
  }

  const ignoredDirs = new Set(["node_modules", "dist", "build", "coverage", "test-results", ".git"]);

  function walk(currentDir) {
    for (const entry of fs.readdirSync(currentDir, { withFileTypes: true })) {
      if (entry.isDirectory()) {
        if (ignoredDirs.has(entry.name)) {
          continue;
        }
        walk(path.join(currentDir, entry.name));
        continue;
      }

      if (entry.isFile() && entry.name === "package.json") {
        files.push(path.join(currentDir, entry.name));
      }
    }
  }

  walk(startDir);
  return files;
}

const workspaceText = readText("pnpm-workspace.yaml");
const npmrcText = readText(".npmrc");

for (const token of [
  "- apps/backend",
  "- apps/frontend",
  "- apps/session-broker",
  "- apps/extensions/*",
  "- tests/e2e",
]) {
  if (!workspaceText.includes(token)) {
    addError(`pnpm-workspace.yaml is missing workspace entry: ${token}`);
  }
}

if (!workspaceText.includes("catalog:")) {
  addError("pnpm-workspace.yaml is missing the default catalog block");
}

if (!npmrcText.includes("save-workspace-protocol=true")) {
  addError(".npmrc must set save-workspace-protocol=true");
}

if (!npmrcText.includes("strict-peer-dependencies=true")) {
  addError(".npmrc must set strict-peer-dependencies=true");
}

if (!npmrcText.includes("shamefully-hoist=false")) {
  addError(".npmrc must set shamefully-hoist=false");
}

const catalogEntries = new Map();
const workspaceLines = workspaceText.split(/\r?\n/);
const catalogStart = workspaceLines.findIndex((line) => line.trim() === "catalog:");

if (catalogStart === -1) {
  addError("pnpm-workspace.yaml catalog block was not found");
} else {
  for (let index = catalogStart + 1; index < workspaceLines.length; index += 1) {
    const line = workspaceLines[index];
    if (!line.startsWith("  ")) {
      break;
    }

    const match = line.match(/^  (?:"([^"]+)"|([^:]+)):\s*(.+)$/);
    if (!match) {
      continue;
    }

    const key = match[1] ?? match[2];
    const value = match[3].trim();
    catalogEntries.set(key, value);
  }
}

const packageFiles = [
  "package.json",
  ...collectPackageFiles(path.join(rootDir, "apps")),
  ...collectPackageFiles(path.join(rootDir, "tests", "e2e")),
];

const manifests = packageFiles.map((relativePath) => {
  const json = readJson(relativePath);
  return {
    relativePath,
    name: json.name ?? path.basename(path.dirname(relativePath)),
    json,
  };
});

const workspaceNames = new Set(
  manifests
    .filter((manifest) => manifest.relativePath !== "package.json")
    .map((manifest) => manifest.json.name)
    .filter(Boolean),
);

const dependencySections = ["dependencies", "devDependencies", "peerDependencies", "optionalDependencies"];
const dependencyUsage = new Map();

for (const manifest of manifests) {
  for (const section of dependencySections) {
    const dependencies = manifest.json[section] ?? {};
    for (const [dependencyName, versionSpec] of Object.entries(dependencies)) {
      if (!dependencyUsage.has(dependencyName)) {
        dependencyUsage.set(dependencyName, []);
      }

      dependencyUsage.get(dependencyName).push({
        manifest,
        section,
        versionSpec,
      });
    }
  }
}

for (const [dependencyName, uses] of dependencyUsage.entries()) {
  const isWorkspaceDependency = workspaceNames.has(dependencyName);

  if (isWorkspaceDependency) {
    for (const use of uses) {
      if (use.versionSpec !== "workspace:^") {
        addError(`${use.manifest.relativePath} must reference internal package ${dependencyName} with workspace:^ (found ${use.versionSpec})`);
      }
    }
    continue;
  }

  if (uses.length < 2) {
    continue;
  }

  if (!catalogEntries.has(dependencyName)) {
    addError(`pnpm-workspace.yaml catalog is missing shared dependency ${dependencyName}`);
  }

  for (const use of uses) {
    if (!String(use.versionSpec).startsWith("catalog:")) {
      addError(`${use.manifest.relativePath} must use catalog: for shared dependency ${dependencyName} (found ${use.versionSpec})`);
    }
  }
}

for (const [dependencyName, catalogVersion] of catalogEntries.entries()) {
  const uses = dependencyUsage.get(dependencyName) ?? [];
  if (uses.length >= 2 && uses.some((use) => !String(use.versionSpec).startsWith("catalog:"))) {
    addError(`catalog entry ${dependencyName} = ${catalogVersion} is defined but not consumed via catalog: everywhere`);
  }
}

if (errors.length > 0) {
  for (const error of errors) {
    console.error(error);
  }
  process.exit(1);
}

console.log("pnpm workspace catalog policy validated");
NODE

log_info "pnpm workspace catalog policy validation passed"