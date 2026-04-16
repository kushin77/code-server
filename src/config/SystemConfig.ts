/**
 * UNIFIED CONFIGURATION LOADER
 * Single source of truth for all runtime configuration
 * Loads from: environment → config files → defaults
 * 
 * PRODUCTION-FIRST: All configuration is externalized and validated
 * No hardcoded values. All parameters come from:
 *   1. Environment variables (CI/CD, container orchestration)
 *   2. Config files (config/ directory)
 *   3. Defaults (sensible values)
 */

export interface PostgresConfig {
  host: string;
  port: number;
  database: string;
  user: string;
  password: string;
  poolSize: number;
  idleTimeout: number;
  sslMode?: 'require' | 'prefer' | 'disable';
}

export interface RedisConfig {
  host: string;
  port: number;
  password: string;
  db: number;
  ttl: number;
  retryStrategy?: (times: number) => number;
}

export interface FeatureFlags {
  gpuEnabled: boolean;
  multiRegionEnabled: boolean;
  oauth2Enabled: boolean;
  auditLoggingEnabled: boolean;
  performanceOptimization: boolean;
  chaosTesting: boolean;
}

export interface SLOConfig {
  availabilityTarget: number; // 99.99
  p99LatencyTarget: number; // 100ms
  errorRateTarget: number; // 0.1%
  alertThresholds: {
    availability: number;
    latency: number;
    errorRate: number;
  };
}

export interface LoadTestConfig {
  durationMs: number;
  startRps: number;
  peakRps: number;
  rampUpMs: number;
  steadyStateMs: number;
  rampDownMs: number;
  payloadSize: number;
  connectionPoolSize: number;
  requestTimeoutMs: number;
}

export interface SystemConfig {
  // Deployment
  deployHost: string;
  deployUser: string;
  deployEnv: 'development' | 'staging' | 'production';
  domain: string;
  acmeEmail: string;

  // Database
  postgres: PostgresConfig;

  // Cache
  redis: RedisConfig;

  // Features
  features: FeatureFlags;

  // SLO & Monitoring
  slo: SLOConfig;

  // Load Testing
  loadTest: LoadTestConfig;

  // Container Orchestration
  containerDefaults: {
    logging: {
      driver: string;
      options: {
        maxSize: string;
        maxFile: number;
      };
    };
    stopTimeout: number; // seconds
    healthcheck: {
      interval: number; // seconds
      timeout: number;
      retries: number;
      startPeriod: number;
    };
  };
}

/**
 * ConfigLoader — Singleton pattern for configuration management
 * Loads configuration in override hierarchy:
 * 1. Defaults (built-in)
 * 2. Environment variables
 * 3. Can be overridden programmatically
 */
export class ConfigLoader {
  private static instance: ConfigLoader;
  private config: SystemConfig;
  private loadedAt: Date;

  private constructor() {
    this.config = this.loadConfiguration();
    this.loadedAt = new Date();
  }

  /**
   * Get singleton instance
   */
  static getInstance(): ConfigLoader {
    if (!ConfigLoader.instance) {
      ConfigLoader.instance = new ConfigLoader();
    }
    return ConfigLoader.instance;
  }

