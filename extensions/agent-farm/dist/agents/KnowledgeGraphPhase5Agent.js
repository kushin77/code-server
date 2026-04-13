"use strict";
/**
 * Phase 5: Knowledge Graph Integration Agent
 * Semantic code understanding through knowledge graphs
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.KnowledgeGraphPhase5Agent = void 0;
const types_1 = require("../types");
const CodeDependencyExtractor_1 = require("../ml/CodeDependencyExtractor");
const KnowledgeGraphBuilder_1 = require("../ml/KnowledgeGraphBuilder");
class KnowledgeGraphPhase5Agent extends types_1.Agent {
    constructor() {
        super();
        this.name = 'KnowledgeGraphPhase5Agent';
        this.domain = 'Code Intelligence & Architecture';
        this.cachedGraph = null;
        this.dependencyExtractor = new CodeDependencyExtractor_1.CodeDependencyExtractor();
        this.graphBuilder = new KnowledgeGraphBuilder_1.KnowledgeGraphBuilder();
    }
    async analyze(context) {
        try {
            this.log('Starting knowledge graph analysis...');
            const dependencies = await this.dependencyExtractor.extractDependencies(context.content, context.uri.fsPath);
            const recommendations = [];
            if (dependencies.length === 0) {
                recommendations.push('No dependencies found - module is testable independently');
            }
            else if (dependencies.length > 10) {
                recommendations.push(`High dependency count (${dependencies.length}) - consider breaking into smaller modules`);
            }
            const types = new Set(dependencies.map((d) => d.type));
            const summary = `Found ${dependencies.length} dependencies of types: ${Array.from(types).join(', ')}`;
            return this.formatOutput(summary, recommendations, dependencies.length > 10 ? 'warning' : 'info');
        }
        catch (error) {
            this.log(`Analysis error: ${error instanceof Error ? error.message : String(error)}`);
            return this.formatOutput('Analysis failed', ['Dependency extraction error'], 'error');
        }
    }
    async coordinate(context, previousResults) {
        this.log('Knowledge graph agent coordinating with other agents...');
    }
    parseQuery(queryText) {
        const lower = queryText.toLowerCase();
        let type = 'relationship';
        if (lower.includes('depend'))
            type = 'dependency';
        if (lower.includes('impact'))
            type = 'impact';
        if (lower.includes('complex'))
            type = 'complexity';
        if (lower.includes('architecture'))
            type = 'architecture';
        const ofMatch = queryText.match(/(?:of|for)\s+(\w+)/i);
        const target = ofMatch ? ofMatch[1] : queryText.split(/\s+/)[0];
        return { type, target };
    }
    findNodeByLabel(label, graph) {
        return Array.from(graph.nodes.values()).find((n) => n.label.toLowerCase() === label.toLowerCase());
    }
    getNodeLabel(nodeId, graph) {
        return graph.nodes.get(nodeId)?.label || nodeId;
    }
    generateReasoning(query, analysis) {
        return `Based on knowledge graph analysis for query type "${query.type}" on target "${query.target}": Criticality ${(analysis.criticality * 100).toFixed(1)}%, Components affected: ${analysis.affectedComponents.length}`;
    }
}
exports.KnowledgeGraphPhase5Agent = KnowledgeGraphPhase5Agent;
exports.default = KnowledgeGraphPhase5Agent;
//# sourceMappingURL=KnowledgeGraphPhase5Agent.js.map