import * as vscode from 'vscode';
export class CodeAnalyzer {
    constructor(ollamaClient, repositoryIndexer) {
        this.ollamaClient = ollamaClient;
        this.repositoryIndexer = repositoryIndexer;
    }
    async analyzeFile(document) {
        const content = document.getText();
        const fileName = document.fileName;
        const prompt = `Analyze this code file: ${fileName}

${content}

Provide:
1. Purpose and functionality summary
2. Key functions/classes and their roles
3. Potential issues or improvements
4. Complexity analysis
5. Security considerations`;
        return await this.ollamaClient.generate(prompt);
    }
    async getFileContext() {
        const editor = vscode.window.activeTextEditor;
        if (!editor) {
            return '';
        }
        const document = editor.document;
        const lineCount = Math.min(50, document.lineCount); // First 50 lines
        let context = `File: ${document.fileName}\n`;
        context += `Language: ${document.languageId}\n\n`;
        for (let i = 0; i < lineCount; i++) {
            context += document.lineAt(i).text + '\n';
        }
        return context;
    }
    async generateCode(prompt) {
        const editor = vscode.window.activeTextEditor;
        const fileContext = editor ? `Current file language: ${editor.document.languageId}` : '';
        const enhancedPrompt = `Generate production-grade code.

${fileContext}

Request: ${prompt}

Provide only the code, no explanations.`;
        return await this.ollamaClient.generate(enhancedPrompt);
    }
    async generateTests(document) {
        const content = document.getText();
        const prompt = `Generate comprehensive, production-grade unit tests for this code.
Language: ${document.languageId}
Target: 95%+ coverage

${content}

Provide complete test suite.`;
        return await this.ollamaClient.generate(prompt);
    }
    async refactorCode(document) {
        const content = document.getText();
        const prompt = `As a FAANG-level engineer, suggest refactoring for this code:

${content}

Provide:
1. Specific issues found
2. Improved code
3. Reasoning for each change
4. Performance/maintainability gains`;
        return await this.ollamaClient.generate(prompt);
    }
    async generateDocumentation(document) {
        const content = document.getText();
        const prompt = `Generate professional documentation for this code:

${content}

Include:
1. Overview
2. API/Function documentation
3. Usage examples
4. Configuration guide`;
        return await this.ollamaClient.generate(prompt);
    }
}
//# sourceMappingURL=code-analyzer.js.map