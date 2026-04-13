"use strict";
/**
 * Phase 14: Testing & Hardening
 *
 * This module provides comprehensive testing and validation infrastructure:
 * - Test utilities and helpers
 * - Security validation test suites
 * - Load and performance testing
 * - Integration test frameworks
 * - Comprehensive test reporting and coordination
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.TestOrchestrator = exports.generateIntegrationTestReport = exports.IntegrationTestSuite = exports.IntegrationLoadTest = exports.LoadTestRunner = exports.SecurityValidationTests = exports.TestHelper = void 0;
var TestHelper_1 = require("./TestHelper");
Object.defineProperty(exports, "TestHelper", { enumerable: true, get: function () { return TestHelper_1.TestHelper; } });
var SecurityValidationTests_1 = require("./SecurityValidationTests");
Object.defineProperty(exports, "SecurityValidationTests", { enumerable: true, get: function () { return SecurityValidationTests_1.SecurityValidationTests; } });
var LoadTestRunner_1 = require("./LoadTestRunner");
Object.defineProperty(exports, "LoadTestRunner", { enumerable: true, get: function () { return LoadTestRunner_1.LoadTestRunner; } });
Object.defineProperty(exports, "IntegrationLoadTest", { enumerable: true, get: function () { return LoadTestRunner_1.IntegrationLoadTest; } });
var IntegrationTestSuite_1 = require("./IntegrationTestSuite");
Object.defineProperty(exports, "IntegrationTestSuite", { enumerable: true, get: function () { return IntegrationTestSuite_1.IntegrationTestSuite; } });
Object.defineProperty(exports, "generateIntegrationTestReport", { enumerable: true, get: function () { return IntegrationTestSuite_1.generateIntegrationTestReport; } });
var TestOrchestrator_1 = require("./TestOrchestrator");
Object.defineProperty(exports, "TestOrchestrator", { enumerable: true, get: function () { return TestOrchestrator_1.TestOrchestrator; } });
//# sourceMappingURL=index.js.map