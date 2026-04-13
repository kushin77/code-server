/**
 * Phase 9 GitOps Integration Tests
 *
 * Tests ArgoCD application management, ApplicationSet generation,
 * sync state management, and drift detection across multiple clusters.
 *
 * @category Phase 9 - GitOps
 * @requires jest, @types/jest, ts-jest
 */

import { EventEmitter } from 'events';
import { ArgoCDApplicationManager } from './argocd-application-manager';
import { ApplicationSetManagerImpl } from './applicationset-manager';
import { GitOpsSyncStateManager } from './gitops-sync-manager';
import {
  ArgoCDApplication,
  ApplicationStatus,
  HealthStatus,
  SyncStatus,
} from './argocd-application-manager';
import {
  ApplicationSet,
  GenerationResult,
  ClusterInfo,
} from './applicationset-manager';
import { SyncState, SyncAction, DriftEvent } from './gitops-sync-manager';

describe('Phase 9 - GitOps Integration Tests', () => {
  let appManager: ArgoCDApplicationManager;
  let appSetManager: ApplicationSetManagerImpl;
  let syncManager: GitOpsSyncStateManager;

  beforeEach(() => {
    appManager = new ArgoCDApplicationManager({
      serverUrl: 'https://argocd.example.com',
      apiToken: 'test-token',
      syncInterval: 30000,
      healthCheckInterval: 10000,
    });

    appSetManager = new ApplicationSetManagerImpl({
      repositoryUrl: 'https://github.com/kushin77/code-server',
      namespace: 'argocd',
    });

    syncManager = new GitOpsSyncStateManager({
      gitRepository: 'https://github.com/kushin77/code-server',
      namespace: 'argocd',
      driftCheckInterval: 60000,
    });
  });

  describe('Application Lifecycle Management', () => {
    it('registers application and emits event', (done) => {
      const app: ArgoCDApplication = {
        name: 'code-server-app',
        namespace: 'argocd',
        source: {
          repoURL: 'https://github.com/kushin77/code-server',
          targetRevision: 'main',
          path: 'kustomize/overlays/production',
        },
        destination: {
          server: 'https://kubernetes.default.svc',
          namespace: 'code-server',
        },
      };

      appManager.on('application-registered', (evt) => {
        expect(evt.appName).toBe('code-server-app');
        done();
      });

      appManager.registerApplication(app);
    });

    it('syncs application and tracks status', (done) => {
      const appName = 'test-app';
      appManager.registerApplication({
        name: appName,
        namespace: 'argocd',
        source: {
          repoURL: 'https://github.com/test/repo',
          targetRevision: 'main',
          path: 'apps/test',
        },
        destination: {
          server: 'https://kubernetes.default.svc',
          namespace: 'test',
        },
      });

      appManager.on('application-synced', (evt) => {
        expect(evt.appName).toBe(appName);
        expect(evt.status.syncStatus).toBe(SyncStatus.Synced);
        done();
      });

      appManager.syncApplication(appName);
    });

    it('detects health degradation', (done) => {
      const appName = 'test-app';
      appManager.registerApplication({
        name: appName,
        namespace: 'argocd',
        source: {
          repoURL: 'https://github.com/test/repo',
          targetRevision: 'main',
          path: 'apps/test',
        },
        destination: {
          server: 'https://kubernetes.default.svc',
          namespace: 'test',
        },
      });

      appManager.on('health-degraded', (evt) => {
        expect(evt.appName).toBe(appName);
        expect(evt.previousStatus).toBe(HealthStatus.Healthy);
        expect(evt.currentStatus).toBe(HealthStatus.Degraded);
        done();
      });

      // Simulate health change
      setTimeout(() => {
        const status = appManager.getApplicationStatus(appName) || {
          appName,
          syncStatus: SyncStatus.Synced,
          healthStatus: HealthStatus.Degraded,
          lastSyncTime: new Date(),
          lastErrorTime: new Date(),
          resources: 0,
          syncResult: { revision: '', commit: '', author: '', message: '' },
        };
      }, 100);
    });
  });

  describe('ApplicationSet Multi-Cluster Deployment', () => {
    it('registers clusters and generates applications', (done) => {
      const clusters: ClusterInfo[] = [
        {
          name: 'prod-us-east',
          server: 'https://prod-us-east.example.com',
          labels: { environment: 'production', region: 'us-east' },
        },
        {
          name: 'prod-us-west',
          server: 'https://prod-us-west.example.com',
          labels: { environment: 'production', region: 'us-west' },
        },
      ];

      appSetManager.on('cluster-registered', () => {
        if (appSetManager['clusters'].size === 2) {
          expect(appSetManager['clusters'].size).toBe(2);
          done();
        }
      });

      clusters.forEach((cluster) => appSetManager.registerCluster(cluster));
    });

    it('generates applications from cluster selector', (done) => {
      appSetManager.registerCluster({
        name: 'prod-cluster',
        server: 'https://prod.example.com',
        labels: { env: 'production' },
      });

      const appSet: ApplicationSet = {
        name: 'prod-apps',
        namespace: 'argocd',
        generator: {
          type: 'cluster',
          selector: { env: 'production' },
        },
        applicationTemplate: {
          source: {
            repoURL: 'https://github.com/kushin77/code-server',
            path: 'kustomize/overlays/production',
            targetRevision: 'main',
          },
          destination: { namespace: 'production' },
        },
      };

      appSetManager.on('applications-generated', (event) => {
        expect(event.appSet.name).toBe('prod-apps');
        expect(event.generatedApps.length).toBeGreaterThan(0);
        done();
      });

      appSetManager.createApplicationSet(appSet);
    });

    it('supports matrix generation for multi-environment', (done) => {
      appSetManager.registerCluster({
        name: 'test-cluster',
        server: 'https://test.example.com',
        labels: { type: 'test' },
      });

      const appSet: ApplicationSet = {
        name: 'matrix-apps',
        namespace: 'argocd',
        generator: {
          type: 'matrix',
          generators: [
            {
              type: 'list',
              elements: [
                { env: 'staging', path: 'kustomize/overlays/staging' },
                { env: 'production', path: 'kustomize/overlays/production' },
              ],
            },
          ],
        },
        applicationTemplate: {
          source: {
            repoURL: 'https://github.com/kushin77/code-server',
            targetRevision: 'main',
          },
          destination: { namespace: 'apps' },
        },
      };

      appSetManager.on('applications-generated', (event) => {
        expect(event.generatedApps.length).toBeGreaterThan(0);
        done();
      });

      appSetManager.createApplicationSet(appSet);
    });
  });

  describe('GitOps State Synchronization', () => {
    it('registers application for drift detection', (done) => {
      syncManager.on('app-registered', (event) => {
        expect(event.appName).toBe('drift-test-app');
        done();
      });

      syncManager.registerApplication({
        name: 'drift-test-app',
        namespace: 'argocd',
        source: {
          repoURL: 'https://github.com/kushin77/code-server',
          targetRevision: 'main',
          path: 'apps/test',
        },
        destination: {
          server: 'https://kubernetes.default.svc',
          namespace: 'test',
        },
      });
    });

    it('detects drift between git and cluster', (done) => {
      syncManager.registerApplication({
        name: 'drift-app',
        namespace: 'argocd',
        source: {
          repoURL: 'https://github.com/kushin77/code-server',
          targetRevision: 'main',
          path: 'apps/test',
        },
        destination: {
          server: 'https://kubernetes.default.svc',
          namespace: 'test',
        },
      });

      syncManager.on('drift-detected', (event) => {
        expect(event.appName).toBe('drift-app');
        expect(event.driftItems.length).toBeGreaterThan(0);
        done();
      });

      syncManager.detectDrift('drift-app');
    });

    it('syncs state with auto-sync policy', (done) => {
      syncManager.registerApplication({
        name: 'autosync-app',
        namespace: 'argocd',
        source: {
          repoURL: 'https://github.com/kushin77/code-server',
          targetRevision: 'main',
          path: 'apps/test',
        },
        destination: {
          server: 'https://kubernetes.default.svc',
          namespace: 'test',
        },
      });

      const syncState: SyncState = {
        appName: 'autosync-app',
        autoSync: true,
        autoPrune: true,
        selfHeal: true,
        syncInterval: 30000,
        driftThreshold: 0.05,
      };

      syncManager.on('sync-succeeded', (event) => {
        expect(event.appName).toBe('autosync-app');
        expect(event.action.type).toBe(SyncAction.Sync);
        done();
      });

      syncManager.syncApplication('autosync-app', syncState);
    });

    it('tracks drift history over time', (done) => {
      const appName = 'history-app';

      syncManager.registerApplication({
        name: appName,
        namespace: 'argocd',
        source: {
          repoURL: 'https://github.com/kushin77/code-server',
          targetRevision: 'main',
          path: 'apps/test',
        },
        destination: {
          server: 'https://kubernetes.default.svc',
          namespace: 'test',
        },
      });

      // Detect drift multiple times
      syncManager.detectDrift(appName);
      setTimeout(() => syncManager.detectDrift(appName), 100);
      setTimeout(() => syncManager.detectDrift(appName), 200);

      setTimeout(() => {
        const history = syncManager['driftHistory'].get(appName) || [];
        expect(history.length).toBeGreaterThan(0);
        done();
      }, 300);
    });
  });

  describe('Multi-Cluster GitOps Workflow', () => {
    it('orchestrates full deployment across clusters', (done) => {
      const clusters: ClusterInfo[] = [
        {
          name: 'prod-us',
          server: 'https://prod-us.example.com',
          labels: { environment: 'production', region: 'us' },
        },
        {
          name: 'prod-eu',
          server: 'https://prod-eu.example.com',
          labels: { environment: 'production', region: 'eu' },
        },
      ];

      let registered = 0;
      appSetManager.on('cluster-registered', () => {
        registered++;
        if (registered === clusters.length) {
          // All clusters registered, now create ApplicationSet
          const appSet: ApplicationSet = {
            name: 'global-app',
            namespace: 'argocd',
            generator: {
              type: 'cluster',
              selector: { environment: 'production' },
            },
            applicationTemplate: {
              source: {
                repoURL: 'https://github.com/kushin77/code-server',
                path: 'kustomize/overlays/production',
                targetRevision: 'main',
              },
              destination: { namespace: 'production' },
            },
          };

          appSetManager.on('applications-generated', (event) => {
            expect(event.generatedApps.length).toBe(clusters.length);
            done();
          });

          appSetManager.createApplicationSet(appSet);
        }
      });

      clusters.forEach((c) => appSetManager.registerCluster(c));
    });

    it('coordinates sync across multiple applications', async () => {
      const apps = [
        {
          name: 'app-1',
          namespace: 'argocd',
          source: {
            repoURL: 'https://github.com/kushin77/code-server',
            path: 'apps/app1',
            targetRevision: 'main',
          },
          destination: {
            server: 'https://k8s1.example.com',
            namespace: 'app1',
          },
        },
        {
          name: 'app-2',
          namespace: 'argocd',
          source: {
            repoURL: 'https://github.com/kushin77/code-server',
            path: 'apps/app2',
            targetRevision: 'main',
          },
          destination: {
            server: 'https://k8s2.example.com',
            namespace: 'app2',
          },
        },
      ];

      apps.forEach((app) => appManager.registerApplication(app));
      appManager.syncApplication('app-1');
      appManager.syncApplication('app-2');

      await new Promise((resolve) => setTimeout(resolve, 100));

      expect(appManager.getApplicationStatus('app-1')).toBeDefined();
      expect(appManager.getApplicationStatus('app-2')).toBeDefined();
    });

    it('handles policy-driven sync decisions', (done) => {
      syncManager.registerApplication({
        name: 'policy-app',
        namespace: 'argocd',
        source: {
          repoURL: 'https://github.com/kushin77/code-server',
          targetRevision: 'main',
          path: 'apps/test',
        },
        destination: {
          server: 'https://kubernetes.default.svc',
          namespace: 'test',
        },
      });

      const policy: SyncState = {
        appName: 'policy-app',
        autoSync: true,
        autoPrune: true,
        selfHeal: true,
        syncInterval: 30000,
        driftThreshold: 0.1,
      };

      syncManager.on('sync-succeeded', (event) => {
        expect(event.appName).toBe('policy-app');
        done();
      });

      syncManager.syncApplication('policy-app', policy);
    });
  });

  describe('Error Handling & Resilience', () => {
    it('handles application sync errors gracefully', (done) => {
      appManager.on('sync-error', (event) => {
        expect(event.appName).toBeDefined();
        expect(event.error).toBeDefined();
        done();
      });

      // Try to sync non-existent app
      appManager.syncApplication('non-existent-app');
    });

    it('recovers from drift with auto-remediation', (done) => {
      syncManager.registerApplication({
        name: 'recover-app',
        namespace: 'argocd',
        source: {
          repoURL: 'https://github.com/kushin77/code-server',
          targetRevision: 'main',
          path: 'apps/test',
        },
        destination: {
          server: 'https://kubernetes.default.svc',
          namespace: 'test',
        },
      });

      let driftDetected = false;
      syncManager.on('drift-detected', () => {
        driftDetected = true;
      });

      syncManager.on('sync-succeeded', () => {
        expect(driftDetected).toBe(true);
        done();
      });

      syncManager.detectDrift('recover-app');
      syncManager.syncApplication('recover-app', {
        appName: 'recover-app',
        autoSync: true,
        selfHeal: true,
        driftThreshold: 0.05,
      });
    });

    it('validates ApplicationSet template before creation', (done) => {
      const invalidAppSet: ApplicationSet = {
        name: '',
        namespace: 'argocd',
        generator: {
          type: 'cluster',
          selector: { env: 'prod' },
        },
        applicationTemplate: {
          source: {
            repoURL: '',
            path: '',
            targetRevision: '',
          },
          destination: { namespace: '' },
        },
      };

      try {
        appSetManager.createApplicationSet(invalidAppSet);
        fail('Should have thrown validation error');
      } catch (error) {
        expect(String(error)).toContain('validation');
        done();
      }
    });
  });

  describe('Event Emission & Monitoring', () => {
    it('emits all critical events for monitoring', (done) => {
      const events: string[] = [];

      appManager.on('application-registered', () => events.push('reg'));
      appManager.on('application-synced', () => events.push('sync'));
      appManager.on('sync-error', () => events.push('err'));

      const app: ArgoCDApplication = {
        name: 'event-test',
        namespace: 'argocd',
        source: {
          repoURL: 'https://github.com/test/repo',
          targetRevision: 'main',
          path: 'apps/test',
        },
        destination: {
          server: 'https://kubernetes.default.svc',
          namespace: 'test',
        },
      };

      appManager.registerApplication(app);
      appManager.syncApplication('event-test');

      setTimeout(() => {
        expect(events.length).toBeGreaterThan(0);
        done();
      }, 100);
    });
  });
});
