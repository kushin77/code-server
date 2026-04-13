"use strict";
/**
 * Phase 12: Multi-Site Federation & Geographic Distribution
 *
 * This module provides enterprise-grade multi-region deployment capabilities:
 * - Service discovery and registration across geographic regions
 * - Cross-region data replication with conflict resolution
 * - Intelligent request routing based on geography and performance
 * - Global load balancing with multiple routing strategies
 * - Automatic conflict detection and resolution
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.MultiSiteFederationOrchestrator = exports.GeoLoadBalancer = exports.CrossRegionReplicator = exports.GeographicRegistry = void 0;
var GeographicRegistry_1 = require("./GeographicRegistry");
Object.defineProperty(exports, "GeographicRegistry", { enumerable: true, get: function () { return GeographicRegistry_1.GeographicRegistry; } });
var CrossRegionReplicator_1 = require("./CrossRegionReplicator");
Object.defineProperty(exports, "CrossRegionReplicator", { enumerable: true, get: function () { return CrossRegionReplicator_1.CrossRegionReplicator; } });
var GeoLoadBalancer_1 = require("./GeoLoadBalancer");
Object.defineProperty(exports, "GeoLoadBalancer", { enumerable: true, get: function () { return GeoLoadBalancer_1.GeoLoadBalancer; } });
var MultiSiteFederationOrchestrator_1 = require("./MultiSiteFederationOrchestrator");
Object.defineProperty(exports, "MultiSiteFederationOrchestrator", { enumerable: true, get: function () { return MultiSiteFederationOrchestrator_1.MultiSiteFederationOrchestrator; } });
//# sourceMappingURL=index.js.map