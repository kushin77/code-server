// @file        apps/frontend/src/extensions/feature-flags-panel.tsx
// @module      extensions/feature-flags-panel
// @description React panel for feature flag management
import React, { useState, useEffect } from 'react';
import * as vscode from 'vscode';
/**
 * Feature Flags Management Panel
 *
 * Provides:
 * - List all flags (local, LaunchDarkly, Unleash)
 * - Toggle flags on/off
 * - Create new flags
 * - View flag details and analytics
 * - Export/import flag configurations
 * - Multi-environment support
 */
export const FeatureFlagsPanel = () => {
    const [flags, setFlags] = useState([]);
    const [loading, setLoading] = useState(true);
    const [searchTerm, setSearchTerm] = useState('');
    const [newFlagName, setNewFlagName] = useState('');
    const [filterProvider, setFilterProvider] = useState('all');
    useEffect(() => {
        loadFlags();
        const interval = setInterval(loadFlags, 30000); // Refresh every 30 seconds
        return () => clearInterval(interval);
    }, []);
    const loadFlags = async () => {
        try {
            setLoading(true);
            const response = await fetch('http://localhost:3100/api/flags');
            const data = await response.json();
            setFlags(data.flags);
        }
        catch (error) {
            vscode.window.showErrorMessage(`Failed to load flags: ${error instanceof Error ? error.message : 'Unknown error'}`);
        }
        finally {
            setLoading(false);
        }
    };
    const toggleFlag = async (flag) => {
        try {
            const response = await fetch(`http://localhost:3100/api/flags/${flag.key}`, {
                method: 'PUT',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ enabled: !flag.enabled }),
            });
            if (response.ok) {
                await loadFlags();
            }
            else {
                vscode.window.showErrorMessage('Failed to toggle flag');
            }
        }
        catch (error) {
            vscode.window.showErrorMessage(`Error toggling flag: ${error instanceof Error ? error.message : 'Unknown error'}`);
        }
    };
    const createFlag = async () => {
        if (!newFlagName.trim()) {
            vscode.window.showWarningMessage('Flag name cannot be empty');
            return;
        }
        try {
            const response = await fetch('http://localhost:3100/api/flags', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ key: newFlagName, name: newFlagName }),
            });
            if (response.ok) {
                setNewFlagName('');
                await loadFlags();
            }
            else {
                vscode.window.showErrorMessage('Failed to create flag');
            }
        }
        catch (error) {
            vscode.window.showErrorMessage(`Error creating flag: ${error instanceof Error ? error.message : 'Unknown error'}`);
        }
    };
    const deleteFlag = async (flagKey) => {
        const confirm = await vscode.window.showInformationMessage(`Delete flag "${flagKey}"?`, 'Delete', 'Cancel');
        if (confirm !== 'Delete')
            return;
        try {
            const response = await fetch(`http://localhost:3100/api/flags/${flagKey}`, {
                method: 'DELETE',
            });
            if (response.ok) {
                await loadFlags();
            }
            else {
                vscode.window.showErrorMessage('Failed to delete flag');
            }
        }
        catch (error) {
            vscode.window.showErrorMessage(`Error deleting flag: ${error instanceof Error ? error.message : 'Unknown error'}`);
        }
    };
    const exportFlags = async () => {
        try {
            const response = await fetch('http://localhost:3100/api/flags/export');
            const data = await response.json();
            const document = await vscode.workspace.openUntitledTextDocument({
                language: 'json',
                content: JSON.stringify(data.flags, null, 2),
            });
            await vscode.window.showTextDocument(document);
        }
        catch (error) {
            vscode.window.showErrorMessage(`Failed to export flags: ${error instanceof Error ? error.message : 'Unknown error'}`);
        }
    };
    const filteredFlags = flags.filter((flag) => {
        const matchesSearch = flag.key.toLowerCase().includes(searchTerm.toLowerCase()) ||
            flag.name.toLowerCase().includes(searchTerm.toLowerCase());
        const matchesProvider = filterProvider === 'all' || flag.provider === filterProvider;
        return matchesSearch && matchesProvider;
    });
    return (<div style={{ padding: '16px', fontFamily: 'var(--vscode-font-family)' }}>
      <div style={{ marginBottom: '16px' }}>
        <h2 style={{ marginTop: 0 }}>Feature Flags</h2>

        <div style={{ display: 'flex', gap: '8px', marginBottom: '12px' }}>
          <input type="text" placeholder="Search flags..." value={searchTerm} onChange={(e) => setSearchTerm(e.target.value)} style={{
            flex: 1,
            padding: '6px 8px',
            background: 'var(--vscode-input-background)',
            color: 'var(--vscode-input-foreground)',
            border: '1px solid var(--vscode-input-border)',
            borderRadius: '4px',
        }}/>

          <select value={filterProvider} onChange={(e) => setFilterProvider(e.target.value)} style={{
            padding: '6px 8px',
            background: 'var(--vscode-input-background)',
            color: 'var(--vscode-input-foreground)',
            border: '1px solid var(--vscode-input-border)',
            borderRadius: '4px',
        }}>
            <option value="all">All Providers</option>
            <option value="local">Local</option>
            <option value="launchdarkly">LaunchDarkly</option>
            <option value="unleash">Unleash</option>
          </select>

          <button onClick={loadFlags} style={{
            padding: '6px 12px',
            background: 'var(--vscode-button-background)',
            color: 'var(--vscode-button-foreground)',
            border: 'none',
            borderRadius: '4px',
            cursor: 'pointer',
        }}>
            {loading ? 'Loading...' : 'Refresh'}
          </button>

          <button onClick={exportFlags} style={{
            padding: '6px 12px',
            background: 'var(--vscode-button-secondaryBackground)',
            color: 'var(--vscode-button-secondaryForeground)',
            border: 'none',
            borderRadius: '4px',
            cursor: 'pointer',
        }}>
            Export
          </button>
        </div>

        <div style={{ display: 'flex', gap: '8px', marginBottom: '16px' }}>
          <input type="text" placeholder="New flag name..." value={newFlagName} onChange={(e) => setNewFlagName(e.target.value)} onKeyPress={(e) => {
            if (e.key === 'Enter')
                createFlag();
        }} style={{
            flex: 1,
            padding: '6px 8px',
            background: 'var(--vscode-input-background)',
            color: 'var(--vscode-input-foreground)',
            border: '1px solid var(--vscode-input-border)',
            borderRadius: '4px',
        }}/>

          <button onClick={createFlag} style={{
            padding: '6px 12px',
            background: 'var(--vscode-button-background)',
            color: 'var(--vscode-button-foreground)',
            border: 'none',
            borderRadius: '4px',
            cursor: 'pointer',
        }}>
            Create
          </button>
        </div>
      </div>

      {loading ? (<div style={{ color: 'var(--vscode-foreground)', opacity: 0.7 }}>Loading flags...</div>) : filteredFlags.length === 0 ? (<div style={{ color: 'var(--vscode-foreground)', opacity: 0.7 }}>No flags found</div>) : (<div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
          {filteredFlags.map((flag) => (<div key={flag.key} style={{
                    display: 'flex',
                    alignItems: 'center',
                    gap: '12px',
                    padding: '8px',
                    background: 'var(--vscode-editor-background)',
                    border: '1px solid var(--vscode-editor-lineHighlightBorder)',
                    borderRadius: '4px',
                }}>
              <input type="checkbox" checked={flag.enabled} onChange={() => toggleFlag(flag)} style={{ width: '16px', height: '16px', cursor: 'pointer' }}/>

              <div style={{ flex: 1 }}>
                <div style={{ fontWeight: 500 }}>{flag.name}</div>

                <div style={{ fontSize: '11px', color: 'var(--vscode-descriptionForeground)' }}>
                  {flag.key} • {flag.provider}
                </div>

                {flag.description && (<div style={{ fontSize: '12px', marginTop: '4px' }}>
                    {flag.description}
                  </div>)}
              </div>

              <button onClick={() => deleteFlag(flag.key)} style={{
                    padding: '4px 8px',
                    background: 'transparent',
                    color: 'var(--vscode-errorForeground)',
                    border: 'none',
                    borderRadius: '4px',
                    cursor: 'pointer',
                    fontSize: '12px',
                }}>
                Delete
              </button>
            </div>))}
        </div>)}
    </div>);
};
export default FeatureFlagsPanel;
//# sourceMappingURL=feature-flags-panel.js.map