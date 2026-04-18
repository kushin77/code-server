import * as vscode from 'vscode';

export interface Logger {
  log(message: string): void;
  info(message: string): void;
  debug(message: string): void;
  warn(message: string): void;
  error(message: string, error?: Error): void;
}

export interface CodeContext {
  uri: vscode.Uri;
  content: string;
  selection: vscode.Selection;
  activeEditor: vscode.TextEditor;
}

export interface AgentOutput {
  agentName: string;
  domain: string;
  timestamp: Date;
  summary: string;
  details?: string;
  recommendations?: string[];
  severity?: 'info' | 'warning' | 'error';
  codeLocations?: CodeLocation[];
}

export interface CodeLocation {
  file: string;
  line: number;
  column: number;
  snippet: string;
}

export interface MultiAgentContext {
  codeContext: CodeContext;
  intermediateResults: AgentOutput[];
  coordinationState: Record<string, unknown>;
}

export interface TaskDefinition {
  type: string;
  description: string;
  targetAgents: string[];
  parameters?: Record<string, unknown>;
}

export abstract class Agent {
  abstract readonly name: string;
  abstract readonly domain: string;

  abstract analyze(context: CodeContext): Promise<AgentOutput>;

  abstract coordinate(
    context: MultiAgentContext,
    previousResults: AgentOutput[]
  ): Promise<void>;

  protected log(message: string): void {
    console.log(`[${this.name}] ${message}`);
  }

  protected formatOutput(
    summary: string,
    recommendations: string[] = [],
    severity: 'info' | 'warning' | 'error' = 'info'
  ): AgentOutput {
    return {
      agentName: this.name,
      domain: this.domain,
      timestamp: new Date(),
      summary,
      recommendations,
      severity,
    };
  }
}
