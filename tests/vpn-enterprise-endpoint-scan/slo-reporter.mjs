#!/usr/bin/env node
// tests/vpn-enterprise-endpoint-scan/slo-reporter.mjs
// QA-COVERAGE-004 Phase 2: Coverage SLO validation and reporting
// Purpose: Validate test coverage metrics against SLO targets, track trends, and gate CI

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// ============================================================================
// Configuration & Constants
// ============================================================================

const SLO_TARGETS = {
  OVERALL_COVERAGE: 95,           // Overall test coverage minimum
  CRITICAL_PATH_COVERAGE: 98,     // Critical functionality (auth, core APIs)
  NETWORKING_COVERAGE: 96,        // VPN/network critical features
  SECURITY_COVERAGE: 99,          // Security-sensitive code
  ERROR_HANDLING_COVERAGE: 94,    // Error paths and edge cases
};

const SEVERITY_LEVELS = {
  CRITICAL: { weight: 10, color: '31', threshold: 97 },  // Red
  HIGH: { weight: 5, color: '33', threshold: 95 },       // Yellow
  MEDIUM: { weight: 2, color: '36', threshold: 90 },     // Cyan
  LOW: { weight: 1, color: '32', threshold: 80 },        // Green
};

const TREND_THRESHOLDS = {
  REGRESSION_ALERT: 2.0,   // Alert if coverage drops >2%
  IMPROVEMENT_THRESHOLD: 1.0,  // Track improvements >1%
  TREND_WINDOW: 30,        // Days to track for trend analysis
};

// ============================================================================
// Utility Functions
// ============================================================================

function colorize(text, colorCode) {
  return `\u001b[${colorCode}m${text}\u001b[0m`;
}

function formatPercentage(value) {
  return `${value.toFixed(2)}%`;
}

function getCurrentTimestamp() {
  return new Date().toISOString();
}

function loadCoverageReport(reportPath) {
  if (!fs.existsSync(reportPath)) {
    throw new Error(`Coverage report not found: ${reportPath}`);
  }
  return JSON.parse(fs.readFileSync(reportPath, 'utf-8'));
}

function loadTrendHistory(historyPath) {
  if (!fs.existsSync(historyPath)) {
    return [];
  }
  return JSON.parse(fs.readFileSync(historyPath, 'utf-8'));
}

function saveTrendHistory(historyPath, history) {
  fs.mkdirSync(path.dirname(historyPath), { recursive: true });
  fs.writeFileSync(historyPath, JSON.stringify(history, null, 2));
}

// ============================================================================
// SLO Validation
// ============================================================================

function validateCoverage(report) {
  const results = {
    timestamp: getCurrentTimestamp(),
    passed: true,
    metrics: {},
    violations: [],
    warnings: [],
  };

  // Extract coverage metrics from report
  const metrics = {
    overall: report.total?.coverage || 0,
    critical: report.critical?.coverage || 0,
    networking: report.networking?.coverage || 0,
    security: report.security?.coverage || 0,
    errorHandling: report.errorHandling?.coverage || 0,
  };

  // Validate against SLO targets
  Object.entries(metrics).forEach(([key, value]) => {
    const targetKey = key.replace(/([A-Z])/g, '_$1').toUpperCase();
    const target = SLO_TARGETS[`${targetKey}_COVERAGE`] || SLO_TARGETS.OVERALL_COVERAGE;
    
    results.metrics[key] = {
      current: value,
      target: target,
      gap: value - target,
      status: value >= target ? 'PASS' : 'FAIL',
    };

    if (value < target) {
      results.violations.push({
        metric: key,
        current: value,
        target: target,
        gap: target - value,
        severity: value < target - 5 ? 'CRITICAL' : 'HIGH',
      });
      results.passed = false;
    }
  });

  return results;
}

// ============================================================================
// Trend Analysis
// ============================================================================

