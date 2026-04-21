// @file        apps/frontend/src/extensions/docs-editor-panel.tsx
// @module      extensions/docs-editor-panel
// @description React panel for documentation editing and preview

import React, { useState, useEffect } from 'react';
import * as vscode from 'vscode';
import { measureAsyncExtensionProfiler, useExtensionMountProfiler } from '@/utils/extensionProfiler';

interface DocItem {
  id: string;
  title: string;
  content: string;
  format: string;
  lastModified: string;
}

/**
 * Documentation Editor Panel
 *
 * Features:
 * - Live markdown editing
 * - Real-time preview
 * - Multi-document support
 * - Auto-generation from templates
 * - Export to HTML/PDF
 * - Search and indexing
 */
export const DocsEditorPanel: React.FC = () => {
  useExtensionMountProfiler({
    id: 'docs-editor',
    label: 'Docs editor panel',
    category: 'content',
  });

  const [docs, setDocs] = useState<DocItem[]>([]);
  const [selectedDoc, setSelectedDoc] = useState<DocItem | null>(null);
  const [editContent, setEditContent] = useState('');
  const [viewMode, setViewMode] = useState<'edit' | 'preview' | 'split'>('split');
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    void loadDocs();
  }, []);

  const loadDocs = async (): Promise<void> => {
    return measureAsyncExtensionProfiler(
      {
        id: 'docs-editor',
        label: 'Docs editor panel',
        category: 'content',
        kind: 'load',
      },
      async () => {
        try {
          setLoading(true);
          const response = await fetch('http://localhost:3100/api/docs');
          const data = await response.json();

          setDocs(data.docs || []);

          if (data.docs && data.docs.length > 0) {
            setSelectedDoc(data.docs[0]);
            setEditContent(data.docs[0].content);
          }
        } catch (error) {
          vscode.window.showErrorMessage(
            `Failed to load docs: ${error instanceof Error ? error.message : 'Unknown error'}`
          );
        } finally {
          setLoading(false);
        }
      }
    );
  };

  const generateDocs = async (): Promise<void> => {
    try {
      const response = await fetch('http://localhost:3100/api/docs/generate', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ includeAPI: true, includeExamples: true }),
      });

      if (response.ok) {
        await loadDocs();
        vscode.window.showInformationMessage('Documentation generated');
      }
    } catch (error) {
      vscode.window.showErrorMessage(
        `Failed to generate: ${error instanceof Error ? error.message : 'Unknown error'}`
      );
    }
  };

  const saveDoc = async (): Promise<void> => {
    if (!selectedDoc) return;

    try {
      const response = await fetch(`http://localhost:3100/api/docs/${selectedDoc.id}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ content: editContent }),
      });

      if (response.ok) {
        vscode.window.showInformationMessage('Document saved');
        setSelectedDoc({ ...selectedDoc, content: editContent });
      }
    } catch (error) {
      vscode.window.showErrorMessage(
        `Failed to save: ${error instanceof Error ? error.message : 'Unknown error'}`
      );
    }
  };

  const exportDoc = async (format: 'html' | 'pdf'): Promise<void> => {
    if (!selectedDoc) return;

    try {
      const response = await fetch(
        `http://localhost:3100/api/docs/${selectedDoc.id}/export?format=${format}`
      );

      if (response.ok) {
        const data = await response.json();

        const document = await vscode.workspace.openUntitledTextDocument({
          language: format,
          content: data.content,
        });

        await vscode.window.showTextDocument(document);
      }
    } catch (error) {
      vscode.window.showErrorMessage(
        `Failed to export: ${error instanceof Error ? error.message : 'Unknown error'}`
      );
    }
  };

  const renderPreview = (markdown: string): string => {
    // Simplified markdown to HTML conversion
    return markdown
      .replace(/^# (.*?)$/gm, '<h1>$1</h1>')
      .replace(/^## (.*?)$/gm, '<h2>$1</h2>')
      .replace(/^### (.*?)$/gm, '<h3>$1</h3>')
      .replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
      .replace(/\*(.*?)\*/g, '<em>$1</em>')
      .replace(/`(.*?)`/g, '<code>$1</code>')
      .replace(/\n/g, '<br/>');
  };

  return (
    <div
      style={{
        padding: '16px',
        fontFamily: 'var(--vscode-font-family)',
        display: 'flex',
        flexDirection: 'column',
        height: '100vh',
      }}
    >
      <div style={{ marginBottom: '12px' }}>
        <h2 style={{ marginTop: 0 }}>Documentation</h2>

        <div style={{ display: 'flex', gap: '8px', marginBottom: '12px' }}>
          <button
            onClick={generateDocs}
            style={{
              padding: '6px 12px',
              background: 'var(--vscode-button-background)',
              color: 'var(--vscode-button-foreground)',
              border: 'none',
              borderRadius: '4px',
              cursor: 'pointer',
            }}
          >
            Generate
          </button>

          {['edit', 'preview', 'split'].map((mode) => (
            <button
              key={mode}
              onClick={() => setViewMode(mode as any)}
              style={{
                padding: '6px 12px',
                background:
                  viewMode === mode
                    ? 'var(--vscode-button-background)'
                    : 'var(--vscode-button-secondaryBackground)',
                color:
                  viewMode === mode
                    ? 'var(--vscode-button-foreground)'
                    : 'var(--vscode-button-secondaryForeground)',
                border: 'none',
                borderRadius: '4px',
                cursor: 'pointer',
                textTransform: 'capitalize',
              }}
            >
              {mode}
            </button>
          ))}

          <button
            onClick={() => saveDoc()}
            style={{
              padding: '6px 12px',
              background: 'var(--vscode-button-background)',
              color: 'var(--vscode-button-foreground)',
              border: 'none',
              borderRadius: '4px',
              cursor: 'pointer',
              marginLeft: 'auto',
            }}
          >
            Save
          </button>
        </div>

        <div style={{ display: 'flex', gap: '8px', marginBottom: '12px' }}>
          <button
            onClick={() => exportDoc('html')}
            style={{
              padding: '4px 8px',
              fontSize: '12px',
              background: 'var(--vscode-button-secondaryBackground)',
              color: 'var(--vscode-button-secondaryForeground)',
              border: 'none',
              borderRadius: '3px',
              cursor: 'pointer',
            }}
          >
            Export HTML
          </button>

          <button
            onClick={() => exportDoc('pdf')}
            style={{
              padding: '4px 8px',
              fontSize: '12px',
              background: 'var(--vscode-button-secondaryBackground)',
              color: 'var(--vscode-button-secondaryForeground)',
              border: 'none',
              borderRadius: '3px',
              cursor: 'pointer',
            }}
          >
            Export PDF
          </button>
        </div>
      </div>

      <div style={{ display: 'flex', gap: '12px', flex: 1, minHeight: 0 }}>
        {/* Document List */}
        <div
          style={{
            width: '200px',
            borderRight: '1px solid var(--vscode-editor-lineHighlightBorder)',
            overflowY: 'auto',
          }}
        >
          {docs.map((doc) => (
            <div
              key={doc.id}
              onClick={() => {
                setSelectedDoc(doc);
                setEditContent(doc.content);
              }}
              style={{
                padding: '8px',
                background:
                  selectedDoc?.id === doc.id
                    ? 'var(--vscode-editor-selectionBackground)'
                    : 'transparent',
                cursor: 'pointer',
                borderBottom: '1px solid var(--vscode-editor-lineHighlightBorder)',
              }}
            >
              <div style={{ fontWeight: selectedDoc?.id === doc.id ? 'bold' : 'normal' }}>
                {doc.title}
              </div>
              <div style={{ fontSize: '11px', opacity: 0.7 }}>
                {new Date(doc.lastModified).toLocaleDateString()}
              </div>
            </div>
          ))}
        </div>

        {/* Editor and Preview */}
        <div style={{ flex: 1, display: 'flex', gap: '12px', minWidth: 0 }}>
          {/* Editor */}
          {(viewMode === 'edit' || viewMode === 'split') && (
            <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column' }}>
              <label style={{ fontSize: '12px', marginBottom: '4px' }}>Editor</label>
              <textarea
                value={editContent}
                onChange={(e) => setEditContent(e.target.value)}
                style={{
                  flex: 1,
                  padding: '8px',
                  background: 'var(--vscode-editor-background)',
                  color: 'var(--vscode-editor-foreground)',
                  border: '1px solid var(--vscode-editor-lineHighlightBorder)',
                  borderRadius: '4px',
                  fontFamily: 'monospace',
                  fontSize: '12px',
                  resize: 'none',
                }}
              />
            </div>
          )}

          {/* Preview */}
          {(viewMode === 'preview' || viewMode === 'split') && (
            <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column' }}>
              <label style={{ fontSize: '12px', marginBottom: '4px' }}>Preview</label>
              <div
                style={{
                  flex: 1,
                  padding: '8px',
                  background: 'var(--vscode-editor-background)',
                  border: '1px solid var(--vscode-editor-lineHighlightBorder)',
                  borderRadius: '4px',
                  overflowY: 'auto',
                  fontSize: '13px',
                }}
                dangerouslySetInnerHTML={{ __html: renderPreview(editContent) }}
              />
            </div>
          )}
        </div>
      </div>
    </div>
  );
};

export default DocsEditorPanel;
