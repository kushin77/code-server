import * as vscode from 'vscode';
import { Agent, AgentOutput, CodeContext } from './types';
import { CodeAgent } from './agents/CodeAgent';
import { ReviewAgent } from './agents/ReviewAgent';
import { Orchestrator } from './orchestrator/Orchestrator';

let orchestrator: Orchestrator;

export async function activate(context: vscode.ExtensionContext) {
  console.log('Agent Farm extension is activating...');

  // Initialize agents
  const agents: Agent[] = [
    new CodeAgent(),
    new ReviewAgent(),
  ];

  // Initialize orchestrator
  orchestrator = new Orchestrator(agents);

  // Register commands
  context.subscriptions.push(
    vscode.commands.registerCommand('agent-farm.executeTask', async () => {
      const editor = vscode.window.activeTextEditor;
      if (!editor) {
        vscode.window.showErrorMessage('No active editor');
        return;
      }

      vscode.window.showInformationMessage('Agent Farm: Analyzing...');
      
      try {
        const codeContext: CodeContext = {
          uri: editor.document.uri,
          content: editor.document.getText(),
          selection: editor.selection,
          activeEditor: editor,
        };

        const result = await orchestrator.executeTask(codeContext);
        showResults(result);
      } catch (error) {
        vscode.window.showErrorMessage(`Agent Farm error: ${error}`);
      }
    })
  );

  context.subscriptions.push(
    vscode.commands.registerCommand('agent-farm.showDashboard', async () => {
      vscode.window.showInformationMessage('Agent Farm Dashboard (coming soon)');
    })
  );

  context.subscriptions.push(
    vscode.commands.registerCommand('agent-farm.semanticSearch', async () => {
      const query = await vscode.window.showInputBox({
        prompt: 'Search code by meaning',
        placeHolder: 'e.g., "find database connections"',
      });

      if (query) {
        vscode.window.showInformationMessage(`Searching for: ${query}`);
      }
    })
  );

  context.subscriptions.push(
    vscode.commands.registerCommand('agent-farm.analyzeFile', async () => {
      const editor = vscode.window.activeTextEditor;
      if (!editor) {
        vscode.window.showErrorMessage('No active editor');
        return;
      }

      vscode.window.showInformationMessage('Analyzing file...');
      
      try {
        const codeContext: CodeContext = {
          uri: editor.document.uri,
          content: editor.document.getText(),
          selection: editor.selection,
          activeEditor: editor,
        };

        const results = await orchestrator.analyzeFile(codeContext);
        showResults(results);
      } catch (error) {
        vscode.window.showErrorMessage(`Analysis error: ${error}`);
      }
    })
  );

  console.log('Agent Farm extension activated successfully');
}

function showResults(results: AgentOutput[]) {
  if (results.length === 0) {
    vscode.window.showInformationMessage('No issues found');
    return;
  }

  const panel = vscode.window.createWebviewPanel(
    'agentFarmResults',
    'Agent Farm Results',
    vscode.ViewColumn.Two,
    {}
  );

  panel.webview.html = generateResultsHTML(results);
}

function generateResultsHTML(results: AgentOutput[]): string {
  let html = '<html><body><h1>Agent Farm Results</h1>';
  
  for (const result of results) {
    html += `<div><h2>${result.agentName}</h2>`;
    html += `<p>${result.summary}</p>`;
    
    if (result.recommendations && result.recommendations.length > 0) {
      html += '<ul>';
      for (const rec of result.recommendations) {
        html += `<li>${rec}</li>`;
      }
      html += '</ul>';
    }
    
    html += '</div>';
  }
  
  html += '</body></html>';
  return html;
}

export function deactivate() {
  console.log('Agent Farm extension deactivated');
}
