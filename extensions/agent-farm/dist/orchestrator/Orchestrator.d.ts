import { Agent, AgentOutput, CodeContext } from '../types';
export declare class Orchestrator {
    private agents;
    constructor(agents: Agent[]);
    executeTask(codeContext: CodeContext): Promise<AgentOutput[]>;
    analyzeFile(codeContext: CodeContext): Promise<AgentOutput[]>;
    routeTask(taskType: string, codeContext: CodeContext): Promise<AgentOutput[]>;
    private selectAgent;
    getAgents(): Agent[];
    getAgentByName(name: string): Agent | undefined;
}
//# sourceMappingURL=Orchestrator.d.ts.map
