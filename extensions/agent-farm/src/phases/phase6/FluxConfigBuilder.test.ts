import { describe, it, expect, beforeEach } from 'vitest';
import { FluxConfigBuilder } from './FluxConfigBuilder';
import { Logger } from '../../types';

describe('FluxConfigBuilder', () => {
  let builder: FluxConfigBuilder;
  let mockLogger: Logger;

  beforeEach(() => {
    mockLogger = {
      debug: vi.fn(),
      info: vi.fn(),
      warn: vi.fn(),
      error: vi.fn(),
    };

    builder = new FluxConfigBuilder({
      logger: mockLogger,
    });
  });

  describe('Basic Configuration', () => {
    it('should create basic Flux configuration', async () => {
      const config = builder
        .withRepository('https://github.com/example/config.git')
        .withBranch('main')
        .withInterval('5m')
        .build();

      expect(config).toBeDefined();
      expect(config.apiVersion).toBe('source.toolkit.fluxcd.io/v1beta2');
    });

    it('should set repository URL', () => {
      builder.withRepository('https://github.com/example/config.git');
      expect(builder.getRepositoryUrl()).toBe('https://github.com/example/config.git');
    });

    it('should set branch', () => {
      builder.withBranch('main');
      expect(builder.getBranch()).toBe('main');
    });

    it('should set reconciliation interval', () => {
      builder.withInterval('10m');
      expect(builder.getInterval()).toBe('10m');
    });
  });

  describe('Authentication', () => {
    it('should support SSH authentication', async () => {
      const config = builder
        .withRepository('git@github.com:example/config.git')
        .withSSHKey({
          publicKey: 'ssh-rsa AAAA...',
          privateKey: '-----BEGIN OPENSSH PRIVATE KEY-----...',
        })
        .build();

      expect(config.spec.secretRef).toBeDefined();
      expect(config.spec.secretRef.name).toContain('ssh');
    });

    it('should support HTTPS token authentication', async () => {
      const config = builder
        .withRepository('https://github.com/example/config.git')
        .withHTTPSToken('ghp_1234567890abcdef')
        .build();

      expect(config.spec.secretRef).toBeDefined();
    });

    it('should support basic auth', async () => {
      const config = builder
        .withRepository('https://github.com/example/config.git')
        .withBasicAuth('username', 'password')
        .build();

      expect(config.spec.secretRef).toBeDefined();
    });
  });

  describe('Kustomization Configuration', () => {
    it('should generate Kustomization resource', async () => {
      const kustomization = builder
        .withRepository('https://github.com/example/config.git')
        .withBranch('main')
        .withPath('./kubernetes')
        .withKustomization()
        .build();

      expect(kustomization.spec.sourceRef.kind).toBe('GitRepository');
      expect(kustomization.spec.path).toBe('./kubernetes');
    });

    it('should support Kustomization with patches', () => {
      builder
        .withKustomization()
        .addPatch({
          target: {
            group: 'apps',
            version: 'v1',
            kind: 'Deployment',
            name: 'app',
          },
          patch: 'spec:\n  replicas: 3',
        });

      const config = builder.build();
      expect(config.spec.patches).toBeDefined();
    });

    it('should configure prune behavior', () => {
      builder
        .withKustomization()
        .withPruning(true);

      const config = builder.build();
      expect(config.spec.prune).toBe(true);
    });

    it('should configure health checks', () => {
      builder
        .withKustomization()
        .addHealthCheck({
          apiVersion: 'apps/v1',
          kind: 'Deployment',
          name: 'app-deployment',
        });

      const config = builder.build();
      expect(config.spec.healthChecks).toBeDefined();
    });
  });

  describe('Helm Configuration', () => {
    it('should generate Helm release', async () => {
      const helmRelease = builder
        .withHelmRepository('https://charts.example.com')
        .withChart('my-app')
        .withVersion('1.2.3')
        .withNamespace('default')
        .withValues({
          replicaCount: 3,
          image: {
            repository: 'myapp',
            tag: 'v1.2.3',
          },
        })
        .buildHelmConfig();

      expect(helmRelease.apiVersion).toBe('helm.toolkit.fluxcd.io/v2beta2');
      expect(helmRelease.spec.chart.spec.chart).toBe('my-app');
    });

    it('should configure Helm values', () => {
      const values = {
        replicaCount: 5,
        resources: {
          limits: { cpu: '500m', memory: '512Mi' },
        },
      };

      builder.withValues(values);
      expect(builder.getValues()).toEqual(values);
    });

    it('should support Helm post-renderers', () => {
      builder
        .withHelmRepository('https://charts.example.com')
        .withPostRenderer('kustomize')
        .addPostRenderPatch({
          apiVersion: 'apps/v1',
          kind: 'Deployment',
          patch: 'spec:\n  replicas: 3',
        });

      const config = builder.buildHelmConfig();
      expect(config.spec.postRenderers).toBeDefined();
    });
  });

  describe('Multi-Region Configuration', () => {
    it('should generate config for multiple regions', async () => {
      const regions = ['us-east-1', 'eu-west-1', 'ap-southeast-1'];

      for (const region of regions) {
        builder.addRegion(region, {
          repository: `https://github.com/example/config-${region}.git`,
          branch: 'main',
          path: './kubernetes',
        });
      }

      const configs = builder.buildMultiRegion();
      expect(configs.length).toBe(3);
    });

    it('should support region-specific overrides', () => {
      builder
        .addRegion('us-east-1', {
          repository: 'https://github.com/example/config.git',
          branch: 'main',
        })
        .addRegionOverride('us-east-1', {
          interval: '1m',
          priority: 1,
        });

      const configs = builder.buildMultiRegion();
      expect(configs[0].spec.interval).toBe('1m');
    });
  });

  describe('Secrets Management', () => {
    it('should integrate with SOPS for secrets', () => {
      builder
        .withRepository('https://github.com/example/config.git')
        .withSecretsEncryption('sops')
        .withKMSKey('arn:aws:kms:us-east-1:123456789:key/abc123');

      const config = builder.build();
      expect(config.spec.secretRef).toBeDefined();
    });

    it('should support sealed secrets', () => {
      builder
        .withRepository('https://github.com/example/config.git')
        .withSecretsEncryption('sealed-secrets')
        .withSealedSecretsKey('default');

      const config = builder.build();
      expect(config).toBeDefined();
    });

    it('should exclude secrets from Git', () => {
      builder
        .withKustomization()
        .excludeFromGit(['**/secrets/**', '**/*-secret.yaml']);

      const config = builder.build();
      expect(config.spec.ignore).toBeDefined();
    });
  });

  describe('Notification Configuration', () => {
    it('should configure alerts', () => {
      builder
        .addAlert({
          provider: 'slack',
          address: 'https://hooks.slack.com/services/...',
          events: ['sync', 'error'],
        })
        .addAlert({
          provider: 'webhook',
          address: 'https://example.com/webhook',
        });

      const config = builder.build();
      expect(config.spec.serviceAccount).toBeDefined();
    });

    it('should support multiple notification channels', () => {
      const alerts = [
        { provider: 'slack', address: 'https://...' },
        { provider: 'opsgenie', address: 'https://...' },
        { provider: 'teams', address: 'https://...' },
      ];

      alerts.forEach((alert) => builder.addAlert(alert));

      const config = builder.build();
      expect(config.spec.serviceAccount).toBeDefined();
    });
  });

  describe('Validation and Dependencies', () => {
    it('should validate dependencies before build', () => {
      builder
        .withKustomization()
        .addDependency('flux-system');

      const config = builder.build();
      expect(config.spec.dependsOn).toBeDefined();
    });

    it('should support wait-for-ready dependencies', () => {
      builder
        .withKustomization()
        .addDependency('flux-system', { waitForReady: true });

      const config = builder.build();
      expect(config.spec.dependsOn).toBeDefined();
    });
  });

  describe('YAML Generation', () => {
    it('should generate valid YAML output', async () => {
      const yaml = builder
        .withRepository('https://github.com/example/config.git')
        .withBranch('main')
        .toYAML();

      expect(yaml).toContain('apiVersion');
      expect(yaml).toContain('kind');
      expect(yaml).toContain('metadata');
    });

    it('should support multi-document YAML', async () => {
      const yaml = builder
        .addRegion('us-east-1', { repository: 'https://...' })
        .addRegion('eu-west-1', { repository: 'https://...' })
        .toYAML({ multiDocument: true });

      expect(yaml.split('---').length).toBeGreaterThan(1);
    });
  });

  describe('Fluent API', () => {
    it('should support fluent API chaining', () => {
      const config = builder
        .withRepository('https://github.com/example/config.git')
        .withBranch('main')
        .withInterval('5m')
        .withKustomization()
        .withPruning(true)
        .build();

      expect(config).toBeDefined();
      expect(config.spec.interval).toBe('5m');
    });

    it('should return builder from all chain methods', () => {
      expect(builder.withRepository('...')).toBe(builder);
      expect(builder.withBranch('main')).toBe(builder);
      expect(builder.withInterval('5m')).toBe(builder);
    });
  });

  describe('Performance', () => {
    it('should generate config quickly', () => {
      const start = Date.now();

      for (let i = 0; i < 100; i++) {
        const config = new FluxConfigBuilder({
          logger: mockLogger,
        })
          .withRepository(`https://github.com/example/config-${i}.git`)
          .withBranch('main')
          .build();
      }

      const duration = Date.now() - start;
      expect(duration).toBeLessThan(1000); // SLA: < 1s for 100 configs
    });

    it('should handle large values efficiently', () => {
      const largeValues = Object.fromEntries(
        Array.from({ length: 1000 }).map((_, i) => [`key-${i}`, `value-${i}`])
      );

      const start = Date.now();
      builder.withValues(largeValues);
      const config = builder.buildHelmConfig();
      const duration = Date.now() - start;

      expect(duration).toBeLessThan(500); // SLA: < 500ms
      expect(config).toBeDefined();
    });
  });

  describe('Error Handling', () => {
    it('should validate required fields before build', () => {
      expect(() => {
        new FluxConfigBuilder({ logger: mockLogger }).build();
      }).toThrow();
    });

    it('should provide helpful error messages', () => {
      expect(() => {
        new FluxConfigBuilder({ logger: mockLogger })
          .withRepository('invalid-url')
          .build();
      }).toThrow();
    });
  });
});
