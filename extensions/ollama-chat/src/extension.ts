import * as vscode from 'vscode';
import axios from 'axios';
import { OllamaClient } from './ollama-client';
import { RepositoryIndexer } from './repository-indexer';
import { CodeAnalyzer } from './code-analyzer';

let ollamaClient: OllamaClient;
let repositoryIndexer: RepositoryIndexer;
let codeAnalyzer: CodeAnalyzer;

export async function activate(context: vscode.ExtensionContext) {
  console.log('🚀 Ollama Chat extension activating...');

  const config = vscode.workspace.getConfiguration('ollama');
  const endpoint = config.get<string>('endpoint') || 'http://localhost:11434';
  const defaultModel = config.get<string>('defaultModel') || 'llama2:70b-chat';

  // Initialize Ollama client
  ollamaClient = new OllamaClient(endpoint, defaultModel);
  repositoryIndexer = new RepositoryIndexer(ollamaClient);
  codeAnalyzer = new CodeAnalyzer(ollamaClient, repositoryIndexer);

  // Register chat participant
  const chatParticipant = vscode.chat.createChatParticipant('ollama.chat', handleChatRequest);
  chatParticipant.iconPath = new vscode.ThemeIcon('lightbulb');
  chatParticipant.helpItems = [
    { label: 'analyze', description: 'Analyze current file' },
    { label: 'explain', description: 'Explain code' },
    { label: 'generate', description: 'Generate code' },
    { label: 'refactor', description: 'Suggest refactoring' },
    { label: 'test', description: 'Generate tests' },
    { label: 'document', description: 'Generate documentation' },
  ];

  // Register commands
  context.subscriptions.push(
    vscode.commands.registerCommand('ollama.startServer', startOllamaServer),
    vscode.commands.registerCommand('ollama.stopServer', stopOllamaServer),
    vscode.commands.registerCommand('ollama.listModels', listAvailableModels),
    vscode.commands.registerCommand('ollama.indexRepository', indexRepository),
    vscode.commands.registerCommand('ollama.analyzeFile', analyzeCurrentFile),
    vscode.commands.registerCommand('ollama.generateCode', generateCode)
  );

  // Auto-index repository if enabled
  const autoIndex = config.get<boolean>('indexRepositoryOnStartup');
  if (autoIndex && vscode.workspace.workspaceFolders) {
    await indexRepository();
  }

  // Check Ollama connectivity
  try {
    await ollamaClient.checkHealth();
    vscode.window.showInformationMessage('✅ Ollama connected and ready. Chat with @ollama in the Chat view!');
  } catch (error) {
    vscode.window.showWarningMessage(
      '⚠️ Ollama server not responding. Make sure Docker containers are running.',
      'Retry'
    ).then(selection => {
      if (selection === 'Retry') {
        vscode.commands.executeCommand('ollama.startServer');
      }
    });
  }

  console.log('✅ Ollama Chat extension activated');
}

async function handleChatRequest(
  request: vscode.ChatRequest,
  context: vscode.ChatContext,
  stream: vscode.ChatResponseStream,
  token: vscode.CancellationToken
): Promise<vscode.ChatResult> {
  const prompt = request.prompt;
  
  try {
    stream.progress('🤖 Analyzing request...');

    // Determine intent
    let intent = 'general';
    if (prompt.includes('test') || prompt.includes('spec')) intent = 'test';
    else if (prompt.includes('document') || prompt.includes('doc')) intent = 'document';
    else if (prompt.includes('refactor')) intent = 'refactor';
    else if (prompt.includes('explain') || prompt.includes('what')) intent = 'explain';
    else if (prompt.includes('generate') || prompt.includes('create')) intent = 'generate';

    // Get repository context
    const repoContext = await repositoryIndexer.getRelevantContext(prompt);
    const fileContext = await codeAnalyzer.getFileContext();

    // Build augmented prompt
    const augmentedPrompt = buildAugmentedPrompt(prompt, intent, repoContext, fileContext);

    stream.progress('💭 Thinking with ' + ollamaClient.getCurrentModel() + '...');

    // Stream response from Ollama
    const responseStream = await ollamaClient.generateWithStream(augmentedPrompt);
    for await (const chunk of responseStream) {
      stream.markdown(chunk);
    }

    stream.button({
      command: 'ollama.analyzeFile',
      title: '📊 Analyze File',
    });

    return { metadata: { command: 'ollama.chat' } };
  } catch (error) {
    stream.markdown(`❌ Error: ${(error as Error).message}`);
    return { metadata: { command: 'ollama.chat' } };
  }
}

