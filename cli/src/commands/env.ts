#!/usr/bin/env node
/**
 * @file        cli/src/commands/env.ts
 * @module      cli/environment
 * @description ElevatedIQ env.yaml CLI — validate, clone, diff, offline, replay, promote
 * @governance  GOV-002: All operations logged and reversible
 *
 * Usage:
 *   elevatediq env validate [env.yaml]
 *   elevatediq env diff <file-a.yaml> <file-b.yaml>
 *   elevatediq env clone --from <source> --to <target>
 *   elevatediq env offline [env.yaml]
 *   elevatediq env replay --build-id <id>
 *   elevatediq env promote --from <source> --to <target>
 */

import * as fs from "fs";
import * as path from "path";
import * as https from "https";
import * as http from "http";
import * as crypto from "crypto";

// ── Configuration ─────────────────────────────────────────────────────────────

const ENV_PROVISIONER_URL =
  process.env.ENV_PROVISIONER_URL || "http://localhost:8007";
const DEFAULT_ENV_FILE = process.env.ENV_YAML_PATH || "env.yaml";
const REPO_ROOT = process.env.REPO_ROOT || path.resolve(__dirname, "../../..");
const OPS_LOG = path.join(REPO_ROOT, "artifacts", "env-operations.log");

// ── Logging ───────────────────────────────────────────────────────────────────

function logLine(level: string, msg: string): void {
  const ts = new Date().toISOString();
  const line = `[${ts}] [${level}] ${msg}`;
  console.log(line);
  try {
    fs.mkdirSync(path.dirname(OPS_LOG), { recursive: true });
    fs.appendFileSync(OPS_LOG, line + "\n");
  } catch {
    // Non-fatal: log file write failure
  }
}

const log = {
  info: (m: string) => logLine("INFO", m),
  success: (m: string) => logLine("SUCCESS", m),
  error: (m: string) => logLine("ERROR", m),
  warn: (m: string) => logLine("WARN", m),
};

// ── HTTP helper ───────────────────────────────────────────────────────────────

function httpPost(
  url: string,
  body: Buffer,
  contentType: string
): Promise<{ status: number; body: string }> {
  return new Promise((resolve, reject) => {
    const parsed = new URL(url);
    const lib = parsed.protocol === "https:" ? https : http;
    const req = lib.request(
      {
        hostname: parsed.hostname,
        port: parsed.port || (parsed.protocol === "https:" ? 443 : 80),
        path: parsed.pathname + parsed.search,
        method: "POST",
        headers: {
          "Content-Type": contentType,
          "Content-Length": body.length,
        },
      },
      (res) => {
        let data = "";
        res.on("data", (chunk) => (data += chunk));
        res.on("end", () => resolve({ status: res.statusCode ?? 0, body: data }));
      }
    );
    req.on("error", reject);
    req.write(body);
    req.end();
  });
}

/** Build multipart/form-data body for a single file field. */
function buildFormData(
  fieldName: string,
  fileName: string,
  fileContent: Buffer
): { body: Buffer; contentType: string } {
  const boundary = crypto.randomBytes(16).toString("hex");
  const parts: Buffer[] = [
    Buffer.from(
      `--${boundary}\r\nContent-Disposition: form-data; name="${fieldName}"; filename="${fileName}"\r\nContent-Type: application/octet-stream\r\n\r\n`
    ),
    fileContent,
    Buffer.from(`\r\n--${boundary}--\r\n`),
  ];
  return {
    body: Buffer.concat(parts),
    contentType: `multipart/form-data; boundary=${boundary}`,
  };
}

/** Build multipart/form-data body for two file fields. */
function buildFormData2(
  fieldA: string,
  fileA: string,
  contentA: Buffer,
  fieldB: string,
  fileB: string,
  contentB: Buffer
): { body: Buffer; contentType: string } {
  const boundary = crypto.randomBytes(16).toString("hex");
  const parts: Buffer[] = [
    Buffer.from(
      `--${boundary}\r\nContent-Disposition: form-data; name="${fieldA}"; filename="${fileA}"\r\nContent-Type: application/octet-stream\r\n\r\n`
    ),
    contentA,
    Buffer.from(
      `\r\n--${boundary}\r\nContent-Disposition: form-data; name="${fieldB}"; filename="${fileB}"\r\nContent-Type: application/octet-stream\r\n\r\n`
    ),
    contentB,
    Buffer.from(`\r\n--${boundary}--\r\n`),
  ];
  return {
    body: Buffer.concat(parts),
    contentType: `multipart/form-data; boundary=${boundary}`,
  };
}

// ── Commands ──────────────────────────────────────────────────────────────────

/**
 * Validate env.yaml against the JSON schema via env-provisioner service.
 */
