import * as vscode from 'vscode';
import { OllamaClient } from './ollama-client';
import { RepositoryIndexer } from './repository-indexer';
import { CodeAnalyzer } from './code-analyzer';
let ollamaClient;
let repositoryIndexer;
let codeAnalyzer;
let activeChatParticipant;
export async function activate(context) {
    console.log('Ollama Chat extension activating...');
    const config = vscode.workspace.getConfiguration('ollama');
    const endpoint = config.get('endpoint') || 'http://localhost:11434';
    const defaultModel = config.get('defaultModel') || 'llama2:70b-chat';
    // Initialize Ollama client
    ollamaClient = new OllamaClient(endpoint, defaultModel);
    repositoryIndexer = new RepositoryIndexer(ollamaClient);
    codeAnalyzer = new CodeAnalyzer(ollamaClient, repositoryIndexer);
    // Register chat participant
    activeChatParticipant = vscode.chat.createChatParticipant('ollama.chat', handleChatRequest);
    const chatParticipant = activeChatParticipant;
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
    context.subscriptions.push(vscode.commands.registerCommand('ollama.startServer', startOllamaServer), vscode.commands.registerCommand('ollama.stopServer', stopOllamaServer), vscode.commands.registerCommand('ollama.listModels', listAvailableModels), vscode.commands.registerCommand('ollama.indexRepository', indexRepository), vscode.commands.registerCommand('ollama.analyzeFile', analyzeCurrentFile), vscode.commands.registerCommand('ollama.generateCode', generateCode), vscode.commands.registerCommand('ollama.generateTests', generateTests), vscode.commands.registerCommand('ollama.refactorCode', refactorCurrentFile), vscode.commands.registerCommand('ollama.generateDocumentation', documentCurrentFile));
    context.subscriptions.push(chatParticipant);
    // Auto-index repository if enabled
    const autoIndex = config.get('indexRepositoryOnStartup');
    if (autoIndex && vscode.workspace.workspaceFolders) {
        await indexRepository();
    }
    // Check Ollama connectivity
    try {
        await ollamaClient.checkHealth();
        vscode.window.showInformationMessage('✅ Ollama connected and ready. Chat with @ollama in the Chat view!');
    }
    catch (error) {
        vscode.window.showWarningMessage('⚠️ Ollama server not responding. Make sure Docker containers are running.', 'Retry').then(selection => {
            if (selection === 'Retry') {
                vscode.commands.executeCommand('ollama.startServer');
            }
        });
    }
    console.log('✅ Ollama Chat extension activated');
}
async function handleChatRequest(request, context, stream, token) {
    const prompt = request.prompt;
    try {
        if (token.isCancellationRequested) {
            return { metadata: { command: 'ollama.chat' } };
        }
        stream.progress('🤖 Analyzing request...');
        const intent = inferIntent(prompt);
        // Get repository context
        const repoContext = await repositoryIndexer.getRelevantContext(prompt);
        const fileContext = await codeAnalyzer.getFileContext();
        // Build augmented prompt
        const augmentedPrompt = buildAugmentedPrompt(prompt, intent, repoContext, fileContext);
        stream.progress('💭 Thinking with ' + ollamaClient.getCurrentModel() + '...');
        // Stream response from Ollama
        const responseStream = await ollamaClient.generateWithStream(augmentedPrompt);
        for await (const chunk of responseStream) {
            if (token.isCancellationRequested) {
                break;
            }
            stream.markdown(chunk);
        }
        stream.button({
            command: 'ollama.analyzeFile',
            title: '📊 Analyze File',
        });
        return { metadata: { command: 'ollama.chat' } };
    }
    catch (error) {
        stream.markdown(`❌ Error: ${error.message}`);
        return { metadata: { command: 'ollama.chat' } };
    }
}
function inferIntent(prompt) {
    const normalized = prompt.toLowerCase();
    if (normalized.includes('test') || normalized.includes('spec'))
        return 'test';
    if (normalized.includes('document') || normalized.includes('doc'))
        return 'document';
    if (normalized.includes('refactor'))
        return 'refactor';
    if (normalized.includes('explain') || normalized.includes('what'))
        return 'explain';
    if (normalized.includes('generate') || normalized.includes('create'))
        return 'generate';
    return 'general';
}
function buildAugmentedPrompt(userPrompt, intent, repoContext, fileContext) {
    let systemPrompt = `You are an expert software engineer with deep knowledge of this codebase. Provide:
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
    }
    else if (intent === 'document') {
        systemPrompt += '\n\nProvide clear, professional documentation with examples.';
    }
    else if (intent === 'refactor') {
        systemPrompt += '\n\nIdentify FAANG-level improvements and provide concrete refactoring guidance.';
    }
    else if (intent === 'explain') {
        systemPrompt += '\n\nExplain the code clearly and concisely, highlighting key design decisions.';
    }
    else if (intent === 'generate') {
        systemPrompt += '\n\nReturn only the implementation and keep the output immediately usable.';
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
        const modelList = models.map((m) => `• ${m.name} (${m.size})`).join('\n');
        vscode.window.showInformationMessage(`Available Models:\n${modelList}`);
    }
    catch (error) {
        vscode.window.showErrorMessage(`Error listing models: ${error.message}`);
    }
}
async function indexRepository() {
    vscode.window.showInformationMessage('Indexing repository for context...');
    try {
        await repositoryIndexer.indexWorkspace();
        vscode.window.showInformationMessage('✅ Repository indexed successfully');
    }
    catch (error) {
        vscode.window.showErrorMessage(`Error indexing repository: ${error.message}`);
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
    }
    catch (error) {
        vscode.window.showErrorMessage(`Error analyzing file: ${error.message}`);
    }
}
async function generateCode() {
    const prompt = await vscode.window.showInputBox({ placeHolder: 'What code should I generate?' });
    if (!prompt)
        return;
    try {
        const code = await codeAnalyzer.generateCode(prompt);
        const editor = vscode.window.activeTextEditor;
        if (editor) {
            await editor.edit(editBuilder => {
                editBuilder.insert(editor.selection.active, code);
            });
        }
    }
    catch (error) {
        vscode.window.showErrorMessage(`Error generating code: ${error.message}`);
    }
}
async function generateTests() {
    const editor = vscode.window.activeTextEditor;
    if (!editor) {
        vscode.window.showWarningMessage('No file open');
        return;
    }
    try {
        const tests = await codeAnalyzer.generateTests(editor.document);
        await vscode.env.clipboard.writeText(tests);
        vscode.window.showInformationMessage('Generated tests copied to clipboard.');
    }
    catch (error) {
        vscode.window.showErrorMessage(`Error generating tests: ${error.message}`);
    }
}
async function refactorCurrentFile() {
    const editor = vscode.window.activeTextEditor;
    if (!editor) {
        vscode.window.showWarningMessage('No file open');
        return;
    }
    try {
        const refactor = await codeAnalyzer.refactorCode(editor.document);
        await vscode.env.clipboard.writeText(refactor);
        vscode.window.showInformationMessage('Refactor guidance copied to clipboard.');
    }
    catch (error) {
        vscode.window.showErrorMessage(`Error refactoring file: ${error.message}`);
    }
}
async function documentCurrentFile() {
    const editor = vscode.window.activeTextEditor;
    if (!editor) {
        vscode.window.showWarningMessage('No file open');
        return;
    }
    try {
        const docs = await codeAnalyzer.generateDocumentation(editor.document);
        await vscode.env.clipboard.writeText(docs);
        vscode.window.showInformationMessage('Documentation draft copied to clipboard.');
    }
    catch (error) {
        vscode.window.showErrorMessage(`Error generating documentation: ${error.message}`);
    }
}
export function deactivate() {
    activeChatParticipant?.dispose();
    console.log('Ollama Chat extension deactivated');
}
//# sourceMappingURL=extension.js.map