function buildAugmentedPrompt(
  userPrompt: string,
  intent: string,
  repoContext: string,
  fileContext: string
): string {
  let systemPrompt = `You are an elite software engineer with FAANG-level expertise. You have deep knowledge of the codebase and provide:
- Production-grade code and analysis
- Architectural insights at scale
- Security-hardened implementations
- Performance-optimized solutions
- Enterprise-quality documentation

Context from the repository:
${repoContext}

Current file being edited:
${fileContext}

User request: ${userPrompt}`;

  if (intent === 'test') {
    systemPrompt += '\n\nProvide comprehensive, production-grade tests with 95%+ coverage.';
  } else if (intent === 'document') {
    systemPrompt += '\n\nProvide clear, professional documentation with examples.';
  } else if (intent === 'refactor') {
    systemPrompt += '\n\nIdentify FAANG-level improvements and provide concrete refactoring guidance.';
  } else if (intent === 'explain') {
    systemPrompt += '\n\nExplain the code clearly and concisely, highlighting key design decisions.';
  }

  return systemPrompt;
}

async function startOllamaServer() {
  vscode.window.showInformationMessage('Starting Ollama server...');
  // Server starts via docker-compose
}

async function stopOllamaServer() {
  vscode.window.showInformationMessage('Stopping Ollama server...');
  // Server stops via docker-compose
}

async function listAvailableModels() {
  try {
    const models = await ollamaClient.listModels();
    const modelList = models.map((m: any) => `• ${m.name} (${m.size})`).join('\n');
    vscode.window.showInformationMessage(`Available Models:\n${modelList}`);
  } catch (error) {
    vscode.window.showErrorMessage(`Error listing models: ${(error as Error).message}`);
  }
}

async function indexRepository() {
  vscode.window.showInformationMessage('Indexing repository for context...');
  try {
    await repositoryIndexer.indexWorkspace();
    vscode.window.showInformationMessage('✅ Repository indexed successfully');
  } catch (error) {
    vscode.window.showErrorMessage(`Error indexing repository: ${(error as Error).message}`);
  }
}

async function analyzeCurrentFile() {
  const editor = vscode.window.activeTextEditor;
  if (!editor) {
    vscode.window.showWarningMessage('No file open');
    return;
  }

  vscode.window.showInformationMessage('Analyzing file...');
  try {
    const analysis = await codeAnalyzer.analyzeFile(editor.document);
    vscode.window.showInformationMessage(`Analysis:\n${analysis}`);
  } catch (error) {
    vscode.window.showErrorMessage(`Error analyzing file: ${(error as Error).message}`);
  }
}

async function generateCode() {
  const prompt = await vscode.window.showInputBox({ placeHolder: 'What code should I generate?' });
  if (!prompt) return;

  try {
    const code = await codeAnalyzer.generateCode(prompt);
    const editor = vscode.window.activeTextEditor;
    if (editor) {
      await editor.edit(editBuilder => {
        editBuilder.insert(editor.selection.active, code);
      });
    }
  } catch (error) {
    vscode.window.showErrorMessage(`Error generating code: ${(error as Error).message}`);
  }
}

export function deactivate() {
  console.log('Ollama Chat extension deactivated');
}