function analyzeTrends(currentMetrics, history) {
  const trends = {
    improving: [],
    declining: [],
    stable: [],
    regressions: [],
  };

  // Keep only recent history (TREND_WINDOW days)
  const cutoffDate = new Date();
  cutoffDate.setDate(cutoffDate.getDate() - TREND_THRESHOLDS.TREND_WINDOW);
  
  const recentHistory = history.filter(
    h => new Date(h.timestamp) > cutoffDate
  );

  if (recentHistory.length === 0) {
    return { ...trends, status: 'INSUFFICIENT_DATA' };
  }

  const baseline = recentHistory[0];

  Object.entries(currentMetrics).forEach(([metric, current]) => {
    const baselineValue = baseline.metrics[metric]?.current || 0;
    const change = current.current - baselineValue;

    if (Math.abs(change) < TREND_THRESHOLDS.IMPROVEMENT_THRESHOLD) {
      trends.stable.push({ metric, change });
    } else if (change > 0) {
      trends.improving.push({ metric, change });
    } else if (change < -TREND_THRESHOLDS.REGRESSION_ALERT) {
      trends.regressions.push({ metric, change });
    } else {
      trends.declining.push({ metric, change });
    }
  });

  return { ...trends, status: 'OK' };
}

// ============================================================================
// Report Generation
// ============================================================================

function generateReport(results, trends, history) {
  const report = {
    summary: {
      timestamp: results.timestamp,
      overall_status: results.passed ? 'PASS' : 'FAIL',
      violations_count: results.violations.length,
      warnings_count: results.warnings.length,
      trend_status: trends.status,
    },
    metrics: results.metrics,
    violations: results.violations,
    warnings: results.warnings,
    trends: trends,
    recommendations: generateRecommendations(results, trends),
    github_check: {
      name: 'QA Coverage SLO Gate',
      conclusion: results.passed ? 'success' : 'failure',
      status: 'completed',
      output: {
        title: 'Coverage SLO Validation',
        summary: generateSummary(results, trends),
        annotations: results.violations.map(v => ({
          path: 'tests/vpn-enterprise-endpoint-scan',
          annotation_level: v.severity.toLowerCase(),
          message: `${v.metric}: ${formatPercentage(v.current)} (target: ${formatPercentage(v.target)})`,
        })),
      },
    },
  };

  return report;
}

function generateSummary(results, trends) {
  const lines = [];
  lines.push('## Coverage SLO Report\n');
  
  lines.push('### Metrics');
  lines.push('| Metric | Current | Target | Status |');
  lines.push('|--------|---------|--------|--------|');
  
  Object.entries(results.metrics).forEach(([metric, data]) => {
    const status = data.status === 'PASS' ? '✅' : '❌';
    lines.push(
      `| ${metric} | ${formatPercentage(data.current)} | ${formatPercentage(data.target)} | ${status} |`
    );
  });

  if (results.violations.length > 0) {
    lines.push('\n### Violations');
    results.violations.forEach(v => {
      lines.push(
        `- **${v.metric}**: ${formatPercentage(v.current)} (gap: -${formatPercentage(v.gap)})`
      );
    });
  }

  if (trends.regressions.length > 0) {
    lines.push('\n### Regressions Detected');
    trends.regressions.forEach(r => {
      lines.push(`- **${r.metric}**: ${formatPercentage(r.change)}`);
    });
  }

  if (trends.improving.length > 0) {
    lines.push('\n### Improvements');
    trends.improving.forEach(i => {
      lines.push(`- **${i.metric}**: +${formatPercentage(i.change)}`);
    });
  }

  return lines.join('\n');
}

function generateRecommendations(results, trends) {
  const recommendations = [];

  results.violations.forEach(v => {
    if (v.severity === 'CRITICAL') {
      recommendations.push({
        priority: 'CRITICAL',
        metric: v.metric,
        action: `Increase ${v.metric} coverage by ${formatPercentage(v.gap)} to meet SLO`,
        steps: [
          'Identify untested code paths',
          'Write additional unit/integration tests',
          'Run coverage report locally to verify',
          'Submit PR with test improvements',
        ],
      });
    }
  });

  trends.regressions.forEach(r => {
    recommendations.push({
      priority: 'HIGH',
      metric: r.metric,
      action: `Regression detected: ${r.metric} dropped ${formatPercentage(Math.abs(r.change))}`,
      steps: [
        'Review recent commits that reduced coverage',
        'Identify deleted or changed code',
        'Add tests for changed code paths',
        'Verify no test removals',
      ],
    });
  });

  if (recommendations.length === 0) {
    recommendations.push({
      priority: 'LOW',
      action: 'Coverage metrics stable and above targets',
      steps: ['Continue current testing practices'],
    });
  }

  return recommendations;
}

// ============================================================================
// Output Formatting
// ============================================================================

