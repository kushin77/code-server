import { describe, it, expect, beforeEach } from 'vitest';
import { ManifestValidator } from './ManifestValidator';
import { Logger } from '../../types';

describe('ManifestValidator', () => {
  let validator: ManifestValidator;
  let mockLogger: Logger;

  beforeEach(() => {
    mockLogger = {
      debug: vi.fn(),
      info: vi.fn(),
      warn: vi.fn(),
      error: vi.fn(),
    };

    validator = new ManifestValidator({
      logger: mockLogger,
      strictMode: false,
    });
  });

  describe('Basic Validation', () => {
    it('should validate basic Kubernetes manifest structure', async () => {
      const manifest = {
        apiVersion: 'apps/v1',
        kind: 'Deployment',
        metadata: {
          name: 'test-app',
          namespace: 'default',
        },
        spec: {
          replicas: 3,
        },
      };

      const result = await validator.validate(manifest);
      expect(result.valid).toBe(true);
    });

    it('should reject manifest without apiVersion', async () => {
      const manifest = {
        kind: 'Deployment',
        metadata: { name: 'test-app' },
      };

      const result = await validator.validate(manifest);
      expect(result.valid).toBe(false);
      expect(result.errors).toContain(expect.stringContaining('apiVersion'));
    });

    it('should reject manifest without kind', async () => {
      const manifest = {
        apiVersion: 'apps/v1',
        metadata: { name: 'test-app' },
      };

      const result = await validator.validate(manifest);
      expect(result.valid).toBe(false);
      expect(result.errors).toContain(expect.stringContaining('kind'));
    });
  });

  describe('Security Context Validation', () => {
    it('should enforce non-root execution', async () => {
      const manifest = {
        apiVersion: 'v1',
        kind: 'Pod',
        spec: {
          containers: [
            {
              name: 'app',
              image: 'myapp:v1',
              securityContext: {
                runAsNonRoot: true,
                runAsUser: 1000,
              },
            },
          ],
        },
      };

      const result = await validator.validate(manifest);
      expect(result.errors).not.toContain(
        expect.stringContaining('runAsNonRoot')
      );
    });

    it('should warn about root execution', async () => {
      const manifest = {
        apiVersion: 'v1',
        kind: 'Pod',
        spec: {
          containers: [
            {
              name: 'app',
              image: 'myapp:v1',
              securityContext: {
                runAsUser: 0,
              },
            },
          ],
        },
      };

      const result = await validator.validate(manifest);
      expect(result.warnings).toContain(
        expect.stringContaining('root')
      );
    });

    it('should enforce read-only filesystem', async () => {
      const manifest = {
        apiVersion: 'v1',
        kind: 'Pod',
        spec: {
          containers: [
            {
              name: 'app',
              image: 'myapp:v1',
              securityContext: {
                readOnlyRootFilesystem: true,
              },
            },
          ],
        },
      };

      const result = await validator.validate(manifest);
      expect(result.valid).toBe(true);
    });
  });

  describe('Resource Limits Validation', () => {
    it('should require resource limits', async () => {
      const manifest = {
        apiVersion: 'v1',
        kind: 'Pod',
        spec: {
          containers: [
            {
              name: 'app',
              image: 'myapp:v1',
              resources: {
                limits: {
                  cpu: '500m',
                  memory: '512Mi',
                },
              },
            },
          ],
        },
      };

      const result = await validator.validate(manifest);
      expect(result.valid).toBe(true);
    });

    it('should warn about missing resource limits', async () => {
      const manifest = {
        apiVersion: 'v1',
        kind: 'Pod',
        spec: {
          containers: [
            {
              name: 'app',
              image: 'myapp:v1',
            },
          ],
        },
      };

      const result = await validator.validate(manifest);
      expect(result.warnings.length).toBeGreaterThan(0);
    });
  });

  describe('Health Probe Validation', () => {
    it('should validate liveness probe', async () => {
      const manifest = {
        apiVersion: 'v1',
        kind: 'Pod',
        spec: {
          containers: [
            {
              name: 'app',
              image: 'myapp:v1',
              livenessProbe: {
                httpGet: {
                  path: '/health',
                  port: 8080,
                },
                initialDelaySeconds: 10,
                periodSeconds: 10,
              },
            },
          ],
        },
      };

      const result = await validator.validate(manifest);
      expect(result.valid).toBe(true);
    });

    it('should validate readiness probe', async () => {
      const manifest = {
        apiVersion: 'v1',
        kind: 'Pod',
        spec: {
          containers: [
            {
              name: 'app',
              image: 'myapp:v1',
              readinessProbe: {
                httpGet: {
                  path: '/ready',
                  port: 8080,
                },
              },
            },
          ],
        },
      };

      const result = await validator.validate(manifest);
      expect(result.valid).toBe(true);
    });

    it('should warn about missing probes', async () => {
      const manifest = {
        apiVersion: 'v1',
        kind: 'Deployment',
        spec: {
          template: {
            spec: {
              containers: [
                {
                  name: 'app',
                  image: 'myapp:v1',
                },
              ],
            },
          },
        },
      };

      const result = await validator.validate(manifest);
      expect(result.warnings).toContain(
        expect.stringContaining('probe')
      );
    });
  });

  describe('Dependency Analysis', () => {
    it('should detect circular dependencies', async () => {
      const manifests = [
        {
          apiVersion: 'v1',
          kind: 'ConfigMap',
          metadata: { name: 'config-a' },
          data: { dependency: 'config-b' },
        },
        {
          apiVersion: 'v1',
          kind: 'ConfigMap',
          metadata: { name: 'config-b' },
          data: { dependency: 'config-a' },
        },
      ];

      const result = await validator.analyzeDependencies(manifests);
      expect(result.hasCycles).toBe(true);
      expect(result.cycles.length).toBeGreaterThan(0);
    });

    it('should validate dependency order', async () => {
      const manifests = [
        {
          apiVersion: 'v1',
          kind: 'Service',
          metadata: { name: 'svc-a' },
        },
        {
          apiVersion: 'apps/v1',
          kind: 'Deployment',
          metadata: { name: 'deploy-a' },
          spec: {
            selector: { app: 'app-a' },
            template: {
              metadata: { labels: { app: 'app-a' } },
            },
          },
        },
      ];

      const result = await validator.analyzeDependencies(manifests);
      expect(result.ordered).toBeDefined();
    });
  });

  describe('Custom Rules', () => {
    it('should support custom validation rules', async () => {
      validator.addCustomRule({
        name: 'require-owner-label',
        validate: (manifest) => {
          const owner = manifest.metadata?.labels?.owner;
          return {
            valid: !!owner,
            message: owner ? '' : 'Missing owner label',
          };
        },
      });

      const manifest = {
        apiVersion: 'v1',
        kind: 'Pod',
        metadata: {
          labels: { owner: 'team-a' },
        },
      };

      const result = await validator.validate(manifest);
      expect(result.valid).toBe(true);
    });

    it('should apply all custom rules', async () => {
      validator.addCustomRule({
        name: 'require-namespace',
        validate: (manifest) => ({
          valid: !!manifest.metadata?.namespace,
          message: manifest.metadata?.namespace ? '' : 'Missing namespace',
        }),
      });

      const manifest = {
        apiVersion: 'v1',
        kind: 'Pod',
        metadata: { name: 'test' }, // Missing namespace
      };

      const result = await validator.validate(manifest);
      expect(result.errors).toContain(
        expect.stringContaining('namespace')
      );
    });
  });

  describe('YAML Parsing', () => {
    it('should parse valid YAML', async () => {
      const yaml = `
apiVersion: v1
kind: Pod
metadata:
  name: test-pod
spec:
  containers:
  - name: app
    image: myapp:v1
      `;

      const result = await validator.parseYaml(yaml);
      expect(result.valid).toBe(true);
      expect(result.manifest).toBeDefined();
    });

    it('should reject invalid YAML', async () => {
      const yaml = `
apiVersion: v1
kind: Pod
metadata:
  name: test-pod
  invalid: [
  spec:
      `;

      const result = await validator.parseYaml(yaml);
      expect(result.valid).toBe(false);
      expect(result.errors).toBeDefined();
    });
  });

  describe('Recommendations', () => {
    it('should provide actionable recommendations', async () => {
      const manifest = {
        apiVersion: 'v1',
        kind: 'Pod',
        spec: {
          containers: [
            {
              name: 'app',
              image: 'myapp:latest', // Bad: using latest tag
            },
          ],
        },
      };

      const result = await validator.validate(manifest);
      expect(result.recommendations).toContain(
        expect.stringContaining('image')
      );
    });

    it('should suggest security improvements', async () => {
      const manifest = {
        apiVersion: 'v1',
        kind: 'Pod',
        spec: {
          containers: [
            {
              name: 'app',
              image: 'myapp:v1',
            },
          ],
        },
      };

      const result = await validator.validate(manifest);
      expect(result.recommendations.length).toBeGreaterThan(0);
    });
  });

  describe('Performance', () => {
    it('should validate manifests quickly', async () => {
      const manifest = {
        apiVersion: 'apps/v1',
        kind: 'Deployment',
        metadata: { name: 'test' },
        spec: {
          replicas: 3,
          selector: { matchLabels: { app: 'test' } },
          template: {
            metadata: { labels: { app: 'test' } },
            spec: {
              containers: [
                {
                  name: 'app',
                  image: 'myapp:v1',
                },
              ],
            },
          },
        },
      };

      const start = Date.now();
      const result = await validator.validate(manifest);
      const duration = Date.now() - start;

      expect(duration).toBeLessThan(500); // SLA: < 500ms
      expect(result).toBeDefined();
    });
  });

  describe('Batch Processing', () => {
    it('should validate multiple manifests', async () => {
      const manifests = Array.from({ length: 10 }).map((_, i) => ({
        apiVersion: 'v1',
        kind: 'Pod',
        metadata: { name: `pod-${i}` },
      }));

      const results = await validator.validateBatch(manifests);
      expect(results.length).toBe(10);
      expect(results.every((r) => r.valid !== undefined)).toBe(true);
    });
  });
});
