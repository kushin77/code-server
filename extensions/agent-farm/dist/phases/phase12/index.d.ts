/**
 * Phase 12: Multi-Site Federation & Geographic Distribution
 * Handles distributed deployment across 6+ regions
 */
export interface Phase12Config {
    regions: string[];
    replicationFactor: number;
    consistencyLevel: 'strong' | 'eventual';
    failoverStrategy: 'active-passive' | 'active-active';
}
export interface Phase12Result {
    status: 'success' | 'partial' | 'failed';
    deployedRegions: string[];
    failedRegions: string[];
    syncStatus: Record<string, boolean>;
}
/**
 * Execute Phase 12 deployment
 */
export declare function executePhase12(config: Phase12Config): Promise<Phase12Result>;
/**
 * Validate Phase 12 prerequisites
 */
export declare function validatePhase12Prerequisites(): Promise<boolean>;
/**
 * Rollback Phase 12 deployment
 */
export declare function rollbackPhase12(): Promise<void>;
//# sourceMappingURL=index.d.ts.map