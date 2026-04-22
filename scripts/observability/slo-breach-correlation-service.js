#!/usr/bin/env node
/**
 * @file        scripts/observability/slo-breach-correlation-service.js
 * @module      observability/slo
 * @description SLO breach auto-correlation with deployment and config changes
 *
 * IaC Principles:
 * - Immutable: SLO breach events frozen once detected
 * - Immutable: Correlation matches frozen
 * - Idempotent: Same SLO + deploy combo = same correlation
 * - Versioned: Breach records versioned for audit trails
 */

const EventEmitter = require('events');
const crypto = require('crypto');

class SLOBreachCorrelationService extends EventEmitter {
    constructor(options = {}) {
        super();
        
        this.serviceName = options.serviceName || 'code-server';
        
        // Immutable SLO breach events (frozen)
        this.sloBreaches = new Map(); // breachId → frozen breach
        
        // Deployment events (frozen)
        this.deployments = new Map(); // deployId → frozen deployment
        
        // Config changes (frozen)
        this.configChanges = new Map(); // changeId → frozen change
        
        // Correlation matches (frozen)
        this.correlationMatches = new Map(); // matchId → frozen match
        
        // Token-based idempotency
        this.breachTokens = new Map(); // token → breachId
        this.correlationTokens = new Map(); // token → matchId
    }
    
    /**
     * Record SLO breach (immutable)
     */
    recordSLOBreach(breachData, breachToken) {
        // Idempotency check
        if (breachToken && this.breachTokens.has(breachToken)) {
            return this.breachTokens.get(breachToken);
        }
        
        const breachId = `breach-${crypto.randomBytes(8).toString('hex')}`;
        const now = Date.now();
        
        // Create immutable breach event
        const breach = {
            // Identifiers (immutable)
            breachId,
            sloId: breachData.sloId,
            sloName: breachData.sloName,
            
            // SLO violation (immutable)
            metric: breachData.metric,  // latency_p99, availability, etc.
            threshold: breachData.threshold,
            actualValue: breachData.actualValue,
            breachPct: Math.round(
                ((breachData.actualValue - breachData.threshold) / breachData.threshold) * 100 * 10
            ) / 10,
            
            // Time window (immutable)
            startTime: breachData.startTime || now - 300000,  // 5 min window
            endTime: now,
            duration: now - (breachData.startTime || now - 300000),
            
            // Severity (immutable)
            severity: breachData.severity || 'high',
            errorBudgetRemaining: breachData.errorBudgetRemaining || 0,
            
            // Context (immutable)
            workspaceId: breachData.workspaceId,
            component: breachData.component || 'unknown',
            
            // Status (mutable initially)
            status: 'detecting-cause',  // detecting-cause, correlated, resolved
            
            // Detected correlations (immutable array)
            correlations: [],
            
            // Timestamps (immutable)
            detectedAt: new Date().toISOString(),
            detectedAtMs: now,
            
            version: 1,
        };
        
        // Freeze breach
        Object.freeze(breach);
        this.sloBreaches.set(breachId, breach);
        
        if (breachToken) {
            this.breachTokens.set(breachToken, breachId);
        }
        
        this.emit('slo-breach-detected', {
            breachId,
            sloName: breach.sloName,
            breachPct: breach.breachPct,
            severity: breach.severity,
        });
        
        return breachId;
    }
    
    /**
     * Record deployment (immutable)
     */
    recordDeployment(deploymentData) {
        const deployId = `deploy-${crypto.randomBytes(8).toString('hex')}`;
        const now = Date.now();
        
        const deployment = {
            // Identifiers (immutable)
            deployId,
            commitSha: deploymentData.commitSha,
            version: deploymentData.version,
            
            // Deployment info (immutable)
            environment: deploymentData.environment || 'production',
            startTime: now,
            startTimeIso: new Date().toISOString(),
            endTime: deploymentData.endTime || now,
            duration: (deploymentData.endTime || now) - now,
            
            // Changes (immutable)
            filesChanged: deploymentData.filesChanged || 0,
            linesAdded: deploymentData.linesAdded || 0,
            linesRemoved: deploymentData.linesRemoved || 0,
            
            // Services (immutable)
            services: Object.freeze(deploymentData.services || []),
            
            // Status (immutable)
            status: 'completed',
            success: true,
            
            deployedBy: deploymentData.deployedBy,
            description: deploymentData.description || '',
            
            version: 1,
        };
        
        Object.freeze(deployment);
        this.deployments.set(deployId, deployment);
        
        this.emit('deployment-recorded', {
            deployId,
            version: deployment.version,
            services: deployment.services,
        });
        
        return deployId;
    }
    
