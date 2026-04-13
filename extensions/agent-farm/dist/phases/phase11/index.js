"use strict";
/**
 * Phase 11: Advanced Resilience, HA/DR & Observability
 *
 * This module provides enterprise-grade high availability and disaster recovery:
 * - Continuous health monitoring across all system components
 * - Automatic failover with customizable strategies
 * - Disaster recovery orchestration (backup, recovery, testing)
 * - Chaos engineering for resilience validation
 * - SLO tracking (RTO < 1h, RPO < 15min, availability 99.9%)
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.ResilienceOrchestrator = exports.FailoverState = exports.FailoverManager = exports.HealthMonitor = void 0;
var HealthMonitor_1 = require("./HealthMonitor");
Object.defineProperty(exports, "HealthMonitor", { enumerable: true, get: function () { return HealthMonitor_1.HealthMonitor; } });
var FailoverManager_1 = require("./FailoverManager");
Object.defineProperty(exports, "FailoverManager", { enumerable: true, get: function () { return FailoverManager_1.FailoverManager; } });
Object.defineProperty(exports, "FailoverState", { enumerable: true, get: function () { return FailoverManager_1.FailoverState; } });
var ResilienceOrchestrator_1 = require("./ResilienceOrchestrator");
Object.defineProperty(exports, "ResilienceOrchestrator", { enumerable: true, get: function () { return ResilienceOrchestrator_1.ResilienceOrchestrator; } });
//# sourceMappingURL=index.js.map