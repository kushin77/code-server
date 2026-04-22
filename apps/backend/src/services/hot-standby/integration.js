/**
 * @file        apps/backend/src/services/hot-standby/integration.ts
 * @module      services/hot-standby
 * @description Integration helper for hot-standby failover with session-broker
 */
import { HotStandbyStateMachine } from './state-machine';
import logger from '../observability/logger';
/**
 * Integration factory for creating and managing hot-standby instances
 */
export class HotStandbyIntegration {
    constructor(redis) {
        this.redis = redis;
        this.stateMachine = null;
        this.enabled = false;
    }
    /**
     * Enable hot-standby failover for session broker
     */
    async enable(options) {
        try {
            this.stateMachine = new HotStandbyStateMachine(options.brokerId, options.remoteBrokerId, this.redis, options.config);
            // Set up event listeners
            this.stateMachine.on('promoted_to_primary', (event) => {
                logger.info('Hot-standby: Replica promoted to primary', {
                    brokerId: event.brokerId,
                    duration: event.duration,
                });
            });
            this.stateMachine.on('recovery_completed', (event) => {
                logger.info('Hot-standby: Recovery completed', {
                    brokerId: event.brokerId,
                });
            });
            this.stateMachine.on('split_brain_prevented', () => {
                logger.warn('Hot-standby: Split-brain scenario prevented');
            });
            this.stateMachine.on('heartbeat_error', (event) => {
                logger.error('Hot-standby: Heartbeat error', { error: event.error });
            });
            this.stateMachine.on('audit_event', (event) => {
                logger.debug('Hot-standby: Audit event', { event });
            });
            await this.stateMachine.initialize(options.role);
            this.enabled = true;
            logger.info('Hot-standby failover enabled', {
                brokerId: options.brokerId,
                role: options.role,
            });
        }
        catch (error) {
            logger.error('Failed to enable hot-standby failover', { error });
            throw error;
        }
    }
    /**
     * Disable hot-standby failover
     */
    async disable() {
        if (this.stateMachine) {
            await this.stateMachine.shutdown();
            this.stateMachine = null;
            this.enabled = false;
            logger.info('Hot-standby failover disabled');
        }
    }
    /**
     * Check if hot-standby is enabled
     */
    isEnabled() {
        return this.enabled && this.stateMachine !== null;
    }
    /**
     * Get current status
     */
    getStatus() {
        if (!this.stateMachine) {
            return null;
        }
        return this.stateMachine.getStatus();
    }
    /**
     * Update session count (call from session-broker)
     */
    updateSessionCount(count) {
        if (this.stateMachine && this.enabled) {
            this.stateMachine.updateSessionCount(count);
        }
    }
    /**
     * Get failover history
     */
    getFailoverHistory() {
        if (!this.stateMachine) {
            return [];
        }
        return this.stateMachine.getFailoverHistory();
    }
    /**
     * Get underlying state machine (for advanced usage)
     */
    getStateMachine() {
        return this.stateMachine;
    }
}
/**
 * Create a singleton instance
 */
let instance = null;
export function createHotStandbyIntegration(redis) {
    if (!instance) {
        instance = new HotStandbyIntegration(redis);
    }
    return instance;
}
export function getHotStandbyIntegration() {
    return instance;
}
//# sourceMappingURL=integration.js.map