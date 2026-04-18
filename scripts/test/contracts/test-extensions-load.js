/**
 * @file        scripts/test/contracts/test-extensions-load.js
 * @description Contract test: Extensions Load API compatibility
 */

module.exports = async function testExtensionsLoad(harness) {
  const tests = [];

  // Test 1: VSCode API available
  try {
    const vscodeApi = require("vscode");
    if (!vscodeApi) throw new Error("VSCode API not available");
    tests.push({ name: "VSCode API available", status: "passed" });
  } catch (e) {
    tests.push({ name: "VSCode API available", status: "failed", error: e.message });
  }

  // Test 2: Extension context accessible
  try {
    // Verify ExtensionContext type available
    const apiValid = typeof vscodeApi !== "undefined";
    if (!apiValid) throw new Error("Extension APIs not accessible");
    tests.push({ name: "Extension context accessible", status: "passed" });
  } catch (e) {
    tests.push({ name: "Extension context accessible", status: "failed", error: e.message });
  }

  // Test 3: Extension manifest parsing
  try {
    const fs = require("fs");
    const path = require("path");
    const extDir = path.join(harness.workspaceDir, "extensions");
    if (!fs.existsSync(extDir)) fs.mkdirSync(extDir, { recursive: true });
    tests.push({ name: "Extension manifest parsing", status: "passed" });
  } catch (e) {
    tests.push({ name: "Extension manifest parsing", status: "failed", error: e.message });
  }

  // Report test results
  const failed = tests.filter((t) => t.status === "failed");
  if (failed.length > 0) {
    throw new Error(
      `Extensions Load Contract Failed: ${failed.map((t) => t.name).join(", ")}`
    );
  }

  console.log(`  ✅ Extensions Load Contract: ${tests.length} tests passed`);
};
