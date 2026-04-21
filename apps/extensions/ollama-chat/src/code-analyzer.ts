import * as vscode from 'vscode';
import { OllamaClient } from './ollama-client';
import { RepositoryIndexer } from './repository-indexer';

interface SecurityRule {
  readonly pattern: RegExp;
  readonly message: string;
  readonly severity: vscode.DiagnosticSeverity;
}

export class CodeAnalyzer {
  constructor(
    private ollamaClient: OllamaClient,
    private repositoryIndexer: RepositoryIndexer
  ) {}

  async analyzeFile(document: vscode.TextDocument): Promise<string> {
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

  async getFileContext(): Promise<string> {
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

  async generateCode(prompt: string): Promise<string> {
    const editor = vscode.window.activeTextEditor;
    const fileContext = editor ? `Current file language: ${editor.document.languageId}` : '';

    const enhancedPrompt = `Generate production-grade code.

${fileContext}

Request: ${prompt}

Provide only the code, no explanations.`;

    return await this.ollamaClient.generate(enhancedPrompt);
  }

  async generateTests(document: vscode.TextDocument): Promise<string> {
    const content = document.getText();

    const prompt = `Generate comprehensive, production-grade unit tests for this code.
Language: ${document.languageId}
Target: 95%+ coverage

${content}

Provide complete test suite.`;

    return await this.ollamaClient.generate(prompt);
  }

  async refactorCode(document: vscode.TextDocument): Promise<string> {
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

  async generateDocumentation(document: vscode.TextDocument): Promise<string> {
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

  buildSecurityDiagnostics(document: vscode.TextDocument): vscode.Diagnostic[] {
    const findings: vscode.Diagnostic[] = [];
    const rules: SecurityRule[] = [
      {
        pattern: /\beval\s*\(/g,
        message: 'Avoid eval(); use explicit parsing or safe dispatch instead.',
        severity: vscode.DiagnosticSeverity.Error,
      },
      {
        pattern: /\bdangerouslySetInnerHTML\b/g,
        message: 'Avoid dangerouslySetInnerHTML unless the value is sanitized.',
        severity: vscode.DiagnosticSeverity.Error,
      },
      {
        pattern: /\binnerHTML\s*=/g,
        message: 'Avoid innerHTML assignments; prefer textContent or sanitized rendering.',
        severity: vscode.DiagnosticSeverity.Warning,
      },
      {
        pattern: /\b(?:child_process\.)?exec(?:Sync)?\s*\(/g,
        message: 'Shell execution is security-sensitive; prefer a safe API or strict argument validation.',
        severity: vscode.DiagnosticSeverity.Error,
      },
      {
        pattern: /\b(?:password|secret|token|api[_-]?key)\s*[:=]\s*['"][^'"]+['"]/gi,
        message: 'Hardcoded credential detected; load secrets from a secure source instead.',
        severity: vscode.DiagnosticSeverity.Error,
      },
      {
        pattern: /https?:\/\//g,
        message: 'Use HTTPS-only endpoints for security-sensitive integrations.',
        severity: vscode.DiagnosticSeverity.Information,
      },
    ];

    for (let lineIndex = 0; lineIndex < document.lineCount; lineIndex++) {
      const line = document.lineAt(lineIndex);

      for (const rule of rules) {
        const regex = new RegExp(rule.pattern.source, rule.pattern.flags.includes('g') ? rule.pattern.flags : `${rule.pattern.flags}g`);
        let match: RegExpExecArray | null;

        while ((match = regex.exec(line.text)) !== null) {
          const startColumn = match.index;
          const endColumn = startColumn + Math.max(match[0].length, 1);
          const diagnostic = new vscode.Diagnostic(
            new vscode.Range(lineIndex, startColumn, lineIndex, endColumn),
            rule.message,
            rule.severity
          );

          diagnostic.source = 'ollama-sast';
          findings.push(diagnostic);

          if (match[0].length === 0) {
            break;
          }
        }
      }
    }

    return findings;
  }
}