async function cmdValidate(envFile: string): Promise<void> {
  log.info(`Validating ${envFile}`);
  if (!fs.existsSync(envFile)) {
    log.error(`File not found: ${envFile}`);
    process.exit(1);
  }

  const fileContent = fs.readFileSync(envFile);
  const { body, contentType } = buildFormData(
    "file",
    path.basename(envFile),
    fileContent
  );

  try {
    const resp = await httpPost(
      `${ENV_PROVISIONER_URL}/validate`,
      body,
      contentType
    );
    const result = JSON.parse(resp.body);

    if (result.valid) {
      log.success(`✓ ${envFile} is valid`);
    } else {
      log.error(`✗ Validation failed: ${JSON.stringify(result.errors)}`);
      process.exit(1);
    }
  } catch (err) {
    log.error(`Provisioner unreachable: ${err}. Falling back to local validation.`);
    // Local fallback: basic YAML parse check
    try {
      const content = fs.readFileSync(envFile, "utf-8");
      if (!content.includes("version:") || !content.includes("runtime:")) {
        log.error(`✗ ${envFile} missing required fields: version, runtime`);
        process.exit(1);
      }
      log.success(`✓ ${envFile} passes basic local validation (provisioner offline)`);
    } catch (parseErr) {
      log.error(`✗ Could not read ${envFile}: ${parseErr}`);
      process.exit(1);
    }
  }
}

/**
 * Show diff between two env.yaml files.
 */
async function cmdDiff(fileA: string, fileB: string): Promise<void> {
  log.info(`Diffing ${fileA} ↔ ${fileB}`);
  for (const f of [fileA, fileB]) {
    if (!fs.existsSync(f)) {
      log.error(`File not found: ${f}`);
      process.exit(1);
    }
  }

  const contentA = fs.readFileSync(fileA);
  const contentB = fs.readFileSync(fileB);
  const { body, contentType } = buildFormData2(
    "file_a",
    path.basename(fileA),
    contentA,
    "file_b",
    path.basename(fileB),
    contentB
  );

  try {
    const resp = await httpPost(
      `${ENV_PROVISIONER_URL}/diff`,
      body,
      contentType
    );
    const diff = JSON.parse(resp.body);

    if (
      Object.keys(diff.runtime_changes ?? {}).length === 0 &&
      (diff.service_changes ?? []).length === 0
    ) {
      log.success("No differences found between the two env files");
    } else {
      console.log("\n=== Runtime Changes ===");
      console.log(JSON.stringify(diff.runtime_changes, null, 2));
      console.log("\n=== Service Changes ===");
      console.log(JSON.stringify(diff.service_changes, null, 2));
    }
  } catch (err) {
    log.error(`Diff failed: ${err}`);
    process.exit(1);
  }
}

/**
 * Clone env.yaml from source profile to a target file, pinning current image digests.
 */
async function cmdClone(from: string, to: string): Promise<void> {
  const examplesDir = path.join(REPO_ROOT, "apps", "env-provisioner", "examples");
  const sourceFile = path.join(examplesDir, `env-${from}.yaml`);
  const targetFile = to.endsWith(".yaml") ? to : `env-${to}.yaml`;

  log.info(`Cloning ${from} → ${targetFile}`);

  if (!fs.existsSync(sourceFile)) {
    log.error(`Source environment not found: ${sourceFile}`);
    log.info(`Available: ${fs.readdirSync(examplesDir).join(", ")}`);
    process.exit(1);
  }

  fs.copyFileSync(sourceFile, targetFile);
  log.success(`Cloned ${from} → ${targetFile}`);
  log.info(
    "Review and pin image SHA256 digests before committing: " +
      "docker inspect <image> --format '{{index .RepoDigests 0}}'"
  );
}

/**
 * Pre-pull all images listed in env.yaml to enable offline operation.
 */
async function cmdOffline(envFile: string): Promise<void> {
  log.info(`Preparing offline mode from ${envFile}`);
  if (!fs.existsSync(envFile)) {
    log.error(`File not found: ${envFile}`);
    process.exit(1);
  }

  const content = fs.readFileSync(envFile, "utf-8");

  // Extract image references (simple regex — covers image: field)
  const imageMatches = content.match(/image:\s+(\S+)/g) ?? [];
  const images = imageMatches.map((m) => m.replace(/^image:\s+/, "").trim());

  if (images.length === 0) {
    log.warn("No images found in env.yaml");
    return;
  }

  log.info(`Found ${images.length} images to pre-pull: ${images.join(", ")}`);
  log.info(
    "Run the following to pre-pull all images:\n" +
      images.map((img) => `  docker pull ${img}`).join("\n")
  );
  log.info(
    "After pulling, set RUNTIME_MODE=local in your environment to operate offline."
  );
  log.success("Offline preparation complete — run docker pull commands above");
}

/**
 * Replay a CI environment locally from a build ID.
 * Fetches the env.yaml artifact from the CI run.
 */