  /**
   * Load configuration from environment and defaults
   */
  private loadConfiguration(): SystemConfig {
    return {
      // ═══════════════════════════════════════════════════════════
      // DEPLOYMENT
      // ═══════════════════════════════════════════════════════════
      deployHost: process.env.DEPLOY_HOST || '192.168.168.31',
      deployUser: process.env.DEPLOY_USER || 'akushnir',
      deployEnv: (process.env.DEPLOY_ENV || 'production') as any,
      domain: process.env.DOMAIN || 'ide.kushnir.cloud',
      acmeEmail: process.env.ACME_EMAIL || 'ops@kushnir.cloud',

      // ═══════════════════════════════════════════════════════════
      // DATABASE
      // ═══════════════════════════════════════════════════════════
      postgres: {
        host: process.env.POSTGRES_HOST || 'localhost',
        port: parseInt(process.env.POSTGRES_PORT || '5432', 10),
        database: process.env.POSTGRES_DB || 'codeserver',
        user: process.env.POSTGRES_USER || 'codeserver',
        password: process.env.POSTGRES_PASSWORD || '',
        poolSize: parseInt(process.env.POSTGRES_POOL_SIZE || '10', 10),
        idleTimeout: parseInt(process.env.POSTGRES_IDLE_TIMEOUT || '30000', 10),
        sslMode: (process.env.POSTGRES_SSL_MODE || 'prefer') as any,
      },

      // ═══════════════════════════════════════════════════════════
      // CACHE
      // ═══════════════════════════════════════════════════════════
      redis: {
        host: process.env.REDIS_HOST || 'localhost',
        port: parseInt(process.env.REDIS_PORT || '6379', 10),
        password: process.env.REDIS_PASSWORD || '',
        db: parseInt(process.env.REDIS_DB || '0', 10),
        ttl: parseInt(process.env.REDIS_TTL || '86400', 10),
      },

      // ═══════════════════════════════════════════════════════════
      // FEATURE FLAGS
      // ═══════════════════════════════════════════════════════════
      features: {
        gpuEnabled: process.env.FEATURE_GPU_ENABLED !== 'false',
        multiRegionEnabled: process.env.FEATURE_MULTI_REGION !== 'false',
        oauth2Enabled: process.env.FEATURE_OAUTH2 !== 'false',
        auditLoggingEnabled: process.env.FEATURE_AUDIT_LOGGING !== 'false',
        performanceOptimization: process.env.FEATURE_PERFORMANCE_OPTIMIZATION !== 'false',
        chaosTesting: process.env.FEATURE_CHAOS_TESTING === 'true',
      },

      // ═══════════════════════════════════════════════════════════
      // SLO & MONITORING
      // ═══════════════════════════════════════════════════════════
      slo: {
        availabilityTarget: parseFloat(process.env.SLO_AVAILABILITY_TARGET || '99.99'),
        p99LatencyTarget: parseInt(process.env.SLO_P99_LATENCY_TARGET || '100', 10),
        errorRateTarget: parseFloat(process.env.SLO_ERROR_RATE_TARGET || '0.1'),
        alertThresholds: {
          availability: parseFloat(process.env.SLO_ALERT_THRESHOLD_AVAILABILITY || '99.95'),
          latency: parseInt(process.env.SLO_ALERT_THRESHOLD_LATENCY || '150', 10),
          errorRate: parseFloat(process.env.SLO_ALERT_THRESHOLD_ERROR_RATE || '1'),
        },
      },

      // ═══════════════════════════════════════════════════════════
      // LOAD TESTING
      // ═══════════════════════════════════════════════════════════
      loadTest: {
        durationMs: parseInt(process.env.LOAD_TEST_DURATION_MS || '600000', 10),
        startRps: parseInt(process.env.LOAD_TEST_START_RPS || '100', 10),
        peakRps: parseInt(process.env.LOAD_TEST_PEAK_RPS || '1000', 10),
        rampUpMs: parseInt(process.env.LOAD_TEST_RAMP_UP_MS || '60000', 10),
        steadyStateMs: parseInt(process.env.LOAD_TEST_STEADY_STATE_MS || '300000', 10),
        rampDownMs: parseInt(process.env.LOAD_TEST_RAMP_DOWN_MS || '60000', 10),
        payloadSize: parseInt(process.env.LOAD_TEST_PAYLOAD_SIZE || '1024', 10),
        connectionPoolSize: parseInt(process.env.LOAD_TEST_CONNECTION_POOL_SIZE || '100', 10),
        requestTimeoutMs: parseInt(process.env.LOAD_TEST_REQUEST_TIMEOUT_MS || '30000', 10),
      },

      // ═══════════════════════════════════════════════════════════
      // CONTAINER ORCHESTRATION DEFAULTS
      // ═══════════════════════════════════════════════════════════
      containerDefaults: {
        logging: {
          driver: process.env.DOCKER_LOGGING_DRIVER || 'json-file',
          options: {
            maxSize: process.env.DOCKER_LOGGING_MAX_SIZE || '10m',
            maxFile: parseInt(process.env.DOCKER_LOGGING_MAX_FILE || '5', 10),
          },
        },
        stopTimeout: parseInt(process.env.DOCKER_STOP_TIMEOUT || '30', 10),
        healthcheck: {
          interval: parseInt(process.env.HEALTHCHECK_INTERVAL || '30', 10),
          timeout: parseInt(process.env.HEALTHCHECK_TIMEOUT || '10', 10),
          retries: parseInt(process.env.HEALTHCHECK_RETRIES || '3', 10),
          startPeriod: parseInt(process.env.HEALTHCHECK_START_PERIOD || '40', 10),
        },
      },
    };
  }

  /**
   * Get the full configuration object
   */
  getConfig(): Readonly<SystemConfig> {
    return Object.freeze(this.config);
  }

  /**
   * Get a specific configuration section
   */
  getSection<K extends keyof SystemConfig>(section: K): Readonly<SystemConfig[K]> {
    return Object.freeze(this.config[section]);
  }

  /**
   * Merge custom config overrides (for testing)
   */
  withOverrides(overrides: Partial<SystemConfig>): SystemConfig {
    return {
      ...this.config,
      ...overrides,
      postgres: { ...this.config.postgres, ...overrides.postgres },
      redis: { ...this.config.redis, ...overrides.redis },
      features: { ...this.config.features, ...overrides.features },
      slo: { ...this.config.slo, ...overrides.slo },
      loadTest: { ...this.config.loadTest, ...overrides.loadTest },
      containerDefaults: { ...this.config.containerDefaults, ...overrides.containerDefaults },
    };
  }

  /**
   * Get configuration load time (for metrics)
   */
  getLoadedAt(): Date {
    return this.loadedAt;
  }

  /**
   * Validate configuration (check required values)
   */
  validate(): { valid: boolean; errors: string[] } {
    const errors: string[] = [];

    if (!this.config.postgres.password && this.config.deployEnv === 'production') {
      errors.push('POSTGRES_PASSWORD is required in production');
    }

    if (!this.config.redis.password && this.config.deployEnv === 'production') {
      errors.push('REDIS_PASSWORD is required in production');
    }

    if (this.config.deployEnv === 'production' && this.config.deployHost === 'localhost') {
      errors.push('DEPLOY_HOST must not be localhost in production');
    }

    return {
      valid: errors.length === 0,
      errors,
    };
  }
}

/**
 * Export singleton instance
 */
export const config: Readonly<SystemConfig> = ConfigLoader.getInstance().getConfig();

/**
 * Helper: Create configuration for testing with specific overrides
 */
export function createTestConfig(overrides: Partial<SystemConfig> = {}): SystemConfig {
  return ConfigLoader.getInstance().withOverrides(overrides);
}
