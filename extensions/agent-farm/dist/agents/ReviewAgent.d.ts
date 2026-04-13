import { Agent, AgentOutput, CodeContext, MultiAgentContext } from '../types';
export declare class ReviewAgent extends Agent {
    readonly name = "ReviewAgent";
    readonly domain = "Code Quality & Best Practices";
    analyze(context: CodeContext): Promise<AgentOutput>;
    coordinate(context: MultiAgentContext, previousResults: AgentOutput[]): Promise<void>;
}
//# sourceMappingURL=ReviewAgent.d.ts.map