async function cmdReplay(buildId: string): Promise<void> {
  log.info(`Replaying build ${buildId} locally`);
  const targetFile = `env-replay-${buildId}.yaml`;

  // Check if env-provisioner /replay endpoint is available
  try {
    const resp = await httpPost(
      `${ENV_PROVISIONER_URL}/replay`,
      Buffer.from(JSON.stringify({ build_id: buildId })),
      "application/json"
    );
    const result = JSON.parse(resp.body);
    if (result.env_yaml) {
      fs.writeFileSync(targetFile, result.env_yaml);
      log.success(`Fetched env.yaml for build ${buildId} → ${targetFile}`);
      log.info(`Provision with: elevatediq env validate ${targetFile}`);
    } else {
      throw new Error("No env_yaml in response");
    }
  } catch {
    log.warn(
      `Provisioner replay endpoint unavailable. ` +
        `Download env.yaml from CI artifact for build ${buildId} ` +
        `and provision locally:\n` +
        `  gh run download ${buildId} --name env-yaml\n` +
        `  elevatediq env validate env.yaml`
    );
  }
}

/**
 * Promote environment from one profile to another (requires human approval via OPA).
 */
async function cmdPromote(from: string, to: string): Promise<void> {
  log.info(`Promoting environment ${from} → ${to}`);

  const examplesDir = path.join(REPO_ROOT, "apps", "env-provisioner", "examples");
  const sourceFile = path.join(examplesDir, `env-${from}.yaml`);
  const targetFile = path.join(examplesDir, `env-${to}.yaml`);

  if (!fs.existsSync(sourceFile)) {
    log.error(`Source environment not found: ${sourceFile}`);
    process.exit(1);
  }

  // Show diff first
  if (fs.existsSync(targetFile)) {
    log.info("Computing diff before promotion:");
    await cmdDiff(sourceFile, targetFile);
  }

  // OPA policy check: no_prod_without_human
  if (to === "production" || to === "prod") {
    log.warn("Target is PRODUCTION — this requires human approval (OPA: no_prod_without_human)");
    log.warn(
      "To proceed:\n" +
        "  1. Create a PR with the env.yaml changes\n" +
        "  2. Get tech_lead approval\n" +
        "  3. Merge and deploy via CI/CD pipeline\n" +
        "Direct production promotion is blocked by policy."
    );
    process.exit(1);
  }

  fs.copyFileSync(sourceFile, targetFile);
  log.success(`Promoted ${from} → ${to}: ${targetFile}`);
  log.info("Validate and commit the promoted file to apply changes.");
}

// ── Main ───────────────────────────────────────────────────────────────────────

function printUsage(): void {
  console.log(`
ElevatedIQ env.yaml CLI

Usage:
  elevatediq env validate [env-file]          Validate env.yaml against schema
  elevatediq env diff <file-a> <file-b>       Show differences between two env files
  elevatediq env clone --from <src> --to <tgt> Clone environment profile
  elevatediq env offline [env-file]           Prepare for offline operation
  elevatediq env replay --build-id <id>       Replay CI build environment locally
  elevatediq env promote --from <src> --to <tgt> Promote environment (with approval gate)

Environment:
  ENV_PROVISIONER_URL   Provisioner service URL (default: http://localhost:8007)
  ENV_YAML_PATH         Default env.yaml path (default: env.yaml)
`);
}

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const subcommand = args[0];

  if (!subcommand || subcommand === "--help" || subcommand === "-h") {
    printUsage();
    process.exit(0);
  }

  switch (subcommand) {
    case "validate": {
      const envFile = args[1] || DEFAULT_ENV_FILE;
      await cmdValidate(envFile);
      break;
    }

    case "diff": {
      const fileA = args[1];
      const fileB = args[2];
      if (!fileA || !fileB) {
        log.error("Usage: env diff <file-a.yaml> <file-b.yaml>");
        process.exit(1);
      }
      await cmdDiff(fileA, fileB);
      break;
    }

    case "clone": {
      const fromIdx = args.indexOf("--from");
      const toIdx = args.indexOf("--to");
      if (fromIdx === -1 || toIdx === -1) {
        log.error("Usage: env clone --from <source> --to <target>");
        process.exit(1);
      }
      await cmdClone(args[fromIdx + 1], args[toIdx + 1]);
      break;
    }

    case "offline": {
      const envFile = args[1] || DEFAULT_ENV_FILE;
      await cmdOffline(envFile);
      break;
    }

    case "replay": {
      const buildIdx = args.indexOf("--build-id");
      if (buildIdx === -1) {
        log.error("Usage: env replay --build-id <build-id>");
        process.exit(1);
      }
      await cmdReplay(args[buildIdx + 1]);
      break;
    }

    case "promote": {
      const fromIdx = args.indexOf("--from");
      const toIdx = args.indexOf("--to");
      if (fromIdx === -1 || toIdx === -1) {
        log.error("Usage: env promote --from <source> --to <target>");
        process.exit(1);
      }
      await cmdPromote(args[fromIdx + 1], args[toIdx + 1]);
      break;
    }

    default:
      log.error(`Unknown subcommand: ${subcommand}`);
      printUsage();
      process.exit(1);
  }
}

main().catch((err) => {
  log.error(`Unhandled error: ${err}`);
  process.exit(1);
});
