#!/usr/bin/env node
/**
 * @file slo-reporter.mjs
 * @description SLO reporter for QA coverage gates.
 *              Compares current run against historical baseline, detects regressions,
 *              publishes metrics to Prometheus, and emits GitHub step summary.
 * @module qa/slo
 */

import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { existsSync, mkdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import crypto from 'node:crypto';

const __dirname = dirname(fileURLToPath(import.meta.url));
const HISTORY_DIR = join(process.cwd(), '.coverage-history');
const BASELINE_FILE = join(HISTORY_DIR, 'baseline.json');
const HISTORY_FILE = join(HISTORY_DIR, 'history.json');
const MAX_HISTORY_ENTRIES = 90; // 90 days rolling

// SLO Definitions
const SLO_TARGETS = {
  route_coverage: {
    target: 0.95,    // 95%
    alert_threshold: 0.90,  // Alert if < 90%
    regression_threshold: 0.05, // Alert on >5% drop
    label: 'Route Coverage',
  },
  interaction_coverage: {
    target: 0.80,
    alert_threshold: 0.70,
    regression_threshold: 0.05,
    label: 'Interaction Coverage',
  },
  api_contract_pass_rate: {
    target: 0.90,
    alert_threshold: 0.80,
    regression_threshold: 0.05,
    label: 'API Contract Pass Rate',
  },
  p99_latency_ms: {
    target: 1000,
    alert_threshold: 1500,
    regression_threshold: 0.20, // 20% increase
    label: 'P99 Latency (ms)',
    lower_is_better: true,
  },
};

/**
 * Loads coverage data from a file or returns defaults
 */
async function loadCoverageData(filePath) {
  try {
    const content = await readFile(filePath, 'utf-8');
    return JSON.parse(content);
  } catch (err) {
    // Return empty data if file doesn't exist
    return null;
  }
}

/**
 * Loads historical data
 */
async function loadHistory() {
  try {
    const content = await readFile(HISTORY_FILE, 'utf-8');
    return JSON.parse(content);
  } catch (err) {
    return { entries: [] };
  }
}

/**
 * Saves a new history entry
 */
async function saveHistoryEntry(metrics) {
  if (!existsSync(HISTORY_DIR)) {
    mkdirSync(HISTORY_DIR, { recursive: true });
  }

  const history = await loadHistory();
  const entry = {
    timestamp: new Date().toISOString(),
    run_id: process.env.GITHUB_RUN_ID || 'local',
    commit: process.env.GITHUB_SHA || 'unknown',
    metrics,
  };

  history.entries.unshift(entry);

  // Trim to max history
  if (history.entries.length > MAX_HISTORY_ENTRIES) {
    history.entries = history.entries.slice(0, MAX_HISTORY_ENTRIES);
  }

  await writeFile(HISTORY_FILE, JSON.stringify(history, null, 2));
  return entry;
}

/**
 * Loads baseline metrics (7-day rolling average)
 */
async function loadBaseline() {
  const history = await loadHistory();
  if (history.entries.length === 0) {
    return null;
  }

  // Use last 7 entries for rolling baseline
  const recentEntries = history.entries.slice(0, Math.min(7, history.entries.length));
  if (recentEntries.length === 0) return null;

  // Calculate average for each metric
  const baseline = {};
  const metrics = Object.keys(recentEntries[0].metrics || {});

  for (const metric of metrics) {
    const values = recentEntries
      .map(e => e.metrics[metric])
      .filter(v => v !== null && v !== undefined && !isNaN(v));

    if (values.length > 0) {
      baseline[metric] = values.reduce((sum, v) => sum + v, 0) / values.length;
    }
  }

  return baseline;
}

/**
 * Compares current metrics against SLO targets and baseline
 */
function evaluateSLOs(current, baseline) {
  const results = [];

  for (const [sloKey, slo] of Object.entries(SLO_TARGETS)) {
    const currentValue = current[sloKey];
    if (currentValue === undefined) continue;

    const lowerIsBetter = slo.lower_is_better || false;

    // Check against SLO target
    const meetsTarget = lowerIsBetter
      ? currentValue <= slo.target
      : currentValue >= slo.target;

    // Check against alert threshold
    const meetsAlertThreshold = lowerIsBetter
      ? currentValue <= slo.alert_threshold
      : currentValue >= slo.alert_threshold;

    // Check regression against baseline
    let regression = null;
    let regressionPct = null;
    if (baseline && baseline[sloKey] !== undefined) {
      const baselineValue = baseline[sloKey];
      if (lowerIsBetter) {
        regressionPct = (currentValue - baselineValue) / baselineValue;
        regression = regressionPct > slo.regression_threshold;
      } else {
        regressionPct = (baselineValue - currentValue) / baselineValue;
        regression = regressionPct > slo.regression_threshold;
      }
    }

    results.push({
      key: sloKey,
      label: slo.label,
      currentValue,
      target: slo.target,
      alertThreshold: slo.alert_threshold,
      baselineValue: baseline?.[sloKey] ?? null,
      meetsTarget,
      meetsAlertThreshold,
      regression,
      regressionPct,
      lowerIsBetter,
    });
  }

  return results;
}

/**
 * Generates Prometheus metrics output
 */
function generatePrometheusMetrics(current, sloResults) {
  const timestamp = Date.now();
  const labels = `environment="on-prem",job="qa-coverage-gates"`;

  let output = '';

  // Current metric values
  for (const result of sloResults) {
    const metricName = `qa_slo_${result.key}`;
    output += `# HELP ${metricName} ${result.label}\n`;
    output += `# TYPE ${metricName} gauge\n`;
    output += `${metricName}{${labels}} ${result.currentValue} ${timestamp}\n\n`;

    // SLO target
    output += `${metricName}_target{${labels}} ${result.target} ${timestamp}\n`;
    output += `${metricName}_meets_target{${labels}} ${result.meetsTarget ? 1 : 0} ${timestamp}\n`;
    output += `${metricName}_meets_alert{${labels}} ${result.meetsAlertThreshold ? 1 : 0} ${timestamp}\n\n`;

    // Regression
    if (result.regressionPct !== null) {
      output += `${metricName}_regression_pct{${labels}} ${result.regressionPct} ${timestamp}\n`;
      output += `${metricName}_regression_detected{${labels}} ${result.regression ? 1 : 0} ${timestamp}\n\n`;
    }
  }

  // Overall SLO compliance
  const allMeetTarget = sloResults.every(r => r.meetsTarget);
  const allMeetAlert = sloResults.every(r => r.meetsAlertThreshold);
  const anyRegression = sloResults.some(r => r.regression);

  output += `# HELP qa_slo_overall_meets_target Whether all SLOs meet their targets\n`;
  output += `# TYPE qa_slo_overall_meets_target gauge\n`;
  output += `qa_slo_overall_meets_target{${labels}} ${allMeetTarget ? 1 : 0} ${timestamp}\n\n`;

  output += `# HELP qa_slo_overall_meets_alert Whether all SLOs are above alert threshold\n`;
  output += `# TYPE qa_slo_overall_meets_alert gauge\n`;
  output += `qa_slo_overall_meets_alert{${labels}} ${allMeetAlert ? 1 : 0} ${timestamp}\n\n`;

  output += `# HELP qa_slo_regression_detected Whether any SLO regression was detected\n`;
  output += `# TYPE qa_slo_regression_detected gauge\n`;
  output += `qa_slo_regression_detected{${labels}} ${anyRegression ? 1 : 0} ${timestamp}\n`;

  return output;
}

/**
 * Generates GitHub step summary markdown
 */
function generateGitHubSummary(sloResults, current, baseline) {
  const timestamp = new Date().toISOString();
  const allMeetTarget = sloResults.every(r => r.meetsTarget);
  const anyRegression = sloResults.some(r => r.regression);

  let md = `## 📊 QA Coverage SLO Report\n\n`;
  md += `**Run Time**: ${timestamp}\n`;
  md += `**Commit**: \`${process.env.GITHUB_SHA?.slice(0, 8) || 'local'}\`\n\n`;

  // Overall status
  if (allMeetTarget && !anyRegression) {
    md += `✅ **All SLOs Met** — No regressions detected\n\n`;
  } else if (!allMeetTarget) {
    md += `🔴 **SLO Violations** — See details below\n\n`;
  } else if (anyRegression) {
    md += `🟡 **Regression Detected** — SLOs met but trending downward\n\n`;
  }

  // SLO Details table
  md += `### SLO Details\n\n`;
  md += `| Metric | Current | Target | Baseline | Status | Regression |\n`;
  md += `|--------|---------|--------|----------|--------|------------|\n`;

  for (const r of sloResults) {
    const currentFormatted = r.lowerIsBetter
      ? `${r.currentValue.toFixed(0)}ms`
      : `${(r.currentValue * 100).toFixed(1)}%`;

    const targetFormatted = r.lowerIsBetter
      ? `${r.target}ms`
      : `${(r.target * 100).toFixed(0)}%`;

    const baselineFormatted = r.baselineValue !== null
      ? (r.lowerIsBetter
        ? `${r.baselineValue.toFixed(0)}ms`
        : `${(r.baselineValue * 100).toFixed(1)}%`)
      : 'N/A';

    const statusIcon = r.meetsTarget ? '✅' : (r.meetsAlertThreshold ? '🟡' : '🔴');
    const regressionText = r.regression
      ? `⬇️ ${(r.regressionPct * 100).toFixed(1)}%`
      : (r.regressionPct !== null ? '✅ stable' : 'N/A');

    md += `| ${r.label} | ${currentFormatted} | ${targetFormatted} | ${baselineFormatted} | ${statusIcon} | ${regressionText} |\n`;
  }

  md += `\n`;

  // Alerts section
  const violations = sloResults.filter(r => !r.meetsAlertThreshold);
  const regressions = sloResults.filter(r => r.regression);

  if (violations.length > 0) {
    md += `### 🚨 Active Violations\n\n`;
    for (const v of violations) {
      md += `- **${v.label}**: ${v.currentValue} is below alert threshold ${v.alertThreshold}\n`;
    }
    md += `\n`;
  }

  if (regressions.length > 0) {
    md += `### ⚠️ Regressions\n\n`;
    for (const r of regressions) {
      md += `- **${r.label}**: ${(r.regressionPct * 100).toFixed(1)}% drop vs. 7-day baseline\n`;
    }
    md += `\n`;
  }

  return md;
}

/**
 * Main execution function
 */
async function main() {
  const coverageFilePath = process.argv[2];

  console.log('[slo-reporter] Starting SLO evaluation...');

  // Load current coverage data
  let current = {};

  if (coverageFilePath && existsSync(coverageFilePath)) {
    const data = await loadCoverageData(coverageFilePath);
    if (data) {
      current = {
        route_coverage: data.route_coverage ?? 0,
        interaction_coverage: data.interaction_coverage ?? 0,
        api_contract_pass_rate: data.api_contract_pass_rate ?? 0,
        p99_latency_ms: data.p99_latency_ms ?? 0,
      };
    }
  } else {
    // Use environment variables as fallback (set by coverage runner)
    current = {
      route_coverage: parseFloat(process.env.COVERAGE_ROUTE || '0'),
      interaction_coverage: parseFloat(process.env.COVERAGE_INTERACTION || '0'),
      api_contract_pass_rate: parseFloat(process.env.COVERAGE_API_PASS || '0'),
      p99_latency_ms: parseFloat(process.env.COVERAGE_P99_LATENCY || '0'),
    };
  }

  console.log('[slo-reporter] Current metrics:', current);

  // Load historical baseline (7-day rolling average)
  const baseline = await loadBaseline();
  console.log('[slo-reporter] Baseline:', baseline);

  // Evaluate SLOs
  const sloResults = evaluateSLOs(current, baseline);

  // Save current run to history
  await saveHistoryEntry(current);

  // Generate Prometheus metrics
  const prometheusMetrics = generatePrometheusMetrics(current, sloResults);

  // Write metrics file
  if (!existsSync(HISTORY_DIR)) {
    mkdirSync(HISTORY_DIR, { recursive: true });
  }
  await writeFile(join(HISTORY_DIR, 'slo-metrics.prom'), prometheusMetrics);
  console.log('[slo-reporter] Prometheus metrics written to .coverage-history/slo-metrics.prom');

  // Generate GitHub step summary
  const summary = generateGitHubSummary(sloResults, current, baseline);

  // Write to GitHub step summary if available
  if (process.env.GITHUB_STEP_SUMMARY) {
    await writeFile(process.env.GITHUB_STEP_SUMMARY, summary, { flag: 'a' });
    console.log('[slo-reporter] GitHub step summary written');
  }

  // Write human-readable summary to stdout
  console.log('\n' + '='.repeat(60));
  console.log('SLO EVALUATION RESULTS');
  console.log('='.repeat(60));
  for (const r of sloResults) {
    const status = r.meetsTarget ? '✅ PASS' : '❌ FAIL';
    console.log(`${status} ${r.label}: ${r.currentValue}`);
  }
  console.log('='.repeat(60));

  // Determine exit code
  const hasViolations = sloResults.some(r => !r.meetsAlertThreshold);
  const hasRegressions = sloResults.some(r => r.regression);

  if (hasViolations) {
    console.error('[slo-reporter] FATAL: SLO violations detected — blocking CI');
    process.exit(1);
  } else if (hasRegressions) {
    console.warn('[slo-reporter] WARNING: Regressions detected but SLOs still met');
    // Exit 2 for regression warning (non-fatal)
    process.exit(2);
  } else {
    console.log('[slo-reporter] All SLOs passed — no regressions detected');
    process.exit(0);
  }
}

main().catch(err => {
  console.error('[slo-reporter] Fatal error:', err);
  process.exit(1);
});
