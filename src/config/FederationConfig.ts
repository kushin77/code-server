/**
 * Phase 12.1: Infrastructure as Code - Region Configuration
 * Defines the 5-region federation infrastructure with dynamic discovery
 */

export interface RegionConfig {
  regionId: string;
  regionName: string;
  cloudProvider: 'gcp' | 'aws' | 'azure';
  projectId: string;
  location: string;
  kubernetesVersion: string;
  nodeCount: number;
  machineType: string;
  diskSizeGb: number;
  network: {
    cidr: string;
    pods: string;
    services: string;
  };
  database: {
    version: string;
    backupRetentionDays: number;
    computeNodes: number;
  };
  tags: Record<string, string>;
}

export interface FederationConfig {
  federationId: string;
  federationName: string;
  createdAt: Date;
  regions: RegionConfig[];
  globalConfig: {
    replicationMode: 'multi-primary' | 'primary-replica';
    conflictResolution: 'lww' | 'custom';
    syncIntervalMs: number;
    maxClockSkewMs: number;
    backupStrategy: 'continuous' | 'daily' | 'weekly';
    disasterRecoveryRTO: number; // minutes
    disasterRecoveryRPO: number; // minutes
  };
}

/**
 * 5-Region Federation Configuration
 * Spans US, Europe, and Asia-Pacific for global coverage
 */
export const FEDERATION_CONFIG: FederationConfig = {
  federationId: 'global-federation-2026',
  federationName: 'Global Code Server Federation',
  createdAt: new Date('2026-04-13'),
  regions: [
    // Region 1: US West (Primary)
    {
      regionId: 'us-west',
      regionName: 'US West - California',
      cloudProvider: 'gcp',
      projectId: 'code-server-us-west-prod',
      location: 'us-west1',
      kubernetesVersion: '1.28',
      nodeCount: 5,
      machineType: 'n2-standard-4',
      diskSizeGb: 200,
      network: {
        cidr: '10.0.0.0/20',
        pods: '10.4.0.0/14',
        services: '10.0.16.0/20',
      },
      database: {
        version: '15.1',
        backupRetentionDays: 30,
        computeNodes: 3,
      },
      tags: {
        environment: 'production',
        region: 'us-west',
        tier: 'primary',
        replica_id: 'us-west-primary',
      },
    },

    // Region 2: EU West (Secondary)
    {
      regionId: 'eu-west',
      regionName: 'EU West - Ireland',
      cloudProvider: 'gcp',
      projectId: 'code-server-eu-west-prod',
      location: 'eu-west1',
      kubernetesVersion: '1.28',
      nodeCount: 4,
      machineType: 'n2-standard-4',
      diskSizeGb: 200,
      network: {
        cidr: '10.16.0.0/20',
        pods: '10.20.0.0/14',
        services: '10.36.0.0/20',
      },
      database: {
        version: '15.1',
        backupRetentionDays: 30,
        computeNodes: 3,
      },
      tags: {
        environment: 'production',
        region: 'eu-west',
        tier: 'secondary',
        replica_id: 'eu-west-primary',
      },
    },

    // Region 3: EU Central
    {
      regionId: 'eu-central',
      regionName: 'EU Central - Germany',
      cloudProvider: 'gcp',
      projectId: 'code-server-eu-central-prod',
      location: 'europe-west1',
      kubernetesVersion: '1.28',
      nodeCount: 3,
      machineType: 'n1-standard-4',
      diskSizeGb: 150,
      network: {
        cidr: '10.32.0.0/20',
        pods: '10.40.0.0/14',
        services: '10.48.0.0/20',
      },
      database: {
        version: '15.1',
        backupRetentionDays: 30,
        computeNodes: 2,
      },
      tags: {
        environment: 'production',
        region: 'eu-central',
        tier: 'tertiary',
        replica_id: 'eu-central-primary',
      },
    },

    // Region 4: AP South (Asia-Pacific)
    {
      regionId: 'ap-south',
      regionName: 'AP South - Singapore',
      cloudProvider: 'gcp',
      projectId: 'code-server-ap-south-prod',
      location: 'asia-southeast1',
      kubernetesVersion: '1.28',
      nodeCount: 3,
      machineType: 'n1-standard-2',
      diskSizeGb: 150,
      network: {
        cidr: '10.64.0.0/20',
        pods: '10.68.0.0/14',
        services: '10.80.0.0/20',
      },
      database: {
        version: '15.1',
        backupRetentionDays: 30,
        computeNodes: 2,
      },
      tags: {
        environment: 'production',
        region: 'ap-south',
        tier: 'tertiary',
        replica_id: 'ap-south-primary',
      },
    },

    // Region 5: AP Northeast (Tokyo)
    {
      regionId: 'ap-northeast',
      regionName: 'AP Northeast - Japan',
      cloudProvider: 'gcp',
      projectId: 'code-server-ap-northeast-prod',
      location: 'asia-northeast1',
      kubernetesVersion: '1.28',
      nodeCount: 3,
      machineType: 'n1-standard-2',
      diskSizeGb: 150,
      network: {
        cidr: '10.96.0.0/20',
        pods: '10.100.0.0/14',
        services: '10.112.0.0/20',
      },
      database: {
        version: '15.1',
        backupRetentionDays: 30,
        computeNodes: 2,
      },
      tags: {
        environment: 'production',
        region: 'ap-northeast',
        tier: 'tertiary',
        replica_id: 'ap-northeast-primary',
      },
    },
  ],
  globalConfig: {
    replicationMode: 'multi-primary',
    conflictResolution: 'lww',
    syncIntervalMs: 1000,
    maxClockSkewMs: 5000,
    backupStrategy: 'continuous',
    disasterRecoveryRTO: 15, // 15 minutes max downtime
    disasterRecoveryRPO: 1, // 1 minute max data loss
  },
};