    /**
     * Record config change (immutable)
     */
    recordConfigChange(changeData) {
        const changeId = `config-${crypto.randomBytes(8).toString('hex')}`;
        const now = Date.now();
        
        const change = {
            // Identifiers (immutable)
            changeId,
            configKey: changeData.configKey,
            service: changeData.service,
            
            // Change details (immutable)
            oldValue: changeData.oldValue,
            newValue: changeData.newValue,
            
            // Change type (immutable)
            changeType: changeData.changeType,  // update, create, delete
            environment: changeData.environment || 'production',
            
            // Timing (immutable)
            appliedAt: new Date().toISOString(),
            appliedAtMs: now,
            
            // Who made change (immutable)
            changedBy: changeData.changedBy,
            reason: changeData.reason || '',
            
            // Impact (immutable)
            affectedComponents: Object.freeze(changeData.affectedComponents || []),
            impactLevel: changeData.impactLevel || 'medium',  // low, medium, high
            
            version: 1,
        };
        
        Object.freeze(change);
        this.configChanges.set(changeId, change);
        
        this.emit('config-change-recorded', {
            changeId,
            configKey: change.configKey,
            service: change.service,
            impactLevel: change.impactLevel,
        });
        
        return changeId;
    }
    
    /**
     * Correlate SLO breach with deployment (idempotent)
     */
    correlateBreachwithDeployment(breachId, deployId, correlationToken) {
        // Idempotency check
        if (correlationToken && this.correlationTokens.has(correlationToken)) {
            return this.correlationTokens.get(correlationToken);
        }
        
        const breach = this.sloBreaches.get(breachId);
        const deploy = this.deployments.get(deployId);
        
        if (!breach) throw new Error(`Breach ${breachId} not found`);
        if (!deploy) throw new Error(`Deployment ${deployId} not found`);
        
        const matchId = `match-${crypto.randomBytes(8).toString('hex')}`;
        const now = Date.now();
        
        // Calculate time delta (deployment → breach)
        const timeDeltaMs = breach.detectedAtMs - deploy.endTime;
        const timeDeltaMin = Math.round(timeDeltaMs / 60000);
        
        // Assess correlation confidence
        let confidence = 0;
        let reasons = [];
        
        if (timeDeltaMs >= -300000 && timeDeltaMs <= 600000) {  // -5 to +10 min window
            confidence += 0.4;  // Strong time correlation
            reasons.push(`Deployment ${timeDeltaMin}min before breach`);
        }
        
        // Check if deployed service matches affected component
        if (deploy.services.includes(breach.component)) {
            confidence += 0.35;  // Service match
            reasons.push(`Deployed service matches affected component: ${breach.component}`);
        }
        
        // Check deployment size (risky deployments are larger)
        if (deploy.linesAdded > 500 || deploy.filesChanged > 20) {
            confidence += 0.15;  // Large deployment risk
            reasons.push(`Large deployment: ${deploy.filesChanged} files, ${deploy.linesAdded} lines added`);
        }
        
        // Cap confidence at 100%
        confidence = Math.min(confidence, 1.0);
        
        // Create immutable correlation match
        const match = {
            // Identifiers (immutable)
            matchId,
            breachId,
            deployId,
            
            // Correlation data (immutable)
            confidence: Math.round(confidence * 1000) / 1000,
            reasons: Object.freeze(reasons),
            
            // Timing (immutable)
            detectedAt: new Date().toISOString(),
            detectedAtMs: now,
            timeDeltaMs,
            timeDeltaMin,
            
            // Breach & deploy info (immutable snapshots)
            sloName: breach.sloName,
            metric: breach.metric,
            breachPct: breach.breachPct,
            deployVersion: deploy.version,
            deployedServices: Object.freeze([...deploy.services]),
            
            // Assessment (immutable)
            likelyRootCause: confidence > 0.7,
            recommendedAction: this.generateRecommendation(confidence, deploy, breach),
            
            version: 1,
        };
        
        Object.freeze(match);
        this.correlationMatches.set(matchId, match);
        
        if (correlationToken) {
            this.correlationTokens.set(correlationToken, matchId);
        }
        
        // Update breach with correlation (new version)
        const updatedBreach = {
            ...breach,
            correlations: [...(breach.correlations || []), matchId],
            status: confidence > 0.7 ? 'correlated' : 'detecting-cause',
            version: breach.version + 1,
        };
        Object.freeze(updatedBreach);
        this.sloBreaches.set(breachId, updatedBreach);
        
        this.emit('breach-deployment-correlated', {
            matchId,
            breachId,
            deployId,
            confidence: match.confidence,
            likelyRootCause: match.likelyRootCause,
        });
        
        return matchId;
    }
    
