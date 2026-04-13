/**
 * Agent Farm Dashboard
 * 
 * Provides webview UI for Agent Farm status, analytics, and interaction.
 */

import * as vscode from 'vscode';
import { OrchestratorResult, AgentResult, Recommendation } from './types';

/**
 * Dashboard for Agent Farm analysis results and metrics
 */
export class AgentFarmDashboard {
  private panel: vscode.WebviewPanel | undefined;
  private extensionUri: vscode.Uri;
  private analysisHistory: OrchestratorResult[] = [];

  constructor(extensionUri: vscode.Uri) {
    this.extensionUri = extensionUri;
  }

  /**
   * Show the dashboard
   */
  show(analysis?: OrchestratorResult): void {
    if (analysis) {
      this.analysisHistory.push(analysis);
    }

    const column = vscode.ViewColumn.Two;

    if (this.panel) {
      this.panel.reveal(column);
    } else {
      this.panel = vscode.window.createWebviewPanel(
        'agentFarmDashboard',
        'Agent Farm Dashboard',
        column,
        {
          enableScripts: true,
          retainContextWhenHidden: true,
        }
      );

      this.panel.onDidDispose(() => {
        this.panel = undefined;
      });
    }

    this.panel.webview.html = this.getHtmlContent();
  }

  /**
   * Update dashboard with new analysis
   */
  updateAnalysis(analysis: OrchestratorResult): void {
    this.analysisHistory.push(analysis);
    
    if (this.panel) {
      this.panel.webview.html = this.getHtmlContent();
    }
  }

  /**
   * Get HTML content for the dashboard
   */
  private getHtmlContent(): string {
    const latestAnalysis = this.analysisHistory[this.analysisHistory.length - 1];

    if (!latestAnalysis) {
      return this.getEmptyStateHtml();
    }

    return this.getRenderHtml(latestAnalysis);
  }

