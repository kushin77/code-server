#!/usr/bin/env node
/**
 * @file        scripts/test/contracts/harness.js
 * @module      testing/contracts
 * @description VSCode contract test harness - validates upstream compatibility
 */

const fs = require("fs");
const path = require("path");
const { spawn } = require("child_process");

class ContractTestHarness {
  constructor(options = {}) {
    this.vscodeDir = options.vscodeDir || process.env.VSCODE_PATH || "/tmp/vscode-test";
    this.workspaceDir = options.workspaceDir || "/tmp/test-workspace";
    this.upstreamVersion = options.upstreamVersion || "latest";
    this.timeout = options.timeout || 5000;
    this.results = [];
  }

  async initialize() {
    console.log("🔧 Initializing contract test harness...");
    // Ensure test workspace exists
    if (!fs.existsSync(this.workspaceDir)) {
      fs.mkdirSync(this.workspaceDir, { recursive: true });
    }
    console.log("✅ Test harness initialized");
  }

  async runTests(testPattern = "**/*.test.js") {
    console.log(`\n📋 Running contract tests (pattern: ${testPattern})...\n`);

    const testDir = path.join(__dirname);
    const testFiles = fs
      .readdirSync(testDir)
      .filter((f) => f.startsWith("test-") && f.endsWith(".js"));

    if (testFiles.length === 0) {
      console.warn("⚠️  No contract tests found");
      return { passed: 0, failed: 0, skipped: 0 };
    }

    let passed = 0;
    let failed = 0;

    for (const testFile of testFiles) {
      const testPath = path.join(testDir, testFile);
      try {
        console.log(`→ Running ${testFile}...`);

        // Import and run test
        const test = require(testPath);
        if (typeof test === "function") {
          await test(this);
          console.log(`  ✅ ${testFile}`);
          passed++;
        } else {
          console.log(`  ⚠️  ${testFile} (no test function exported)`);
        }
      } catch (error) {
        console.error(`  ❌ ${testFile}: ${error.message}`);
        failed++;
        this.results.push({ test: testFile, status: "failed", error: error.message });
      }
    }

    console.log(`\n📊 Test Results: ${passed} passed, ${failed} failed`);
    return { passed, failed, skipped: 0, total: testFiles.length };
  }

  async cleanup() {
    console.log("\n🧹 Cleaning up test environment...");
    // Clean temporary workspace
    if (fs.existsSync(this.workspaceDir)) {
      fs.rmSync(this.workspaceDir, { recursive: true, force: true });
    }
    console.log("✅ Cleanup complete");
  }

  reportResults() {
    const summary = this.results.reduce(
      (acc, r) => {
        if (r.status === "passed") acc.passed++;
        if (r.status === "failed") acc.failed++;
        return acc;
      },
      { passed: 0, failed: 0 }
    );

    console.log("\n📈 Contract Test Summary:");
    console.log(`  Passed: ${summary.passed}`);
    console.log(`  Failed: ${summary.failed}`);
    console.log(`  Pass Rate: ${((summary.passed / this.results.length) * 100).toFixed(1)}%`);

    if (summary.failed > 0) {
      process.exit(1);
    }
  }
}

// CLI execution
if (require.main === module) {
  const harness = new ContractTestHarness({
    upstreamVersion: process.env.UPSTREAM_VERSION || "latest",
  });

  (async () => {
    try {
      await harness.initialize();
      await harness.runTests();
      harness.reportResults();
      await harness.cleanup();
    } catch (error) {
      console.error("Fatal error:", error.message);
      process.exit(1);
    }
  })();
}

module.exports = ContractTestHarness;