    /**
     * Generate recommended action
     */
    generateRecommendation(confidence, deploy, breach) {
        if (confidence > 0.9) {
            return `LIKELY ROOT CAUSE: Deployment v${deploy.version}. Consider rollback if SLO breach continues.`;
        } else if (confidence > 0.7) {
            return `PROBABLE CAUSE: Deployment v${deploy.version}. Monitor metrics closely; prepare rollback if needed.`;
        } else if (confidence > 0.5) {
            return `POSSIBLE CAUSE: Deployment v${deploy.version}. May be coincidental timing; investigate other factors.`;
        }
        return `WEAK CORRELATION: Deployment v${deploy.version}. Likely unrelated to ${breach.sloName} breach.`;
    }
    
    /**
     * Get correlation match (immutable snapshot)
     */
    getCorrelationMatch(matchId) {
        const match = this.correlationMatches.get(matchId);
        return match ? Object.freeze({ ...match }) : null;
    }
    
    /**
     * Get SLO breach (immutable snapshot)
     */
    getSLOBreach(breachId) {
        const breach = this.sloBreaches.get(breachId);
        return breach ? Object.freeze({ ...breach }) : null;
    }
    
    /**
     * Query correlation matches (immutable array)
     */
    queryCorrelationMatches(filters = {}) {
        let matches = Array.from(this.correlationMatches.values());
        
        // Filter by breach
        if (filters.breachId) {
            matches = matches.filter(m => m.breachId === filters.breachId);
        }
        
        // Filter by confidence
        if (filters.minConfidence) {
            matches = matches.filter(m => m.confidence >= filters.minConfidence);
        }
        
        // Filter by likely root cause
        if (filters.likelyRootCause !== undefined) {
            matches = matches.filter(m => m.likelyRootCause === filters.likelyRootCause);
        }
        
        // Sort by confidence (descending)
        matches.sort((a, b) => b.confidence - a.confidence);
        
        // Limit
        const limit = filters.limit || 100;
        return Object.freeze(
            matches.slice(0, limit).map(m => Object.freeze(m))
        );
    }
    
    /**
     * Get correlation statistics (immutable)
     */
    getCorrelationStatistics() {
        const matches = Array.from(this.correlationMatches.values());
        
        const stats = {
            totalMatches: matches.length,
            likelyRootCauses: matches.filter(m => m.likelyRootCause).length,
            averageConfidence: matches.length > 0
                ? matches.reduce((sum, m) => sum + m.confidence, 0) / matches.length
                : 0,
            byConfidenceLevel: {
                high: matches.filter(m => m.confidence > 0.7).length,
                medium: matches.filter(m => 0.5 < m.confidence && m.confidence <= 0.7).length,
                low: matches.filter(m => m.confidence <= 0.5).length,
            },
            deploymentCorrelations: this.deployments.size,
            totalBreaches: this.sloBreaches.size,
        };
        
        return Object.freeze(stats);
    }
}

module.exports = SLOBreachCorrelationService;
