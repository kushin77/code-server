"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.ApplicationSetManagerImpl = exports.ApplicationSetManager = void 0;
const events_1 = require("events");
class ApplicationSetManager extends events_1.EventEmitter {
    constructor() {
        super();
        this.appSets = new Map();
        this.generatedApps = new Map();
        this.clusterRegistry = new Map();
    }
}
exports.ApplicationSetManager = ApplicationSetManager;
/**
 * ApplicationSet Manager - manages declarative multi-app deployments
 */
class ApplicationSetManagerImpl extends ApplicationSetManager {
    /**
     * Register cluster for ApplicationSet generation
     */
    registerCluster(cluster) {
        if (this.clusterRegistry.has(cluster.name)) {
            throw new Error(`Cluster ${cluster.name} already registered`);
        }
        this.clusterRegistry.set(cluster.name, cluster);
        this.emit('cluster-registered', { clusterName: cluster.name, timestamp: new Date() });
        console.log(`[ApplicationSet] Registered cluster: ${cluster.name} at ${cluster.server}`);
    }
    /**
     * Create ApplicationSet
     */
    createApplicationSet(template) {
        const name = template.metadata.name;
        if (this.appSets.has(name)) {
            throw new Error(`ApplicationSet ${name} already exists`);
        }
        this.validateApplicationSetTemplate(template);
        this.appSets.set(name, template);
        this.emit('appset-created', { appsetName: name, timestamp: new Date() });
        console.log(`[ApplicationSet] Created ApplicationSet: ${name}`);
    }
    /**
     * Validate ApplicationSet template
     */
    validateApplicationSetTemplate(template) {
        const errors = [];
        if (!template.metadata?.name) {
            errors.push('ApplicationSet name is required');
        }
        if (!template.spec?.generators || template.spec.generators.length === 0) {
            errors.push('At least one generator is required');
        }
        if (!template.spec?.template) {
            errors.push('Template specification is required');
        }
        if (errors.length > 0) {
            throw new Error(`Invalid ApplicationSet template: ${errors.join(', ')}`);
        }
    }
    /**
     * Generate applications from ApplicationSet
     */
    async generateApplications(appsetName) {
        const appset = this.appSets.get(appsetName);
        if (!appset) {
            throw new Error(`ApplicationSet ${appsetName} not found`);
        }
        const targets = [];
        // Process each generator
        for (const generator of appset.spec.generators) {
            console.log(`[ApplicationSet] Processing generator: ${generator.type}`);
            switch (generator.type) {
                case 'cluster':
                    targets.push(...this.generateFromClusterSelector(generator));
                    break;
                case 'list':
                    targets.push(...this.generateFromList(generator));
                    break;
                case 'git':
                    targets.push(...(await this.generateFromGit(generator)));
                    break;
                case 'matrix':
                    targets.push(...this.generateFromMatrix(generator));
                    break;
            }
        }
        // Store generated applications
        this.generatedApps.set(appsetName, targets);
        const result = {
            appsetName,
            generatedCount: targets.length,
            targets,
            timestamp: new Date()
        };
        this.emit('applications-generated', result);
        console.log(`[ApplicationSet] Generated ${targets.length} applications from ${appsetName}`);
        return result;
    }
    /**
     * Generate apps from cluster selector
     */
    generateFromClusterSelector(generator) {
        const targets = [];
        const selector = generator.selector || {};
        for (const [clusterName, cluster] of this.clusterRegistry) {
            // Match cluster labels
            let matches = true;
            for (const [key, value] of Object.entries(selector)) {
                if (cluster.labels?.[key] !== value) {
                    matches = false;
                    break;
                }
            }
            if (matches) {
                targets.push({
                    appName: `app-${clusterName}`,
                    cluster: clusterName,
                    namespace: 'default',
                    repoUrl: 'https://github.com/kushin77/code-server',
                    targetRevision: 'main',
                    path: 'kustomize/overlays/production'
                });
            }
        }
        return targets;
    }
    /**
     * Generate apps from static list
     */
    generateFromList(generator) {
        const targets = [];
        // Example list generator
        const items = [
            {
                cluster: 'staging',
                namespace: 'staging',
                path: 'kustomize/overlays/staging'
            },
            {
                cluster: 'production',
                namespace: 'production',
                path: 'kustomize/overlays/production'
            }
        ];
        for (const item of items) {
            targets.push({
                appName: `app-${item.cluster}`,
                cluster: item.cluster,
                namespace: item.namespace,
                repoUrl: 'https://github.com/kushin77/code-server',
                targetRevision: 'main',
                path: item.path
            });
        }
        return targets;
    }
    /**
     * Generate apps from Git directories
     */
    async generateFromGit(generator) {
        // In real implementation, would scan Git repo for directories
        // and create apps for each directory
        console.log('[ApplicationSet] Git generator scanning repository');
        return [];
    }
    /**
     * Generate apps from matrix (cross-product)
     */
    generateFromMatrix(generator) {
        const targets = [];
        // Example: create app for each cluster × environment combination
        const clusters = ['us-east', 'eu-west', 'ap-south'];
        const environments = ['staging', 'production'];
        for (const cluster of clusters) {
            for (const env of environments) {
                targets.push({
                    appName: `app-${cluster}-${env}`,
                    cluster,
                    namespace: env,
                    repoUrl: 'https://github.com/kushin77/code-server',
                    targetRevision: 'main',
                    path: `kustomize/overlays/${env}`
                });
            }
        }
        return targets;
    }
    /**
     * Get generated applications
     */
    getGeneratedApplications(appsetName) {
        return this.generatedApps.get(appsetName);
    }
    /**
     * Update ApplicationSet
     */
    updateApplicationSet(appsetName, template) {
        const existing = this.appSets.get(appsetName);
        if (!existing) {
            throw new Error(`ApplicationSet ${appsetName} not found`);
        }
        this.validateApplicationSetTemplate(template);
        this.appSets.set(appsetName, template);
        // Regenerate applications
        this.generatedApps.delete(appsetName);
        this.emit('appset-updated', { appsetName, timestamp: new Date() });
        console.log(`[ApplicationSet] Updated ApplicationSet: ${appsetName}`);
    }
    /**
     * Delete ApplicationSet
     */
    deleteApplicationSet(appsetName) {
        this.appSets.delete(appsetName);
        this.generatedApps.delete(appsetName);
        this.emit('appset-deleted', { appsetName, timestamp: new Date() });
        console.log(`[ApplicationSet] Deleted ApplicationSet: ${appsetName}`);
    }
    /**
     * List all ApplicationSets
     */
    listApplicationSets() {
        return Array.from(this.appSets.values());
    }
    /**
     * List registered clusters
     */
    listClusters() {
        return Array.from(this.clusterRegistry.values());
    }
}
exports.ApplicationSetManagerImpl = ApplicationSetManagerImpl;
exports.default = ApplicationSetManagerImpl;
//# sourceMappingURL=applicationset-manager.js.map