function printConsoleReport(report) {
  console.log('\n' + '='.repeat(80));
  console.log(colorize('QA-COVERAGE-004 PHASE 2: SLO VALIDATION REPORT', '36'));
  console.log('='.repeat(80) + '\n');

  // Summary
  const status = report.summary.overall_status === 'PASS' 
    ? colorize('✅ PASS', '32')
    : colorize('❌ FAIL', '31');
  console.log(`Overall Status: ${status}`);
  console.log(`Timestamp: ${report.summary.timestamp}`);
  console.log(`Violations: ${report.summary.violations_count}\n`);

  // Metrics Table
  console.log(colorize('Metrics Summary:', '36'));
  console.log('-'.repeat(80));
  Object.entries(report.metrics).forEach(([metric, data]) => {
    const statusColor = data.status === 'PASS' ? '32' : '31';
    const statusText = colorize(data.status, statusColor);
    console.log(
      `${metric.padEnd(25)} | Current: ${formatPercentage(data.current).padStart(6)} ` +
      `| Target: ${formatPercentage(data.target).padStart(6)} | ${statusText}`
    );
  });
  console.log('-'.repeat(80) + '\n');

  // Violations
  if (report.violations.length > 0) {
    console.log(colorize('Violations:', '31'));
    report.violations.forEach(v => {
      console.log(
        `  ❌ ${v.metric}: ${formatPercentage(v.current)} (gap: -${formatPercentage(v.gap)})`
      );
    });
    console.log('');
  }

  // Trends
  if (report.trends.status === 'OK') {
    if (report.trends.improving.length > 0) {
      console.log(colorize('Improvements:', '32'));
      report.trends.improving.forEach(i => {
        console.log(`  ✅ ${i.metric}: +${formatPercentage(i.change)}`);
      });
    }
    if (report.trends.regressions.length > 0) {
      console.log(colorize('Regressions:', '31'));
      report.trends.regressions.forEach(r => {
        console.log(`  ⚠️  ${r.metric}: ${formatPercentage(r.change)}`);
      });
    }
  }

  console.log('\n' + '='.repeat(80) + '\n');
}

function writeGitHubCheck(report, outputPath) {
  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(outputPath, JSON.stringify(report.github_check, null, 2));
}

// ============================================================================
// Main Execution
// ============================================================================

async function main() {
  try {
    const coverageReportPath = process.argv[2] || 'coverage/coverage-final.json';
    const historyPath = path.join(
      path.dirname(coverageReportPath),
      'coverage-history.json'
    );
    const outputDir = path.join(__dirname, 'test-results');
    const reportPath = path.join(outputDir, 'slo-report.json');
    const checkPath = path.join(outputDir, 'github-check.json');

    console.log(`Loading coverage report from: ${coverageReportPath}`);
    const coverageReport = loadCoverageReport(coverageReportPath);

    // Validate current coverage
    const validationResults = validateCoverage(coverageReport);

    // Load trend history
    const history = loadTrendHistory(historyPath);

    // Analyze trends
    const trends = analyzeTrends(validationResults.metrics, history);

    // Generate report
    const report = generateReport(validationResults, trends, history);

    // Save updated history
    const updatedHistory = [...history, validationResults];
    saveTrendHistory(historyPath, updatedHistory);

    // Print console report
    printConsoleReport(report);

    // Write reports
    fs.mkdirSync(outputDir, { recursive: true });
    fs.writeFileSync(reportPath, JSON.stringify(report, null, 2));
    writeGitHubCheck(report, checkPath);

    console.log(`✓ SLO Report saved: ${reportPath}`);
    console.log(`✓ GitHub Check saved: ${checkPath}`);

    // Set output for GitHub Actions
    if (process.env.GITHUB_OUTPUT) {
      const output = [
        `slo_status=${report.summary.overall_status}`,
        `violations=${report.summary.violations_count}`,
        `report_path=${reportPath}`,
        `passed=${validationResults.passed ? 'true' : 'false'}`,
      ].join('\n');
      
      fs.appendFileSync(process.env.GITHUB_OUTPUT, output);
    }

    // Exit with appropriate code
    process.exit(validationResults.passed ? 0 : 1);

  } catch (error) {
    console.error(colorize(`Error: ${error.message}`, '31'));
    process.exit(1);
  }
}

main();
