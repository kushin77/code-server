"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.Orchestrator = void 0;
class Orchestrator {
    constructor(agents) {
        this.agents = new Map(agents.map(a => [a.name, a]));
        console.log(`Orchestrator initialized with ${agents.length} agents`);
    }
    async executeTask(codeContext) {
        console.log('Orchestrator: Executing task...');
        const results = [];
        // Route to all available agents
        for (const agent of this.agents.values()) {
            try {
                const output = await agent.analyze(codeContext);
                results.push(output);
            }
            catch (error) {
                console.error(`Agent ${agent.name} failed:`, error);
            }
        }
        return results;
    }
    async analyzeFile(codeContext) {
        console.log('Orchestrator: Analyzing file...');
        const results = [];
        // Execute all agents in sequence
        for (const agent of this.agents.values()) {
            try {
                const output = await agent.analyze(codeContext);
                results.push(output);
                // Allow agents to coordinate based on previous results
                const multiAgentContext = {
                    codeContext,
                    intermediateResults: results,
                    coordinationState: {},
                };
                await agent.coordinate(multiAgentContext, results);
            }
            catch (error) {
                console.error(`Analysis failed for ${agent.name}:`, error);
            }
        }
        return results;
    }
    async routeTask(taskType, codeContext) {
        console.log(`Orchestrator: Routing task of type "${taskType}"...`);
        const results = [];
        // Route to specialized agent
        const agent = this.selectAgent(taskType);
        if (agent) {
            try {
                const output = await agent.analyze(codeContext);
                results.push(output);
            }
            catch (error) {
                console.error(`Routing failed:`, error);
            }
        }
        return results;
    }
    selectAgent(taskType) {
        // Simple routing logic (expanded in full implementation)
        switch (taskType.toLowerCase()) {
            case 'refactor':
            case 'optimize':
            case 'implement':
                return this.agents.get('CodeAgent');
            case 'review':
            case 'quality':
            case 'security':
                return this.agents.get('ReviewAgent');
            default:
                // Return first available agent as fallback
                return this.agents.values().next().value;
        }
    }
    getAgents() {
        return Array.from(this.agents.values());
    }
    getAgentByName(name) {
        return this.agents.get(name);
    }
}
exports.Orchestrator = Orchestrator;
//# sourceMappingURL=Orchestrator.js.map