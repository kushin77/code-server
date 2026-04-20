#!/usr/bin/env bash
# @file        scripts/ci/export-e2e-metrics.sh
# @module      ci/e2e
# @description Aggregate Playwright JSON artifacts into QA metrics, markdown summaries, and Prometheus text.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

ARTIFACT_ROOT="${1:-.}"
METRICS_JSON_PATH="${E2E_METRICS_JSON_PATH:-e2e-metrics.json}"
METRICS_MD_PATH="${E2E_METRICS_MD_PATH:-e2e-metrics.md}"
METRICS_PROM_PATH="${E2E_METRICS_PROM_PATH:-e2e-metrics.prom}"
PUSHGATEWAY_URL="${PUSHGATEWAY_URL:-}"

resolve_node_command() {
  local candidate
  local -a candidates=(
    node
    node.exe
    "/mnt/c/Program Files/nodejs/node.exe"
    "/mnt/c/Program Files/nodejs/node"
  )

  for candidate in "${candidates[@]}"; do
    if command -v "$candidate" >/dev/null 2>&1; then
      command -v "$candidate"
      return 0
    fi

    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

NODE_CMD="$(resolve_node_command || true)"

if [[ -z "$NODE_CMD" ]]; then
  log_fatal "Required command not found: node"
fi

"$NODE_CMD" - "$ARTIFACT_ROOT" "$METRICS_JSON_PATH" "$METRICS_MD_PATH" "$METRICS_PROM_PATH" "$PUSHGATEWAY_URL" <<'NODE'
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const [artifactRoot, metricsJsonPath, metricsMdPath, metricsPromPath, pushgatewayUrl] = process.argv.slice(2);

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function walkDirectory(rootDir) {
  const resultFiles = [];

  function visit(currentPath) {
    for (const entry of fs.readdirSync(currentPath, { withFileTypes: true })) {
      const nextPath = path.join(currentPath, entry.name);
      if (entry.isDirectory()) {
        visit(nextPath);
        continue;
      }

      if (entry.isFile() && (entry.name === 'results.json' || entry.name === 'playwright-results.json')) {
        resultFiles.push(nextPath);
      }
    }
  }

  if (fs.existsSync(rootDir)) {
    visit(rootDir);
  }

  return resultFiles;
}

const resultFiles = walkDirectory(artifactRoot);

if (resultFiles.length === 0) {
  throw new Error(`No Playwright results.json files found under ${artifactRoot}`);
}

const aggregated = {
  generatedAt: new Date().toISOString(),
  artifactRoot,
  shards: [],
  totalTests: 0,
  passed: 0,
  failed: 0,
  skipped: 0,
  flaky: 0,
  durationMs: 0,
};

for (const resultFile of resultFiles) {
  const report = readJson(resultFile);
  const stats = report.stats || {};

  const expected = Number(stats.expected || 0);
  const unexpected = Number(stats.unexpected || 0);
  const skipped = Number(stats.skipped || 0);
  const flaky = Number(stats.flaky || 0);
  const durationMs = Number(stats.duration || 0);

  aggregated.shards.push({
    file: path.relative(artifactRoot, resultFile),
    expected,
    unexpected,
    skipped,
    flaky,
    durationMs,
  });

  aggregated.totalTests += expected + unexpected + skipped;
  aggregated.passed += expected;
  aggregated.failed += unexpected;
  aggregated.skipped += skipped;
  aggregated.flaky += flaky;
  aggregated.durationMs += durationMs;
}

aggregated.passRate = aggregated.totalTests > 0
  ? Number(((aggregated.passed / Math.max(aggregated.passed + aggregated.failed, 1)) * 100).toFixed(1))
  : 0;

aggregated.throughputPerMinute = aggregated.durationMs > 0
  ? Number(((aggregated.totalTests / aggregated.durationMs) * 60000).toFixed(2))
  : 0;

const markdown = [
  '## QA Test Metrics',
  '',
  `Generated: ${aggregated.generatedAt}`,
  `Artifact root: ${artifactRoot}`,
  '',
  '| Metric | Value |',
  '|--------|-------|',
  `| Total tests | ${aggregated.totalTests} |`,
  `| Passed | ${aggregated.passed} |`,
  `| Failed | ${aggregated.failed} |`,
  `| Skipped | ${aggregated.skipped} |`,
  `| Flaky | ${aggregated.flaky} |`,
  `| Pass rate | ${aggregated.passRate.toFixed(1)}% |`,
  `| Duration | ${(aggregated.durationMs / 1000).toFixed(1)}s |`,
  `| Throughput | ${aggregated.throughputPerMinute.toFixed(2)} tests/min |`,
  '',
  '### Shards',
  '',
  '| File | Passed | Failed | Skipped | Flaky | Duration |',
  '|------|--------|--------|---------|-------|----------|',
  ...aggregated.shards.map((shard) => {
    const durationSeconds = (shard.durationMs / 1000).toFixed(1);
    return `| ${shard.file} | ${shard.expected} | ${shard.unexpected} | ${shard.skipped} | ${shard.flaky} | ${durationSeconds}s |`;
  }),
  '',
  aggregated.failed > 0
    ? 'QA metrics indicate at least one failing test shard.'
    : 'All aggregated QA test shards passed.',
  '',
].join('\n');

const prometheus = [
  '# TYPE e2e_tests_total gauge',
  `e2e_tests_total ${aggregated.totalTests}`,
  '# TYPE e2e_tests_passed gauge',
  `e2e_tests_passed ${aggregated.passed}`,
  '# TYPE e2e_tests_failed gauge',
  `e2e_tests_failed ${aggregated.failed}`,
  '# TYPE e2e_tests_skipped gauge',
  `e2e_tests_skipped ${aggregated.skipped}`,
  '# TYPE e2e_tests_flaky gauge',
  `e2e_tests_flaky ${aggregated.flaky}`,
  '# TYPE e2e_test_duration_seconds gauge',
  `e2e_test_duration_seconds ${(aggregated.durationMs / 1000).toFixed(3)}`,
  '# TYPE e2e_test_pass_rate gauge',
  `e2e_test_pass_rate ${aggregated.passRate.toFixed(1)}`,
  '',
].join('\n');

fs.writeFileSync(metricsJsonPath, `${JSON.stringify(aggregated, null, 2)}\n`);
fs.writeFileSync(metricsMdPath, markdown);
fs.writeFileSync(metricsPromPath, prometheus);

if (pushgatewayUrl) {
  const jobPath = `${pushgatewayUrl.replace(/\/$/, '')}/metrics/job/e2e_tests`;
  const request = spawnSync('curl', ['--fail', '--silent', '--show-error', '--data-binary', '@-', jobPath], {
    input: prometheus,
    encoding: 'utf8',
  });

  if (request.status !== 0) {
    throw new Error(`Failed to push metrics to ${jobPath}: ${request.stderr || request.stdout || 'unknown error'}`);
  }
}

console.log(markdown);
NODE

log_info "Wrote QA metrics to ${METRICS_JSON_PATH}, ${METRICS_MD_PATH}, and ${METRICS_PROM_PATH}"
