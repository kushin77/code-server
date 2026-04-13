"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.activate = activate;
exports.deactivate = deactivate;
const vscode = __importStar(require("vscode"));
const CodeAgent_1 = require("./agents/CodeAgent");
const ReviewAgent_1 = require("./agents/ReviewAgent");
const SemanticSearchAgent_1 = require("./agents/SemanticSearchAgent");
const Orchestrator_1 = require("./orchestrator/Orchestrator");
let orchestrator;
async function activate(context) {
    console.log('Agent Farm extension is activating...');
    // Initialize agents
    const agents = [
        new CodeAgent_1.CodeAgent(),
        new ReviewAgent_1.ReviewAgent(),
        new SemanticSearchAgent_1.SemanticSearchAgent(),
    ];
    // Initialize orchestrator
    orchestrator = new Orchestrator_1.Orchestrator(agents);
    // Register commands
    context.subscriptions.push(vscode.commands.registerCommand('agent-farm.executeTask', async () => {
        const editor = vscode.window.activeTextEditor;
        if (!editor) {
            vscode.window.showErrorMessage('No active editor');
            return;
        }
        vscode.window.showInformationMessage('Agent Farm: Analyzing...');
        try {
            const codeContext = {
                uri: editor.document.uri,
                content: editor.document.getText(),
                selection: editor.selection,
                activeEditor: editor,
            };
            const result = await orchestrator.executeTask(codeContext);
            showResults(result);
        }
        catch (error) {
            vscode.window.showErrorMessage(`Agent Farm error: ${error}`);
        }
    }));
    context.subscriptions.push(vscode.commands.registerCommand('agent-farm.showDashboard', async () => {
        vscode.window.showInformationMessage('Agent Farm Dashboard (coming soon)');
    }));
    context.subscriptions.push(vscode.commands.registerCommand('agent-farm.semanticSearch', async () => {
        const query = await vscode.window.showInputBox({
            prompt: 'Search code by meaning',
            placeHolder: 'e.g., "find database connections"',
        });
        if (query) {
            vscode.window.showInformationMessage(`Searching for: ${query}`);
        }
    }));
    context.subscriptions.push(vscode.commands.registerCommand('agent-farm.analyzeFile', async () => {
        const editor = vscode.window.activeTextEditor;
        if (!editor) {
            vscode.window.showErrorMessage('No active editor');
            return;
        }
        vscode.window.showInformationMessage('Analyzing file...');
        try {
            const codeContext = {
                uri: editor.document.uri,
                content: editor.document.getText(),
                selection: editor.selection,
                activeEditor: editor,
            };
            const results = await orchestrator.analyzeFile(codeContext);
            showResults(results);
        }
        catch (error) {
            vscode.window.showErrorMessage(`Analysis error: ${error}`);
        }
    }));
    console.log('Agent Farm extension activated successfully');
}
function showResults(results) {
    if (results.length === 0) {
        vscode.window.showInformationMessage('No issues found');
        return;
    }
    const panel = vscode.window.createWebviewPanel('agentFarmResults', 'Agent Farm Results', vscode.ViewColumn.Two, {});
    panel.webview.html = generateResultsHTML(results);
}
function generateResultsHTML(results) {
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
function deactivate() {
    console.log('Agent Farm extension deactivated');
}
//# sourceMappingURL=extension.js.map