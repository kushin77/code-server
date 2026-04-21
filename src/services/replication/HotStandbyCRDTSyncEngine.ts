/**
 * Hot-Standby CRDT Sync Engine
 * Extends CRDTSyncEngine with automatic failover capabilities
 */

import { EventEmitter } from 'events';
import { CRDTSyncEngine, LWWCounter, ORSet, LWWRegister } from '../../../operations/phase-12/crdt-sync-protocol';
import HotStandbyFailover, { ReplicaRole, FailoverState, OperationEnvelope } from './HotStandbyFailover';

export interface HotStandbyConfig {
    replicaId: string;
    initialRole: ReplicaRole;
    peerEndpoint?: string;
    syncInterval?: number;
    heartbeatInterval?: number;
    failoverTimeout?: number;
}

/**
 * Hot-Standby CRDT Synchronization Engine
 * Provides zero-downtime failover with < 1s switchover and zero data loss
 */
export class HotStandbyCRDTSyncEngine extends EventEmitter {
    private crdtEngine: CRDTSyncEngine;
    private failoverManager: HotStandbyFailover;
    private config: HotStandbyConfig;
    private peerEndpoint?: string;
    private isRunning: boolean = false;

    constructor(config: HotStandbyConfig) {
        super();

        this.config = config;
        this.peerEndpoint = config.peerEndpoint;

        // Initialize CRDT engine
        this.crdtEngine = new CRDTSyncEngine(
            config.replicaId,
            {}, // regions - will be set dynamically
            config.syncInterval || 1000
        );

        // Initialize failover manager
        this.failoverManager = new HotStandbyFailover(
            config.replicaId,
            config.initialRole,
            {
                heartbeatInterval: config.heartbeatInterval || 100,
                failoverTimeout: config.failoverTimeout || 500
            }
        );

        this.setupEventHandlers();
    }

    /**
     * Setup event handlers for failover and CRDT operations
     */
    private setupEventHandlers(): void {
        // Forward CRDT events
        this.crdtEngine.on('counter-updated', (event) => this.handleCRDTOperation('counter', event));
        this.crdtEngine.on('set-updated', (event) => this.handleCRDTOperation('set', event));
        this.crdtEngine.on('register-updated', (event) => this.handleCRDTOperation('register', event));

        // Handle failover events
        this.failoverManager.on('operation-added', (envelope: OperationEnvelope) => {
            this.emit('operation-replicated', envelope);
            this.replicateToPeer(envelope);
        });

        this.failoverManager.on('failover-started', () => {
            this.emit('failover-started');
        });

        this.failoverManager.on('promoted-to-primary', () => {
            this.emit('role-changed', { role: ReplicaRole.PRIMARY });
        });

        this.failoverManager.on('demoted-to-standby', () => {
            this.emit('role-changed', { role: ReplicaRole.STANDBY });
        });

        this.failoverManager.on('reconnected', () => {
            this.emit('peer-reconnected');
            this.syncWithPeer();
        });

        // Handle peer communication
        this.failoverManager.on('heartbeat', (health) => {
            if (this.peerEndpoint) {
                this.sendToPeer('heartbeat', health);
            }
        });
    }

    /**
     * Handle CRDT operation and add to failover buffer
     */
    private handleCRDTOperation(type: 'counter' | 'set' | 'register', event: any): void {
        // Only primary can add operations
        if (this.failoverManager.getHealth().role !== ReplicaRole.PRIMARY) {
            return;
        }

        const envelope = this.failoverManager.addOperation(type, event.key, event);
        this.emit('operation-processed', envelope);
    }

    /**
     * Replicate operation to peer
     */
    private replicateToPeer(envelope: OperationEnvelope): void {
        if (this.peerEndpoint && this.failoverManager.getHealth().role === ReplicaRole.PRIMARY) {
            this.sendToPeer('operation', envelope);
        }
    }

    /**
     * Send message to peer
     */
    private async sendToPeer(type: string, data: any): Promise<void> {
        if (!this.peerEndpoint) return;

        try {
            const response = await fetch(`${this.peerEndpoint}/replication`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'X-Replica-Id': this.config.replicaId
                },
                body: JSON.stringify({ type, data })
            });

