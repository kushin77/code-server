"use strict";
/**
 * Phase 11: Advanced Resilience & HA/DR
 * Exports for circuit breakers, failover, and chaos engineering
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.Phase11Examples = exports.ResiliencePhase11Agent = exports.ChaosEngineer = exports.FailoverManager = exports.CircuitBreaker = void 0;
var CircuitBreaker_1 = require("../../ml/CircuitBreaker");
Object.defineProperty(exports, "CircuitBreaker", { enumerable: true, get: function () { return CircuitBreaker_1.CircuitBreaker; } });
var FailoverManager_1 = require("../../ml/FailoverManager");
Object.defineProperty(exports, "FailoverManager", { enumerable: true, get: function () { return FailoverManager_1.FailoverManager; } });
var ChaosEngineer_1 = require("../../ml/ChaosEngineer");
Object.defineProperty(exports, "ChaosEngineer", { enumerable: true, get: function () { return ChaosEngineer_1.ChaosEngineer; } });
var ResiliencePhase11Agent_1 = require("../../agents/ResiliencePhase11Agent");
Object.defineProperty(exports, "ResiliencePhase11Agent", { enumerable: true, get: function () { return ResiliencePhase11Agent_1.ResiliencePhase11Agent; } });
/**
 * Phase 11 Configuration Examples
 */
exports.Phase11Examples = {
    circuitBreakerConfig: {
        name: 'api-service',
        failureThreshold: 5,
        resetTimeout: 30000,
        halfOpenRequests: 3,
        monitoringWindow: 60000,
    },
    failoverConfig: {
        strategy: 'active-passive',
        healthCheckInterval: 5000,
        failureThreshold: 3,
        replicationDelay: 100,
        autoFailover: true,
    },
    chaosTestScenario: {
        name: 'Latency Spike Test',
        scenario: 'latency',
        targetServices: ['api-gateway', 'data-service'],
        duration: 60000,
        intensity: 0.8,
    },
    slaTargets: {
        availability: 99.99,
        maxRecoveryTime: 30000,
        maxDataLoss: 0,
    },
};
//# sourceMappingURL=index.js.map