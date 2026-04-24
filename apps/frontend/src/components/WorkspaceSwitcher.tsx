/**
 * @file        apps/frontend/src/components/WorkspaceSwitcher.tsx
 * @module      collaboration/workspace-switching
 * @description React component for hot workspace switching with performance metrics
 */

import React, { useEffect, useState } from 'react';
import { VscSync } from 'vscode-icons-js';
import {
  WorkspaceSwitcher,
  SwitchMetrics,
  getWorkspaceSwitcher,
} from '../services/workspace-switcher.js';
import { CachedWorkspaceState } from '../services/workspace-state-cache.js';

interface Workspace {
  id: string;
  name: string;
}

interface WorkspaceSwitcherPanelProps {
  workspaces: Workspace[];
  currentWorkspaceId: string;
  onSwitch?: (workspaceId: string) => void;
  onGetCurrentState?: () => CachedWorkspaceState | null;
}

/**
 * WorkspaceSwitcher Panel Component
 * Displays workspace list, current active workspace, and switch metrics
 */
export const WorkspaceSwitcherPanel: React.FC<WorkspaceSwitcherPanelProps> = ({
  workspaces,
  currentWorkspaceId,
  onSwitch,
  onGetCurrentState,
}) => {
  const [switcher, setSwitcher] = useState<WorkspaceSwitcher | null>(null);
  const [metrics, setMetrics] = useState<SwitchMetrics | null>(null);
  const [isSwitching, setIsSwitching] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [stats, setStats] = useState<any>(null);

  // Initialize switcher on mount
  useEffect(() => {
    (async () => {
      try {
        const instance = await getWorkspaceSwitcher();
        setSwitcher(instance);
      } catch (err) {
        setError(
          `Failed to initialize switcher: ${err instanceof Error ? err.message : String(err)}`
        );
      }
    })();
  }, []);

  // Periodically update performance stats
  useEffect(() => {
    if (!switcher) return;

    const interval = setInterval(() => {
      const perf = switcher.getPerformanceStats();
      setStats(perf);
    }, 1000);

    return () => clearInterval(interval);
  }, [switcher]);

  const handleWorkspaceSwitch = async (targetId: string) => {
    if (!switcher || !onGetCurrentState) return;
    if (targetId === currentWorkspaceId) return;

    setIsSwitching(true);
    setError(null);

    try {
      const currentState = onGetCurrentState();
      if (!currentState) {
        throw new Error('Could not capture current workspace state');
      }

      const switchMetrics = await switcher.switchWorkspace(
        currentWorkspaceId,
        currentState,
        targetId
      );

      setMetrics(switchMetrics);
      onSwitch?.(targetId);
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      setError(`Switch failed: ${message}`);
      console.error('[WorkspaceSwitcherPanel] Switch error:', err);
    } finally {
      setIsSwitching(false);
    }
  };

  if (error) {
    return (
      <div
        style={{
          padding: '12px',
          backgroundColor: '#f44747',
          color: '#fff',
          borderRadius: '4px',
          marginBottom: '12px',
        }}
      >
        <strong>Error:</strong> {error}
      </div>
    );
  }

  return (
    <div style={{ padding: '12px', fontSize: '13px' }}>
      {/* Header */}
      <div style={{ marginBottom: '12px', fontWeight: '600' }}>
        Workspace Switcher
      </div>

      {/* Active Workspace */}
      <div
        style={{
          padding: '8px',
          backgroundColor: '#2d2d30',
          borderRadius: '4px',
          marginBottom: '12px',
          border: '1px solid #3e3e42',
        }}
      >
        <div style={{ color: '#cccccc', fontSize: '12px', marginBottom: '4px' }}>
          Current:
        </div>
        <div style={{ fontSize: '14px', fontWeight: '600', color: '#4ec9b0' }}>
          {workspaces.find((w) => w.id === currentWorkspaceId)?.name ||
            currentWorkspaceId}
        </div>
      </div>

      {/* Workspace List */}
      <div style={{ marginBottom: '12px' }}>
        <div
          style={{
            color: '#858585',
            fontSize: '12px',
            marginBottom: '8px',
            textTransform: 'uppercase',
          }}
        >
          Available ({workspaces.filter((w) => w.id !== currentWorkspaceId).length})
        </div>
        <div
          style={{
            display: 'flex',
            flexDirection: 'column',
            gap: '6px',
          }}
        >
          {workspaces
            .filter((w) => w.id !== currentWorkspaceId)
            .map((workspace) => (
              <button
                key={workspace.id}
                onClick={() => handleWorkspaceSwitch(workspace.id)}
                disabled={isSwitching}
                style={{
                  padding: '6px 10px',
                  backgroundColor: '#3c3c3c',
                  color: '#cccccc',
                  border: '1px solid #3e3e42',
                  borderRadius: '3px',
                  cursor: isSwitching ? 'not-allowed' : 'pointer',
                  fontSize: '13px',
                  textAlign: 'left',
                  opacity: isSwitching ? 0.6 : 1,
                  transition: 'background-color 0.2s',
                }}
                onMouseEnter={(e) => {
                  if (!isSwitching) {
                    (e.target as HTMLButtonElement).style.backgroundColor =
                      '#3e3e42';
                  }
                }}
                onMouseLeave={(e) => {
                  (e.target as HTMLButtonElement).style.backgroundColor =
                    '#3c3c3c';
                }}
              >
                {isSwitching && (
                  <VscSync
                    style={{
                      display: 'inline',
                      marginRight: '6px',
                      animation: 'spin 1s linear infinite',
                    }}
                  />
                )}
                {workspace.name}
              </button>
            ))}
        </div>
      </div>

      {/* Last Switch Metrics */}
      {metrics && (
        <div
          style={{
            padding: '8px',
            backgroundColor: '#1e1e1e',
            border: '1px solid #3e3e42',
            borderRadius: '4px',
            marginBottom: '12px',
          }}
        >
          <div
            style={{
              color: '#858585',
              fontSize: '12px',
              marginBottom: '6px',
              textTransform: 'uppercase',
            }}
          >
            Last Switch
          </div>
          <div style={{ fontSize: '12px', color: '#cccccc' }}>
            <div>
              Pause: <strong>{metrics.pauseTime.toFixed(1)}ms</strong>
            </div>
            <div>
              Resume: <strong>{metrics.resumeTime.toFixed(1)}ms</strong>
            </div>
            <div>
              Total: <strong>{metrics.totalTime.toFixed(1)}ms</strong>{' '}
              {metrics.totalTime < 200 ? (
                <span style={{ color: '#4ec9b0' }}>✓ under SLA</span>
              ) : (
                <span style={{ color: '#f44747' }}>✗ over SLA</span>
              )}
            </div>
            <div>
              Cache: <strong>{metrics.cacheHit ? 'hit' : 'miss'}</strong>
            </div>
          </div>
        </div>
      )}

      {/* Performance Stats */}
      {stats && (
        <div
          style={{
            padding: '8px',
            backgroundColor: '#1e1e1e',
            border: '1px solid #3e3e42',
            borderRadius: '4px',
          }}
        >
          <div
            style={{
              color: '#858585',
              fontSize: '12px',
              marginBottom: '6px',
              textTransform: 'uppercase',
            }}
          >
            Performance Stats
          </div>
          <div style={{ fontSize: '12px', color: '#cccccc' }}>
            <div>
              Avg Switch: <strong>{stats.avgSwitchTime.toFixed(1)}ms</strong>
            </div>
            <div>
              Max Switch: <strong>{stats.maxSwitchTime.toFixed(1)}ms</strong>
            </div>
            <div>
              Cache Hit Rate:{' '}
              <strong>{(stats.cacheHitRate * 100).toFixed(0)}%</strong>
            </div>
            <div>
              Active Workspaces: <strong>{stats.activeCount}</strong>/5
            </div>
          </div>
        </div>
      )}

      {/* CSS for spinner animation */}
      <style>{`
        @keyframes spin {
          from { transform: rotate(0deg); }
          to { transform: rotate(360deg); }
        }
      `}</style>
    </div>
  );
};