  /**
   * Empty state HTML
   */
  private getEmptyStateHtml(): string {
    return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Agent Farm Dashboard</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', sans-serif;
      background: #1e1e1e;
      color: #e0e0e0;
      padding: 40px 20px;
    }
    .container { max-width: 600px; margin: 0 auto; text-align: center; }
    h1 { font-size: 28px; margin-bottom: 10px; color: #4ec9b0; }
    p { font-size: 14px; color: #888; margin-bottom: 20px; }
    .logo { font-size: 48px; margin-bottom: 20px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="logo">🤖</div>
    <h1>Agent Farm</h1>
    <p>Multi-Agent Development System</p>
    <p>Run analysis on your code to get started</p>
  </div>
</body>
</html>`;
  }

  /**
   * Render analysis results
   */
  private getRenderHtml(analysis: OrchestratorResult): string {
    const { summary, agentResults, aggregatedRecommendations } = analysis;
    const criticalItems = aggregatedRecommendations.filter((r: Recommendation) => r.severity === 'critical');
    const warningItems = aggregatedRecommendations.filter((r: Recommendation) => r.severity === 'warning');
    const infoItems = aggregatedRecommendations.filter((r: Recommendation) => r.severity === 'info');

    return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Agent Farm Dashboard</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', sans-serif;
      background: #1e1e1e;
      color: #e0e0e0;
      padding: 20px;
      line-height: 1.6;
    }
    .container { max-width: 1000px; margin: 0 auto; }
    h1 { color: #4ec9b0; margin-bottom: 20px; display: flex; align-items: center; gap: 10px; }
    h2 { color: #9cdcfe; margin-top: 20px; margin-bottom: 10px; font-size: 16px; }
    
    .header-info {
      background: #252526;
      padding: 12px;
      border-radius: 4px;
      margin-bottom: 20px;
      font-size: 12px;
      color: #888;
    }
    
    .stats-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
      gap: 10px;
      margin-bottom: 20px;
    }
    
    .stat-card {
      background: #252526;
      padding: 12px;
      border-radius: 4px;
      border-left: 4px solid #4ec9b0;
    }
    
    .stat-value {
      font-size: 24px;
      font-weight: bold;
      color: #4ec9b0;
    }
    
    .stat-label {
      font-size: 11px;
      color: #888;
      text-transform: uppercase;
      margin-top: 4px;
    }
    
    .stat-card.critical { border-left-color: #f48771; }
    .stat-card.critical .stat-value { color: #f48771; }
    
    .stat-card.warning { border-left-color: #dcdcaa; }
    .stat-card.warning .stat-value { color: #dcdcaa; }
    
    .agents-list {
      background: #252526;
      padding: 12px;
      border-radius: 4px;
      margin-bottom: 20px;
    }
    
    .agent-item {
      padding: 8px 0;
      border-bottom: 1px solid #3e3e42;
      font-size: 12px;
      display: flex;
      justify-content: space-between;
      align-items: center;
    }
    
    .agent-item:last-child { border-bottom: none; }
    .agent-name { color: #9cdcfe; font-weight: 500; }
    .agent-confidence { color: #888; font-size: 11px; }
    
    .recommendations {
      background: #252526;
      border-radius: 4px;
      overflow: hidden;
    }
    
    .recommendation-item {
      padding: 12px;
      border-bottom: 1px solid #3e3e42;
      border-left: 4px solid #4ec9b0;
    }
    
    .recommendation-item.critical { border-left-color: #f48771; }
    .recommendation-item.warning { border-left-color: #dcdcaa; }
    .recommendation-item.info { border-left-color: #569cd6; }
    
    .rec-title {
      font-weight: 500;
      margin-bottom: 4px;
      color: #e0e0e0;
    }
    
    .rec-description {
      font-size: 12px;
      color: #888;
      margin-bottom: 8px;
    }
    
    .rec-severity {
      display: inline-block;
      font-size: 10px;
      padding: 2px 6px;
      border-radius: 2px;
      text-transform: uppercase;
      font-weight: 500;
    }
    
    .rec-severity.critical { background: #f48771; color: #1e1e1e; }
    .rec-severity.warning { background: #dcdcaa; color: #1e1e1e; }
    .rec-severity.info { background: #569cd6; color: #fff; }
    
    .rec-actionable {
      font-size: 11px;
      color: #4ec9b0;
      margin-left: 8px;
    }
    
    .empty-state {
      text-align: center;
      padding: 40px;
      color: #888;
    }
  </style>
</head>
<body>
  <div class="container">
    <h1>🤖 Agent Farm Analysis</h1>
    
    <div class="header-info">
      <div>📄 File: <code>${analysis.documentUri}</code></div>
      <div>⏱️ Duration: ${analysis.totalDuration}ms</div>
      <div>🔄 Agents: ${agentResults.length}</div>
    </div>
    
    <h2>Summary</h2>
    <div class="stats-grid">
      <div class="stat-card critical">
        <div class="stat-value">${summary.criticalCount}</div>
        <div class="stat-label">Critical</div>
      </div>
      <div class="stat-card warning">
        <div class="stat-value">${summary.warningCount}</div>
        <div class="stat-label">Warnings</div>
      </div>
      <div class="stat-card">
        <div class="stat-value">${summary.infoCount}</div>
        <div class="stat-label">Info</div>
      </div>
      <div class="stat-card">
        <div class="stat-value">${summary.averageConfidence}%</div>
        <div class="stat-label">Avg Confidence</div>
      </div>
    </div>
    
    <h2>Agents</h2>
    <div class="agents-list">
      ${agentResults.map((result: AgentResult) => `
          <div>
            <div class="agent-name">${result.agent}</div>
            <div style="font-size: 10px; color: #666;">${result.specialization}</div>
          </div>
          <div class="agent-confidence">${result.confidence}% • ${result.duration}ms</div>
        </div>
      `).join('')}
    </div>
    
    ${aggregatedRecommendations.length > 0 ? `
      <h2>Recommendations (${aggregatedRecommendations.length})</h2>
      <div class="recommendations">
        ${aggregatedRecommendations.map((rec, idx) => `
          <div class="recommendation-item ${rec.severity}">
            <div class="rec-title">
              ${rec.title}
              <span class="rec-severity ${rec.severity}">${rec.severity}</span>
              ${rec.actionable ? '<span class="rec-actionable">✓ Actionable</span>' : ''}
            </div>
            <div class="rec-description">${rec.description}</div>
            ${rec.suggestedFix ? `<div style="font-size: 11px; color: #4ec9b0; margin-top: 4px;">💡 ${rec.suggestedFix}</div>` : ''}
          </div>
        `).join('')}
      </div>
    ` : `
      <div class="empty-state">
        <div style="font-size: 24px; margin-bottom: 10px;">✨</div>
        <div>No issues found! Code looks great.</div>
      </div>
    `}
  </div>
</body>
</html>`;
  }

  /**
   * Dispose resources
   */
  dispose(): void {
    if (this.panel) {
      this.panel.dispose();
    }
  }
}
