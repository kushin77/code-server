/**
 * @file        tests/oidc/kubernetes-serviceaccount.test.ts
 * @module      testing/oidc
 * @description Unit tests for Kubernetes ServiceAccount OIDC configuration
 */

import * as fs from 'fs';
import * as path from 'path';

describe('Kubernetes ServiceAccount OIDC Configuration', () => {
  const manifestPath = path.join(__dirname, '../../kubernetes/oidc-serviceaccounts.yaml');
  let manifestContent: string;

  beforeAll(() => {
    if (fs.existsSync(manifestPath)) {
      manifestContent = fs.readFileSync(manifestPath, 'utf-8');
    }
  });

  describe('ServiceAccount Definitions', () => {
    test('should have github-actions-ci ServiceAccount', () => {
      expect(manifestContent).toContain('name: github-actions-ci');
      expect(manifestContent).toContain('kind: ServiceAccount');
    });

    test('should have batch-processor ServiceAccount', () => {
      expect(manifestContent).toContain('name: batch-processor');
    });

    test('should have webhook-receiver ServiceAccount', () => {
      expect(manifestContent).toContain('name: webhook-receiver');
    });

    test('should have cluster-admin ServiceAccount', () => {
      expect(manifestContent).toContain('name: cluster-admin');
    });

    test('should include namespace labels', () => {
      expect(manifestContent).toContain('namespace:');
    });

    test('should include app labels', () => {
      expect(manifestContent).toContain('app:');
    });
  });

  describe('ClusterRole Definitions', () => {
    test('should define ClusterRole for GitHub Actions', () => {
      expect(manifestContent).toContain('name: code-server-github-actions');
      expect(manifestContent).toMatch(/kind:\s*ClusterRole/);
    });

    test('should define ClusterRole for Batch Processor', () => {
      expect(manifestContent).toContain('name: code-server-batch-processor');
    });

    test('should include RBAC rules for permissions', () => {
      expect(manifestContent).toContain('rules:');
      expect(manifestContent).toMatch(/apiGroups:|resources:|verbs:/);
    });

    test('should define necessary API groups', () => {
      expect(manifestContent).toMatch(/apiGroups:\s*\[\]/); // For core APIs
    });
  });

  describe('ClusterRoleBinding Definitions', () => {
    test('should define ClusterRoleBinding for GitHub Actions', () => {
      expect(manifestContent).toContain('name: github-actions-binding');
      expect(manifestContent).toMatch(/kind:\s*ClusterRoleBinding/);
    });

    test('should define ClusterRoleBinding for Batch Processor', () => {
      expect(manifestContent).toContain('name: batch-processor-binding');
    });

    test('should map ServiceAccounts to ClusterRoles', () => {
      expect(manifestContent).toContain('subjects:');
      expect(manifestContent).toContain('kind: ServiceAccount');
    });
  });

  describe('OIDC Token Projection', () => {
    test('should include token projection path', () => {
      expect(manifestContent).toContain('/var/run/secrets/tokens/oidc/token');
    });

    test('should specify projection audience', () => {
      expect(manifestContent).toContain('audience:');
      expect(manifestContent).toMatch(/kubernetes|code-server/);
    });

    test('should set token expiration TTL', () => {
      expect(manifestContent).toContain('expirationSeconds:');
      expect(manifestContent).toMatch(/\b3600\b|\b300\b/); // 1 hour or 5 minutes
    });

    test('should use volumeProjection mechanism', () => {
      expect(manifestContent).toContain('projected:');
      expect(manifestContent).toContain('serviceAccountToken:');
    });
  });

  describe('NetworkPolicy Configuration', () => {
    test('should include NetworkPolicy', () => {
      expect(manifestContent).toMatch(/kind:\s*NetworkPolicy/);
    });

    test('should restrict egress to OIDC issuer', () => {
      expect(manifestContent).toMatch(/port:\s*4182|oauth2-oidc-issuer/);
    });

    test('should define pod selector', () => {
      expect(manifestContent).toContain('podSelector:');
    });
  });

  describe('Security Context', () => {
    test('should define security context', () => {
      expect(manifestContent).toContain('securityContext:');
    });

    test('should run as non-root', () => {
      expect(manifestContent).toMatch(/runAsNonRoot:\s*true/);
    });

    test('should use read-only filesystem', () => {
      expect(manifestContent).toMatch(/readOnlyRootFilesystem:\s*true/);
    });
  });

  describe('Resource Limits', () => {
    test('should define resource requests', () => {
      expect(manifestContent).toContain('requests:');
    });

    test('should define resource limits', () => {
      expect(manifestContent).toContain('limits:');
    });

    test('should set CPU and memory limits', () => {
      expect(manifestContent).toMatch(/cpu:|memory:/);
    });
  });

  describe('Manifest Validation', () => {
    test('manifest file should exist', () => {
      expect(fs.existsSync(manifestPath)).toBe(true);
    });

    test('manifest should be valid YAML structure', () => {
      // Basic YAML validation - should contain expected delimiters
      expect(manifestContent).toMatch(/^---/); // YAML document start
      expect(manifestContent).toMatch(/kind:/); // Contains resource definitions
    });

    test('manifest should define at least 4 ServiceAccounts', () => {
      const saCount = (manifestContent.match(/kind: ServiceAccount/g) || []).length;
      expect(saCount).toBeGreaterThanOrEqual(4);
    });

    test('manifest should define at least 2 ClusterRoles', () => {
      const crCount = (manifestContent.match(/kind: ClusterRole/g) || []).length;
      expect(crCount).toBeGreaterThanOrEqual(2);
    });

    test('manifest should define at least 2 ClusterRoleBindings', () => {
      const crbCount = (manifestContent.match(/kind: ClusterRoleBinding/g) || []).length;
      expect(crbCount).toBeGreaterThanOrEqual(2);
    });
  });
});