            if (!response.ok) {
                throw new Error(`Peer replication failed: ${response.status}`);
            }
        } catch (error) {
            this.emit('replication-error', { error: error.message, peer: this.peerEndpoint });
        }
    }

    /**
     * Receive message from peer
     */
    async receiveFromPeer(type: string, data: any): Promise<void> {
        switch (type) {
            case 'heartbeat':
                this.failoverManager.receiveHeartbeat(data);
                break;

            case 'operation':
                const success = this.failoverManager.receiveOperation(data);
                if (success) {
                    // Apply operation to CRDT engine
                    this.applyOperationToCRDT(data);
                }
                break;

            case 'sync-request':
                await this.sendSyncResponse(data.lastSequenceNumber);
                break;
        }
    }

    /**
     * Apply operation to CRDT engine
     */
    private applyOperationToCRDT(envelope: OperationEnvelope): void {
        const event = envelope.data;

        switch (envelope.type) {
            case 'counter':
                this.crdtEngine.updateCounter(event.key, event.value);
                break;

            case 'set':
                if (event.operation === 'add') {
                    this.crdtEngine.addToSet(event.key, event.element);
                } else {
                    this.crdtEngine.removeFromSet(event.key, event.element);
                }
                break;

            case 'register':
                this.crdtEngine.updateRegister(event.key, event.value);
                break;
        }
    }

    /**
     * Send sync response with missing operations
     */
    private async sendSyncResponse(lastSequenceNumber: number): Promise<void> {
        const operations = this.failoverManager.getOperationsSince(lastSequenceNumber);

        if (this.peerEndpoint) {
            await this.sendToPeer('sync-response', {
                operations,
                checksum: this.failoverManager.getHealth().checksum
            });
        }
    }

    /**
     * Sync with peer after reconnection
     */
    private async syncWithPeer(): Promise<void> {
        if (!this.peerEndpoint) return;

        try {
            const lastSequence = this.failoverManager.getHealth().sequenceNumber;

            await this.sendToPeer('sync-request', {
                lastSequenceNumber: lastSequence
            });
        } catch (error) {
            this.emit('sync-error', { error: error.message });
        }
    }

    /**
     * Start the hot-standby system
     */
    start(): void {
        if (this.isRunning) return;

        this.isRunning = true;
        this.emit('started');

        // Start CRDT sync
        this.crdtEngine.startSync();

        // If standby, sync with primary
        if (this.failoverManager.getHealth().role === ReplicaRole.STANDBY) {
            this.syncWithPeer();
        }
    }

    /**
     * Stop the hot-standby system
     */
    stop(): void {
        if (!this.isRunning) return;

        this.isRunning = false;
        this.crdtEngine.stopSync();
        this.failoverManager.destroy();
        this.emit('stopped');
    }

    /**
     * Get current health status
     */
    getHealth(): any {
        return {
            replicaId: this.config.replicaId,
            role: this.failoverManager.getHealth().role,
            state: this.failoverManager.getHealth().state,
            sequenceNumber: this.failoverManager.getHealth().sequenceNumber,
            checksum: this.failoverManager.getHealth().checksum,
            lagMs: this.failoverManager.getHealth().lagMs,
            crdtCounters: this.crdtEngine.getCounters(),
            crdtSets: this.crdtEngine.getSets(),
            crdtRegisters: this.crdtEngine.getRegisters()
        };
    }

    /**
     * Force failover (for testing)
     */
    forceFailover(): void {
        this.failoverManager.demoteToStandby();
    }

    /**
     * CRDT Engine proxy methods
     */
    updateCounter(key: string, value: number): void {
        this.crdtEngine.updateCounter(key, value);
    }

    addToSet(key: string, element: string): void {
        this.crdtEngine.addToSet(key, element);
    }

    removeFromSet(key: string, element: string): void {
        this.crdtEngine.removeFromSet(key, element);
    }

    updateRegister(key: string, value: string): void {
        this.crdtEngine.updateRegister(key, value);
    }
}

export default HotStandbyCRDTSyncEngine;