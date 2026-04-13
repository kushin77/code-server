import { Agent, AgentOutput, CodeContext, MultiAgentContext } from '../types';
export declare class CodeAgent extends Agent {
    readonly name = "CodeAgent";
    readonly domain = "Implementation & Refactoring";
    analyze(context: CodeContext): Promise<AgentOutput>;
    coordinate(context: MultiAgentContext, previousResults: AgentOutput[]): Promise<void>;
}
//# sourceMappingURL=CodeAgent.d.ts.map