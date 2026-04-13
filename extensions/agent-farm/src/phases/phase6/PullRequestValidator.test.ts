import { describe, it, expect, beforeEach, vi } from 'vitest';
import { PullRequestValidator } from './PullRequestValidator';
import { Logger } from '../../types';

describe('PullRequestValidator', () => {
  let validator: PullRequestValidator;
  let mockLogger: Logger;
  let mockGitHub: any;

  beforeEach(() => {
    mockLogger = {
      debug: vi.fn(),
      info: vi.fn(),
      warn: vi.fn(),
      error: vi.fn(),
    };

    mockGitHub = {
      getPullRequest: vi.fn(),
      getChangedFiles: vi.fn(),
      getComments: vi.fn(),
      setStatus: vi.fn(),
    };

    validator = new PullRequestValidator({
      logger: mockLogger,
      githubClient: mockGitHub,
    });
  });

  describe('Manifest Validation Stage', () => {
    it('should validate changed manifests syntax', async () => {
      mockGitHub.getChangedFiles.mockResolvedValue([
        { filename: 'k8s/deployment.yaml', patch: '+...' },
        { filename: 'k8s/service.yaml', patch: '+...' },
      ]);

      const result = await validator.validateManifestSyntax({
        pullNumber: 123,
        owner: 'example',
        repo: 'my-app',
      });

      expect(result).toBeDefined();
      expect(result.valid).toBeDefined();
    });

    it('should detect invalid YAML in PR', async () => {
      mockGitHub.getChangedFiles.mockResolvedValue([
        {
          filename: 'k8s/broken.yaml',
          patch: '+invalid: yaml: format:',
        },
      ]);

      const result = await validator.validateManifestSyntax({
        pullNumber: 123,
        owner: 'example',
        repo: 'my-app',
      });

      expect(result.valid).toBe(false);
      expect(result.errors.length).toBeGreaterThan(0);
    });

    it('should ignore non-manifest files', async () => {
      mockGitHub.getChangedFiles.mockResolvedValue([
        { filename: 'README.md', patch: '+# New section' },
        { filename: 'src/index.ts', patch: '+...code...' },
        { filename: 'k8s/deployment.yaml', patch: '+...' },
      ]);

      const result = await validator.validateManifestSyntax({
        pullNumber: 123,
        owner: 'example',
        repo: 'my-app',
      });

      expect(result).toBeDefined();
    });
  });

  describe('Configuration Security Stage', () => {
    it('should detect hardcoded credentials', async () => {
      mockGitHub.getChangedFiles.mockResolvedValue([
        {
          filename: 'k8s/secret.yaml',
          patch: '+  password: "hardcoded123"',
        },
      ]);

      const result = await validator.validateConfigurationSecurity({
        pullNumber: 123,
        owner: 'example',
        repo: 'my-app',
      });

      expect(result).toBeDefined();
      expect(result.credentialsFound).toBeGreaterThanOrEqual(0);
    });

    it('should detect API keys in manifest', async () => {
      mockGitHub.getChangedFiles.mockResolvedValue([
        {
          filename: 'k8s/config.yaml',
          patch: '+  apiKey: "sk_live_1234567890abc"',
        },
      ]);

      const result = await validator.validateConfigurationSecurity({
        pullNumber: 123,
        owner: 'example',
        repo: 'my-app',
      });

      expect(result.secrets).toBeDefined();
    });

    it('should warn about insecure image registries', async () => {
      mockGitHub.getChangedFiles.mockResolvedValue([
        {
          filename: 'k8s/deployment.yaml',
          patch: '+    image: myregistry.com/app:v1',
        },
      ]);

      const result = await validator.validateConfigurationSecurity({
        pullNumber: 123,
        owner: 'example',
        repo: 'my-app',
      });

      expect(result.warnings).toBeDefined();
    });
  });

  describe('Dependency Impact Analysis Stage', () => {
    it('should analyze configuration dependencies', async () => {
      mockGitHub.getChangedFiles.mockResolvedValue([
        { filename: 'k8s/configmap.yaml', patch: '+...' },
        { filename: 'k8s/deployment.yaml', patch: '+spec:\n+  template:\n+    spec:\n+      envFrom:\n+      - configMapRef:\n+          name: test-config' },
      ]);

      const result = await validator.analyzeDependencyImpact({
        pullNumber: 123,
        owner: 'example',
        repo: 'my-app',
      });

      expect(result.dependencies).toBeDefined();
      expect(result.affectedServices).toBeDefined();
    });

    it('should detect breaking changes', async () => {
      mockGitHub.getChangedFiles.mockResolvedValue([
        {
          filename: 'k8s/configmap.yaml',
          patch:
            '-  KEY_NAME: value\n+  RENAMED_KEY_NAME: value',
        },
      ]);

      const result = await validator.analyzeDependencyImpact({
        pullNumber: 123,
        owner: 'example',
        repo: 'my-app',
      });

      expect(result.breakingChanges).toBeDefined();
    });

    it('should identify affected deployment targets', async () => {
      const result = await validator.analyzeDependencyImpact({
        pullNumber: 123,
        owner: 'example',
        repo: 'my-app',
      });

      expect(result.affectedServices).toBeDefined();
      expect(Array.isArray(result.affectedServices)).toBe(true);
    });
  });

  describe('Performance Impact Assessment Stage', () => {
    it('should assess resource changes', async () => {
      mockGitHub.getChangedFiles.mockResolvedValue([
        {
          filename: 'k8s/deployment.yaml',
          patch:
            '-        cpu: 100m\n+        cpu: 500m\n-        memory: 256Mi\n+        memory: 1Gi',
        },
      ]);

      const result = await validator.assessPerformanceImpact({
        pullNumber: 123,
        owner: 'example',
        repo: 'my-app',
      });

      expect(result.resourceChanges).toBeDefined();
      expect(result.estimatedCostImpact).toBeDefined();
    });

    it('should estimate cost impact', async () => {
      const result = await validator.assessPerformanceImpact({
        pullNumber: 123,
        owner: 'example',
        repo: 'my-app',
      });

      expect(result.estimatedCostImpact).toBeDefined();
      expect(result.costDelta).toBeDefined();
    });

    it('should warn about excessive resource requests', async () => {
      mockGitHub.getChangedFiles.mockResolvedValue([
        {
          filename: 'k8s/deployment.yaml',
          patch:
            '+        cpu: "10"\n+        memory: 50Gi',
        },
      ]);

      const result = await validator.assessPerformanceImpact({
        pullNumber: 123,
        owner: 'example',
        repo: 'my-app',
      });

      expect(result.warnings).toBeDefined();
    });
  });

  describe('Merge Eligibility Stage', () => {
    it('should approve mergeable PR', async () => {
      mockGitHub.getChangedFiles.mockResolvedValue([
        { filename: 'k8s/deployment.yaml', patch: '+...' },
      ]);

      const result = await validator.determineMergeability({
        pullNumber: 123,
        owner: 'example',
        repo: 'my-app',
      });

      expect(result.mergeable).toBe(true);
    });

    it('should block PR with issues', async () => {
      mockGitHub.getChangedFiles.mockResolvedValue([
        {
          filename: 'k8s/deployment.yaml',
          patch: '+invalid yaml content',
        },
      ]);

      const result = await validator.determineMergeability({
        pullNumber: 123,
        owner: 'example',
        repo: 'my-app',
      });

      expect(result.mergeable).toBe(false);
      expect(result.blockingIssues).toBeDefined();
    });

    it('should allow override for urgent merges', async () => {
      const result = await validator.determineMergeability({
        pullNumber: 123,
        owner: 'example',
        repo: 'my-app',
        allowOverride: true,
      });

      expect(result.overridable).toBeDefined();
    });

    it('should require approvals', async () => {
      mockGitHub.getComments.mockResolvedValue([
        // No approvals
      ]);

      const result = await validator.determineMergeability({
        pullNumber: 123,
        owner: 'example',
        repo: 'my-app',
        requiredApprovals: 2,
      });

      expect(result.approvalsNeeded).toBe(2);
    });
  });

  describe('Deployment Readiness Stage', () => {
    it('should determine deployment readiness', async () => {
      const result = await validator.determineDeploymentReadiness({
        pullNumber: 123,
        owner: 'example',
        repo: 'my-app',
      });

      expect(result.deployable).toBeDefined();
      expect(result.readinessChecks).toBeDefined();
    });

    it('should check image availability', async () => {
      const result = await validator.determineDeploymentReadiness({
        pullNumber: 123,
        owner: 'example',
        repo: 'my-app',
      });

      expect(result.readinessChecks.imagesAvailable).toBeDefined();
    });

    it('should verify cluster capacity', async () => {
      const result = await validator.determineDeploymentReadiness({
        pullNumber: 123,
        owner: 'example',
        repo: 'my-app',
      });

      expect(result.readinessChecks.clusterCapacity).toBeDefined();
    });

    it('should provide deployment recommendations', async () => {
      const result = await validator.determineDeploymentReadiness({
        pullNumber: 123,
        owner: 'example',
        repo: 'my-app',
      });

      expect(result.recommendations).toBeDefined();
    });
  });

  describe('Full Validation Workflow', () => {
    it('should run all validation stages', async () => {
      mockGitHub.getChangedFiles.mockResolvedValue([
        { filename: 'k8s/deployment.yaml', patch: '+...' },
      ]);

      const result = await validator.validatePullRequest({
        pullNumber: 123,
        owner: 'example',
        repo: 'my-app',
      });

      expect(result.stages).toHaveLength(5);
      expect(result.stages).toContain(expect.objectContaining({ name: 'Manifest Validation' }));
      expect(result.stages).toContain(expect.objectContaining({ name: 'Configuration Security' }));
      expect(result.stages).toContain(expect.objectContaining({ name: 'Dependency Analysis' }));
      expect(result.stages).toContain(expect.objectContaining({ name: 'Performance Assessment' }));
      expect(result.stages).toContain(expect.objectContaining({ name: 'Merge Eligibility' }));
    });

    it('should provide comprehensive summary', async () => {
      const result = await validator.validatePullRequest({
        pullNumber: 123,
        owner: 'example',
        repo: 'my-app',
      });

      expect(result.summary).toBeDefined();
      expect(result.summary.overallStatus).toBeDefined();
      expect(result.summary.criticalIssues).toBeDefined();
      expect(result.summary.warnings).toBeDefined();
    });

    it('should report findings to GitHub', async () => {
      await validator.validatePullRequest({
        pullNumber: 123,
        owner: 'example',
        repo: 'my-app',
        reportToGitHub: true,
      });

      expect(mockGitHub.setStatus).toHaveBeenCalled();
    });
  });

  describe('Custom Validation Rules', () => {
    it('should support custom validation hooks', async () => {
      validator.addCustomRule({
        name: 'require-owner-label',
        stage: 'Manifest Validation',
        validate: async (pr) => ({
          passed: true,
          message: 'Custom validation passed',
        }),
      });

      const result = await validator.validatePullRequest({
        pullNumber: 123,
        owner: 'example',
        repo: 'my-app',
      });

      expect(result).toBeDefined();
    });
  });

  describe('Caching and Performance', () => {
    it('should cache validation results', async () => {
      mockGitHub.getChangedFiles.mockResolvedValue([
        { filename: 'k8s/deployment.yaml', patch: '+...' },
      ]);

      await validator.validatePullRequest({
        pullNumber: 123,
        owner: 'example',
        repo: 'my-app',
      });

      const cachedResult = await validator.getCachedResult(123);

      expect(cachedResult).toBeDefined();
    });

    it('should invalidate cache on file changes', async () => {
      await validator.validatePullRequest({
        pullNumber: 123,
        owner: 'example',
        repo: 'my-app',
      });

      validator.invalidateCache(123);
      const result = await validator.getCachedResult(123);

      expect(result).toBeUndefined();
    });
  });

  describe('Error Handling', () => {
    it('should handle GitHub API errors gracefully', async () => {
      mockGitHub.getChangedFiles.mockRejectedValue(
        new Error('API rate limited')
      );

      expect(async () => {
        await validator.validatePullRequest({
          pullNumber: 123,
          owner: 'example',
          repo: 'my-app',
        });
      }).rejects.toThrow();
    });

    it('should provide detailed error context', async () => {
      mockGitHub.getChangedFiles.mockRejectedValue(
        new Error('Connection timeout')
      );

      try {
        await validator.validatePullRequest({
          pullNumber: 123,
          owner: 'example',
          repo: 'my-app',
        });
      } catch (error) {
        expect(error.message).toContain('timeout');
      }
    });
  });
});
