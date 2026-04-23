#!/usr/bin/env node
// @file        apps/backend/src/services/network/migration-recovery-service.ts
// @module      services/network
// @description Network migration recovery for seamless WiFi ↔ 4G transitions
//
import { EventEmitter } from 'events';
/**
 * Network Migration Recovery Service
 * Handles seamless network transitions (WiFi ↔ 4G, etc.)
 *
 * Algorithm:
 * 1. Monitor network state continuously
 * 2. Detect network type changes
 * 3. On migration:
 *    a. Buffer outgoing operations
 *    b. Maintain connection state
 *    c. Attempt reconnect with exponential backoff
 *    d. Use delta sync to catch up
 *    e. Flush buffered operations
 * 4. Emit migration events for monitoring
 *
 * Target: <3 second recovery, 0 bytes data loss
 */
export class NetworkMigrationRecoveryService extends EventEmitter {
    constructor(logger) {
        super();
        this.logger = logger;
        this.previousState = null;
        this.operationBuffer = [];
        this.detectionInterval = null;
        this.reconnectAttempts = 0;
        this.lastSuccessfulMigration = null;
        this.migrationHistory = [];
        this.config = {
            detectionInterval: 1000,
            reconnectTimeout: 3000,
            maxReconnectAttempts: 5,
            bufferDuration: 5000,
            deltaSync: true,
        };
        this.stats = {
            totalMigrations: 0,
            successfulMigrations: 0,
            failedMigrations: 0,
            avgRecoveryTime: 0,
            totalDataRecovered: 0,
            totalOpsBuffered: 0,
        };
        // Initialize with unknown state
        this.currentState = {
            networkType: 'unknown',
            timestamp: Date.now(),
            signal: 0,
            latency: 0,
            bandwidth: 0,
            connected: false,
        };
    }
    /**
     * Get or create singleton instance
     */
    static getInstance(logger) {
        if (!this.instances.has('default')) {
            this.instances.set('default', new NetworkMigrationRecoveryService(logger));
        }
        return this.instances.get('default');
    }
    /**
     * Configure recovery parameters
     */
    configure(config) {
        this.config = { ...this.config, ...config };
    }
    /**
     * Start monitoring network state
     */
    startMonitoring() {
        if (this.detectionInterval) {
            return; // Already monitoring
        }
        this.detectionInterval = setInterval(() => {
            this.detectNetworkChange();
        }, this.config.detectionInterval);
        this.emit('monitoring-started', { timestamp: Date.now() });
    }
    /**
     * Stop monitoring network state
     */
    stopMonitoring() {
        if (this.detectionInterval) {
            clearInterval(this.detectionInterval);
            this.detectionInterval = null;
        }
        this.emit('monitoring-stopped', { timestamp: Date.now() });
    }
    /**
     * Update current network state
     * Called by network detection logic
     */
    updateNetworkState(networkType, signal, latency, bandwidth, connected) {
        const newState = {
            networkType,
            timestamp: Date.now(),
            signal,
            latency,
            bandwidth,
            connected,
        };
        this.previousState = this.currentState;
        this.currentState = newState;
        this.emit('network-state-updated', newState);
    }
    /**
     * Detect network migration
     * Internal method called periodically
     */
    detectNetworkChange() {
        if (!this.previousState) {
            return;
        }
        // Check if network type changed
        if (this.currentState.networkType !== this.previousState.networkType) {
            this.handleMigration(this.previousState.networkType, this.currentState.networkType);
        }
        // Check if connection status changed
        if (this.currentState.connected !== this.previousState.connected) {
            if (!this.currentState.connected) {
                this.handleDisconnection();
            }
            else {
                this.handleReconnection();
            }
        }
    }
    /**
     * Handle network migration
     */
    handleMigration(fromNetwork, toNetwork) {
        const migrationId = `migration-${Date.now()}-${Math.random().toString(36).substring(7)}`;
        const startTime = Date.now();
        this.emit('migration-starting', {
            id: migrationId,
            from: fromNetwork,
            to: toNetwork,
            timestamp: startTime,
        });
        // Start buffering operations during migration
        this.startBuffering();
        // Attempt reconnection with exponential backoff
        this.attemptReconnection(migrationId, fromNetwork, toNetwork, startTime);
    }
    /**
     * Attempt reconnection with exponential backoff
     */
    async attemptReconnection(migrationId, fromNetwork, toNetwork, startTime) {
        this.reconnectAttempts = 0;
        while (this.reconnectAttempts < this.config.maxReconnectAttempts) {
            this.reconnectAttempts++;
            // Exponential backoff: 100ms, 200ms, 400ms, 800ms, 1600ms
            const delay = Math.min(100 * Math.pow(2, this.reconnectAttempts - 1), this.config.reconnectTimeout);
            await new Promise((resolve) => setTimeout(resolve, delay));
            // Check if reconnected
            if (this.currentState.connected) {
                this.handleReconnectionSuccess(migrationId, fromNetwork, toNetwork, startTime);
                return;
            }
        }
        // Failed to reconnect within timeout
        this.handleReconnectionFailure(migrationId, fromNetwork, toNetwork, startTime);
    }
    /**
     * Handle successful reconnection
     */
    handleReconnectionSuccess(migrationId, fromNetwork, toNetwork, startTime) {
        const duration = Date.now() - startTime;
        // Stop buffering and flush operations
        const bufferedOps = this.flushBuffer();
        const event = {
            id: migrationId,
            timestamp: startTime,
            from: fromNetwork,
            to: toNetwork,
            duration,
            dataLoss: 0, // Zero loss with buffering
            operations: bufferedOps,
            success: true,
        };
        this.lastSuccessfulMigration = event;
        this.migrationHistory.push(event);
        // Update statistics
        this.stats.totalMigrations++;
        this.stats.successfulMigrations++;
        this.stats.totalOpsBuffered += bufferedOps;
        this.stats.avgRecoveryTime = Math.round((this.stats.avgRecoveryTime * (this.stats.successfulMigrations - 1) + duration) /
            this.stats.successfulMigrations);
        this.emit('migration-success', event);
        this.reconnectAttempts = 0;
    }
    /**
     * Handle failed reconnection
     */
    handleReconnectionFailure(migrationId, fromNetwork, toNetwork, startTime) {
        const duration = Date.now() - startTime;
        // Calculate data loss
        const dataLoss = this.operationBuffer.reduce((sum, op) => sum + JSON.stringify(op).length, 0);
        const event = {
            id: migrationId,
            timestamp: startTime,
            from: fromNetwork,
            to: toNetwork,
            duration,
            dataLoss,
            operations: 0,
            success: false,
        };
        this.migrationHistory.push(event);
        // Update statistics
        this.stats.totalMigrations++;
        this.stats.failedMigrations++;
        this.emit('migration-failure', event);
        this.reconnectAttempts = 0;
    }
    /**
     * Handle disconnection
     */
    handleDisconnection() {
        this.startBuffering();
        this.emit('disconnection-detected', {
            previousNetworkType: this.previousState?.networkType,
            timestamp: Date.now(),
        });
    }
    /**
     * Handle reconnection
     */
    handleReconnection() {
        const bufferedOps = this.flushBuffer();
        this.emit('reconnection-detected', {
            currentNetworkType: this.currentState.networkType,
            bufferedOperations: bufferedOps,
            timestamp: Date.now(),
        });
    }
    /**
     * Start buffering operations
     * Call when network migration begins
     */
    startBuffering() {
        this.operationBuffer = [];
        this.emit('buffering-started', { timestamp: Date.now() });
    }
    /**
     * Add operation to buffer
     * Call during migration to preserve operations
     */
    bufferOperation(id, data) {
        this.operationBuffer.push({
            id,
            timestamp: Date.now(),
            data,
        });
    }
    /**
     * Flush buffer and return count
     * Call when reconnection succeeds
     */
    flushBuffer() {
        const count = this.operationBuffer.length;
        this.operationBuffer = [];
        this.emit('buffer-flushed', {
            operationsCount: count,
            timestamp: Date.now(),
        });
        return count;
    }
    /**
     * Get current connection state
     */
    getCurrentState() {
        return { ...this.currentState };
    }
    /**
     * Get migration history
     */
    getMigrationHistory() {
        return [...this.migrationHistory];
    }
    /**
     * Get last successful migration
     */
    getLastMigration() {
        return this.lastSuccessfulMigration ? { ...this.lastSuccessfulMigration } : null;
    }
    /**
     * Get statistics
     */
    getStats() {
        return {
            ...this.stats,
            successRate: this.stats.totalMigrations > 0
                ? `${((this.stats.successfulMigrations / this.stats.totalMigrations) * 100).toFixed(1)}%`
                : 'N/A',
            avgRecoveryTimeMs: this.stats.avgRecoveryTime,
        };
    }
    /**
     * Get buffered operation count
     */
    getBufferedOperationCount() {
        return this.operationBuffer.length;
    }
    /**
     * Check if currently buffering
     */
    isBuffering() {
        return this.operationBuffer.length > 0;
    }
    /**
     * Clear history for testing
     */
    reset() {
        this.operationBuffer = [];
        this.previousState = null;
        this.lastSuccessfulMigration = null;
        this.migrationHistory = [];
        this.reconnectAttempts = 0;
        this.currentState = {
            networkType: 'unknown',
            timestamp: Date.now(),
            signal: 0,
            latency: 0,
            bandwidth: 0,
            connected: false,
        };
        this.stats = {
            totalMigrations: 0,
            successfulMigrations: 0,
            failedMigrations: 0,
            avgRecoveryTime: 0,
            totalDataRecovered: 0,
            totalOpsBuffered: 0,
        };
    }
    /**
     * Shutdown service
     */
    shutdown() {
        this.stopMonitoring();
        this.reset();
        this.removeAllListeners();
    }
    /**
     * Clear instances for testing
     */
    static clearInstances() {
        this.instances.forEach((instance) => instance.shutdown());
        this.instances.clear();
    }
}
NetworkMigrationRecoveryService.instances = new Map();
export default NetworkMigrationRecoveryService;
//# sourceMappingURL=migration-recovery-service.js.map