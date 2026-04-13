"use strict";
/**
 * Phase 5: Knowledge Graph Integration
 * ArchitectureDiscovery - Automatically discover code architecture and layers
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.ArchitectureDiscovery = void 0;
/**
 * Discover and analyze code architecture
 */
class ArchitectureDiscovery {
    /**
     * Detect overall architecture pattern
     */
    detectArchitecturePattern(fileStructure) {
        const layers = this.identifyLayers(fileStructure);
        const violations = this.findLayerViolations(layers);
        const pattern = this.classifyArchitecture(layers);
        const recommendations = this.generateRecommendations(pattern, violations);
        return {
            name: pattern.name,
            type: pattern.type,
            confidence: pattern.confidence,
            layers,
            violations,
            recommendations,
        };
    }
    /**
     * Identify architectural layers
     */
    identifyLayers(fileStructure) {
        const layers = [];
        // Common layer patterns
        const layerPatterns = [
            { name: 'Presentation', paths: ['web', 'ui', 'views', 'components', 'pages'] },
            { name: 'API', paths: ['api', 'routes', 'controllers', 'endpoints'] },
            { name: 'Service', paths: ['services', 'business', 'logic', 'handlers', 'processors'] },
            { name: 'Data Access', paths: ['data', 'repositories', 'models', 'persistence', 'db'] },
            { name: 'Infrastructure', paths: ['config', 'utils', 'helpers', 'lib', 'tools'] },
        ];
        layerPatterns.forEach((pattern) => {
            const matchingFiles = this.findFilesByPattern(fileStructure, pattern.paths);
            if (matchingFiles.length > 0) {
                layers.push({
                    name: pattern.name,
                    description: `${pattern.name} layer containing ${matchingFiles.length} files`,
                    components: matchingFiles,
                    dependencies: new Map(),
                    complexity: this.calculateLayerComplexity(matchingFiles),
                    responsibilities: this.inferResponsibilities(pattern.name),
                    metrics: {
                        fileCount: matchingFiles.length,
                        classCount: this.countClasses(matchingFiles),
                        functionCount: this.countFunctions(matchingFiles),
                        averageComplexity: 0,
                        testCoverage: 0,
                    },
                });
            }
        });
        return layers;
    }
    /**
     * Find layer violations (invalid dependencies between layers)
     */
    findLayerViolations(layers) {
        const violations = [];
        // Define valid layer ordering (dependencies should flow downward)
        const layerOrder = ['Presentation', 'API', 'Service', 'Data Access', 'Infrastructure'];
        layers.forEach((fromLayer, fromIndex) => {
            layers.forEach((toLayer, toIndex) => {
                // Layer should not depend on higher layers
                if (fromIndex < toIndex && fromLayer.dependencies.has(toLayer.name)) {
                    violations.push({
                        type: 'layer-crossing',
                        severity: 'high',
                        from: fromLayer.name,
                        to: toLayer.name,
                        description: `${fromLayer.name} layer has unexpected dependency on lower ${toLayer.name} layer`,
                    });
                }
                // Detect skip-layer dependencies (should depend on adjacent layers)
                if (Math.abs(fromIndex - toIndex) > 1 && fromLayer.dependencies.has(toLayer.name)) {
                    violations.push({
                        type: 'skip-layer',
                        severity: 'medium',
                        from: fromLayer.name,
                        to: toLayer.name,
                        description: `${fromLayer.name} skips intermediate layer to depend on ${toLayer.name}`,
                    });
                }
            });
        });
        return violations;
    }
    /**
     * Define component boundaries
     */
    defineComponentBoundaries(fileStructure) {
        const boundaries = [];
        // Find component directories (typical structure: src/components/*/index.ts)
        const components = this.findComponentDirs(fileStructure);
        components.forEach((compPath) => {
            const compName = compPath.split('/').pop() || 'unknown';
            const exports = this.extractPublicAPI(compPath);
            const dependencies = this.findComponentDependencies(compPath);
            boundaries.push({
                name: compName,
                path: compPath,
                exports,
                internalAPIs: this.countInternalAPIs(compPath),
                externalAPIs: exports.length,
                dependencies,
            });
        });
        return boundaries;
    }
    /**
     * Detect coupling between components
     */
    detectDependencyCoupling(boundaries) {
        let totalDependencies = 0;
        let cyclicDependencies = 0;
        const couplingScores = new Map();
        boundaries.forEach((boundary) => {
            let couplingScore = 0;
            boundary.dependencies.forEach((count) => {
                totalDependencies += count;
                couplingScore += count;
            });
            couplingScores.set(boundary.name, couplingScore / boundary.dependencies.size);
        });
        // Detect cyclic dependencies
        const visited = new Set();
        boundaries.forEach((boundary) => {
            if (!visited.has(boundary.name)) {
                if (this.hasCyclicDependency(boundary, boundaries, visited)) {
                    cyclicDependencies++;
                }
            }
        });
        const avgCoupling = totalDependencies / Math.max(boundaries.length, 1);
        return {
            averageCoupling: avgCoupling,
            maxCoupling: Math.max(...Array.from(couplingScores.values())),
            minCoupling: Math.min(...Array.from(couplingScores.values())),
            cyclicDependencies,
            couplingByComponent: couplingScores,
        };
    }
    /**
     * Verify architectural consistency
     */
    verifyArchitecturalConsistency(arch) {
        const issues = [];
        // Check for layer violations
        arch.violations.forEach((violation) => {
            if (violation.severity === 'high' || violation.severity === 'critical') {
                issues.push({
                    type: violation.type,
                    severity: violation.severity,
                    component1: violation.from,
                    component2: violation.to,
                    description: violation.description,
                });
            }
        });
        // Check for naming consistency
        arch.layers.forEach((layer) => {
            layer.components.forEach((comp) => {
                if (!this.followsNamingConvention(comp, layer.name)) {
                    issues.push({
                        type: 'naming-inconsistency',
                        severity: 'low',
                        component1: comp,
                        component2: layer.name,
                        description: `Component ${comp} doesn't follow naming convention for ${layer.name} layer`,
                    });
                }
            });
        });
        const consistencyScore = 1 - (issues.length / Math.max(arch.layers.length * 10, 1));
        return {
            score: Math.max(0, Math.min(1, consistencyScore)),
            issues,
            isConsistent: issues.every((i) => i.severity === 'low'),
            recommendations: this.getConsistencyRecommendations(issues),
        };
    }
    // Private helper methods
    findFilesByPattern(fileStructure, patterns) {
        return fileStructure.files.filter((file) => patterns.some((pattern) => file.path.includes(pattern)));
    }
    calculateLayerComplexity(files) {
        // Simplified complexity calculation: 0-10 scale
        return Math.min(10, files.length / 5);
    }
    countClasses(files) {
        // Simplified: assume 1 class per file
        return files.length;
    }
    countFunctions(files) {
        // Simplified: assume 5 functions per file
        return files.length * 5;
    }
    inferResponsibilities(layerName) {
        const responsibilities = {
            Presentation: ['Render UI', 'Handle user input', 'Route navigation'],
            API: ['HTTP handling', 'Request validation', 'Response formatting'],
            Service: ['Business logic', 'Data processing', 'Cross-layer coordination'],
            'Data Access': ['Database queries', 'Data transformation', 'Caching'],
            Infrastructure: ['Configuration', 'Logging', 'Error handling', 'Utilities'],
        };
        return responsibilities[layerName] || [];
    }
    findComponentDirs(fileStructure) {
        // Look for typical component structure patterns
        return fileStructure.directories.filter((dir) => dir.includes('components') ||
            dir.includes('modules') ||
            dir.includes('packages'));
    }
    extractPublicAPI(componentPath) {
        // Simplified: extract exported symbols
        // In real implementation, would parse the index.ts file
        return [];
    }
    findComponentDependencies(componentPath) {
        // Simplified: return empty map
        // In real implementation, would analyze imports
        return new Map();
    }
    countInternalAPIs(componentPath) {
        // Simplified count
        return 3;
    }
    classifyArchitecture(layers) {
        const layerNames = layers.map((l) => l.name);
        // Determine pattern based on layers present
        if (layerNames.includes('Presentation') &&
            layerNames.includes('Service') &&
            layerNames.includes('Data Access')) {
            return { name: 'Layered Architecture', type: 'layered', confidence: 0.9 };
        }
        else if (layerNames.some((l) => l.includes('module'))) {
            return { name: 'Modular Architecture', type: 'modular', confidence: 0.8 };
        }
        else {
            return { name: 'Unknown Architecture', type: 'layered', confidence: 0.5 };
        }
    }
    generateRecommendations(pattern, violations) {
        const recommendations = [];
        violations.forEach((violation) => {
            if (violation.severity === 'critical') {
                recommendations.push(`Fix critical ${violation.type}: ${violation.from} → ${violation.to}`);
            }
            else if (violation.severity === 'high') {
                recommendations.push(`Refactor ${violation.from} to remove dependency on ${violation.to}`);
            }
        });
        if (recommendations.length === 0) {
            recommendations.push('Architecture is well-structured and follows best practices');
        }
        return recommendations;
    }
    hasCyclicDependency(boundary, boundaries, visited) {
        visited.add(boundary.name);
        for (const [depName] of boundary.dependencies) {
            if (depName === boundary.name)
                return true;
            if (!visited.has(depName)) {
                const depBoundary = boundaries.find((b) => b.name === depName);
                if (depBoundary && this.hasCyclicDependency(depBoundary, boundaries, visited)) {
                    return true;
                }
            }
        }
        return false;
    }
    followsNamingConvention(componentName, layerName) {
        // Simple naming convention check
        const conventions = {
            Presentation: ['Component', 'Page', 'View'],
            API: ['Controller', 'Route', 'Handler'],
            Service: ['Service', 'Manager', 'Processor'],
            'Data Access': ['Repository', 'DAO', 'Model'],
        };
        const expectedPrefixes = conventions[layerName] || [];
        return expectedPrefixes.some((prefix) => componentName.includes(prefix));
    }
    getConsistencyRecommendations(issues) {
        return issues.map((issue) => `Address ${issue.severity}: ${issue.description}`);
    }
}
exports.ArchitectureDiscovery = ArchitectureDiscovery;
//# sourceMappingURL=ArchitectureDiscovery.js.map