/**
 * Get region configuration by ID
 */
export function getRegionConfig(regionId: string): RegionConfig | undefined {
  return FEDERATION_CONFIG.regions.find(r => r.regionId === regionId);
}

/**
 * Get all replica IDs
 */
export function getReplicaIds(): string[] {
  return FEDERATION_CONFIG.regions.map(
    region => region.tags.replica_id as string
  );
}

/**
 * Get region by replica ID
 */
export function getRegionByReplicaId(replicaId: string): RegionConfig | undefined {
  return FEDERATION_CONFIG.regions.find(
    r => r.tags.replica_id === replicaId
  );
}

/**
 * Calculate inter-region latency estimates (ms)
 * Based on geographic distance and typical network latency
 */
export function getEstimatedLatency(
  fromRegion: string,
  toRegion: string
): number {
  const latencies: Record<string, Record<string, number>> = {
    'us-west': {
      'us-west': 1,
      'eu-west': 150,
      'eu-central': 160,
      'ap-south': 180,
      'ap-northeast': 120,
    },
    'eu-west': {
      'us-west': 150,
      'eu-west': 2,
      'eu-central': 20,
      'ap-south': 180,
      'ap-northeast': 200,
    },
    'eu-central': {
      'us-west': 160,
      'eu-west': 20,
      'eu-central': 2,
      'ap-south': 190,
      'ap-northeast': 210,
    },
    'ap-south': {
      'us-west': 180,
      'eu-west': 180,
      'eu-central': 190,
      'ap-south': 2,
      'ap-northeast': 45,
    },
    'ap-northeast': {
      'us-west': 120,
      'eu-west': 200,
      'eu-central': 210,
      'ap-south': 45,
      'ap-northeast': 2,
    },
  };

  return latencies[fromRegion]?.[toRegion] ?? 999;
}

/**
 * Validate federation configuration
 */
export function validateFederationConfig(): {
  isValid: boolean;
  errors: string[];
} {
  const errors: string[] = [];

  // Check minimum regions
  if (FEDERATION_CONFIG.regions.length < 3) {
    errors.push(
      `Minimum 3 regions required, found ${FEDERATION_CONFIG.regions.length}`
    );
  }

  // Check for duplicate region IDs
  const regionIds = FEDERATION_CONFIG.regions.map(r => r.regionId);
  if (new Set(regionIds).size !== regionIds.length) {
    errors.push('Duplicate region IDs detected');
  }

  // Check for duplicate replica IDs
  const replicaIds = FEDERATION_CONFIG.regions.map(
    r => r.tags.replica_id
  );
  if (new Set(replicaIds).size !== replicaIds.length) {
    errors.push('Duplicate replica IDs detected');
  }

  // Check CIDR blocks don't overlap (simplified check)
  const cidrs = FEDERATION_CONFIG.regions.map(r => r.network.cidr);
  for (let i = 0; i < cidrs.length; i++) {
    for (let j = i + 1; j < cidrs.length; j++) {
      // In production, use proper CIDR overlap detection
      if (cidrs[i].split('.')[1] === cidrs[j].split('.')[1]) {
        errors.push(
          `CIDR overlap detected: ${cidrs[i]} and ${cidrs[j]}`
        );
      }
    }
  }

  // Check database config
  if (FEDERATION_CONFIG.globalConfig.disasterRecoveryRTO < 5) {
    errors.push('RTO must be at least 5 minutes');
  }

  if (FEDERATION_CONFIG.globalConfig.disasterRecoveryRPO < 1) {
    errors.push('RPO must be at least 1 minute');
  }

  return {
    isValid: errors.length === 0,
    errors,
  };
}
