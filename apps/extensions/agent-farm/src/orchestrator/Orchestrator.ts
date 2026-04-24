import { Agent, AgentOutput, CodeContext, MultiAgentContext } from '../types';

export class Orchestrator {
  private agents: Map<string, Agent>;

  constructor(agents: Agent[]) {
    this.agents = new Map(agents.map(a => [a.name, a]));
    console.log(`Orchestrator initialized with ${agents.length} agents`);
  }

  async executeTask(codeContext: CodeContext): Promise<AgentOutput[]> {
    console.log('Orchestrator: Executing task...');
    const results: AgentOutput[] = [];

    // Route to all available agents
    for (const agent of this.agents.values()) {
      try {
        const output = await agent.analyze(codeContext);
        results.push(output);
      } catch (error) {
        console.error(`Agent ${agent.name} failed:`, error);
      }
    }

    return results;
  }

  async analyzeFile(codeContext: CodeContext): Promise<AgentOutput[]> {
    console.log('Orchestrator: Analyzing file...');
    const results: AgentOutput[] = [];

    // Execute all agents in sequence
    for (const agent of this.agents.values()) {
      try {
        const output = await agent.analyze(codeContext);
        results.push(output);

        // Allow agents to coordinate based on previous results
        const multiAgentContext: MultiAgentContext = {
          codeContext,
          intermediateResults: results,
          coordinationState: {},
        };

        await agent.coordinate(multiAgentContext, results);
      } catch (error) {
        console.error(`Analysis failed for ${agent.name}:`, error);
      }
    }

    return results;
  }

  async routeTask(taskType: string, codeContext: CodeContext): Promise<AgentOutput[]> {
    console.log(`Orchestrator: Routing task of type "${taskType}"...`);

    const results: AgentOutput[] = [];

    // Route to specialized agent
    const agent = this.selectAgent(taskType);
    if (agent) {
      try {
        const output = await agent.analyze(codeContext);
        results.push(output);
      } catch (error) {
        console.error(`Routing failed:`, error);
      }
    }

    return results;
  }

  private selectAgent(taskType: string): Agent | undefined {
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

  getAgents(): Agent[] {
    return Array.from(this.agents.values());
  }

  getAgentByName(name: string): Agent | undefined {
    return this.agents.get(name);
  }
}