describe('Token Exchange Script', () => {
  const scriptPath = path.join(__dirname, '../../kubernetes/token-exchange.sh');
  let scriptContent: string;

  beforeAll(() => {
    if (fs.existsSync(scriptPath)) {
      scriptContent = fs.readFileSync(scriptPath, 'utf-8');
    }
  });

  test('script should exist', () => {
    expect(fs.existsSync(scriptPath)).toBe(true);
  });

  test('script should have shebang', () => {
    expect(scriptContent).toMatch(/^#!/);
  });

  test('script should implement RFC 8693 token exchange', () => {
    expect(scriptContent).toContain('urn:ietf:params:oauth:grant-type:token-exchange');
  });

  test('script should handle subject_token parameter', () => {
    expect(scriptContent).toMatch(/subject_token|SUBJECT_TOKEN/);
  });

  test('script should specify audience', () => {
    expect(scriptContent).toMatch(/audience|AUDIENCE/);
  });

  test('script should include error handling', () => {
    expect(scriptContent).toMatch(/set -e|set -u|error|fail/i);
  });
});

describe('OIDC Workload Deployments', () => {
  const manifestPath = path.join(__dirname, '../../kubernetes/oidc-workload-deployments.yaml');
  let manifestContent: string;

  beforeAll(() => {
    if (fs.existsSync(manifestPath)) {
      manifestContent = fs.readFileSync(manifestPath, 'utf-8');
    }
  });

  test('manifest should exist', () => {
    expect(fs.existsSync(manifestPath)).toBe(true);
  });

  test('manifest should define github-actions-runner deployment', () => {
    expect(manifestContent).toContain('name: github-actions-runner');
    expect(manifestContent).toContain('kind: Deployment');
    expect(manifestContent).toContain('serviceAccountName: github-actions-ci');
  });

  test('manifest should define batch processor workload identity example', () => {
    expect(manifestContent).toContain('name: batch-processor-job');
    expect(manifestContent).toContain('serviceAccountName: batch-processor');
    expect(manifestContent).toContain('serviceAccountToken:');
  });

  test('manifest should include OIDC projection and security hardening', () => {
    expect(manifestContent).toContain('/var/run/secrets/tokens/oidc');
    expect(manifestContent).toMatch(/OIDC_ISSUER_URL|OIDC_AUDIENCE/);
    expect(manifestContent).toMatch(/runAsNonRoot:\s*true/);
    expect(manifestContent).toMatch(/readOnlyRootFilesystem:\s*true/);
  });
});

describe('API Client Example', () => {
  const scriptPath = path.join(__dirname, '../../kubernetes/api-client-example.sh');
  let scriptContent: string;

  beforeAll(() => {
    if (fs.existsSync(scriptPath)) {
      scriptContent = fs.readFileSync(scriptPath, 'utf-8');
    }
  });

  test('script should exist', () => {
    expect(fs.existsSync(scriptPath)).toBe(true);
  });

  test('script should implement token caching', () => {
    expect(scriptContent).toMatch(/cache|CACHE|TTL|expire/i);
  });

  test('script should include get_jwt_token function', () => {
    expect(scriptContent).toContain('get_jwt_token');
  });

  test('script should include call_api_with_jwt function', () => {
    expect(scriptContent).toContain('call_api_with_jwt');
  });

  test('script should handle Authorization header', () => {
    expect(scriptContent).toMatch(/Authorization|Bearer/);
  });
});

describe('Documentation', () => {
  const docPath = path.join(__dirname, '../../docs/KUBERNETES-OIDC-INTEGRATION.md');
  let docContent: string;

  beforeAll(() => {
    if (fs.existsSync(docPath)) {
      docContent = fs.readFileSync(docPath, 'utf-8');
    }
  });

  test('documentation should exist', () => {
    expect(fs.existsSync(docPath)).toBe(true);
  });

  test('documentation should explain architecture', () => {
    expect(docContent).toMatch(/architecture|token.*flow|issuer/i);
  });

  test('documentation should include deployment steps', () => {
    expect(docContent).toMatch(/deploy|install|apply|kubectl/i);
  });

  test('documentation should include troubleshooting', () => {
    expect(docContent).toMatch(/troubleshoot|error|problem|solution/i);
  });

  test('documentation should cover security', () => {
    expect(docContent).toMatch(/security|tls|secret|encrypt/i);
  });

  test('documentation should include examples', () => {
    expect(docContent).toMatch(/example|```/);
  });
});
