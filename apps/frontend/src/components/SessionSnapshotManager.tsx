/**
 * @file        apps/frontend/src/components/SessionSnapshotManager.tsx
 * @module      collaboration/session-persistence
 * @description React component for session snapshot capture and restore UI
 */

import React, { useEffect, useState, useRef } from 'react';
import { VscSaveAll, VscHistory, VscTrash, VscClose } from 'react-icons/vsc';
import { SessionSnapshotService } from '../services/session-snapshot/service.js';
import { SnapshotMetadata } from '../services/session-snapshot/types.js';

interface Props {
  workspaceId: string;
  onSnapshotCreated?: (snapshotId: string) => void;
  onSnapshotRestored?: (snapshotId: string) => void;
}

export const SessionSnapshotManager: React.FC<Props> = ({
  workspaceId,
  onSnapshotCreated,
  onSnapshotRestored,
}) => {
  const [snapshots, setSnapshots] = useState<SnapshotMetadata[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [label, setLabel] = useState('');
  const [selectedSnapshot, setSelectedSnapshot] = useState<string | null>(null);
  const [restoreOptions, setRestoreOptions] = useState({
    includeFiles: true,
    includeTerminals: true,
    includeDebug: true,
    includeSettings: true,
    includeExtensions: true,
  });
  const serviceRef = useRef<SessionSnapshotService | null>(null);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);

  /**
   * Initialize service and load snapshots
   */
  useEffect(() => {
    const initService = async () => {
      try {
        const { getSessionSnapshotService } = await import(
          '../services/session-snapshot/service.js'
        );
        const service = await getSessionSnapshotService(workspaceId);
        serviceRef.current = service;

        // Set up listeners
        service.on('snapshot-captured', (data) => {
          console.log('[SessionSnapshotManager] Snapshot captured:', data);
          loadSnapshots();
          onSnapshotCreated?.(data.snapshotId);
        });

        service.on('snapshot-restored', (data) => {
          console.log('[SessionSnapshotManager] Snapshot restored:', data);
          if (data.success) {
            onSnapshotRestored?.(data.snapshotId);
          }
        });

        // Load initial snapshots
        await loadSnapshots();
      } catch (err) {
        const msg = `Failed to initialize: ${String(err)}`;
        console.error('[SessionSnapshotManager]', msg);
        setError(msg);
      }
    };

    initService();
  }, [workspaceId, onSnapshotCreated, onSnapshotRestored]);

  /**
   * Load snapshots from service
   */
  const loadSnapshots = async () => {
    if (!serviceRef.current) return;

    try {
      setIsLoading(true);
      const result = await serviceRef.current.listSnapshots(page, 10);
      setSnapshots(result.snapshots);
      setTotal(result.total);
      setError(null);
    } catch (err) {
      const msg = `Failed to load snapshots: ${String(err)}`;
      console.error('[SessionSnapshotManager]', msg);
      setError(msg);
    } finally {
      setIsLoading(false);
    }
  };

  /**
   * Handle create snapshot
   */
  const handleCreateSnapshot = async () => {
    if (!serviceRef.current) {
      setError('Service not initialized');
      return;
    }

    try {
      setIsSaving(true);
      setError(null);

      await serviceRef.current.captureSnapshot(label || undefined);
      setLabel('');
    } catch (err) {
      const msg = `Failed to create snapshot: ${String(err)}`;
      console.error('[SessionSnapshotManager]', msg);
      setError(msg);
    } finally {
      setIsSaving(false);
    }
  };

  /**
   * Handle restore snapshot
   */
  const handleRestoreSnapshot = async (snapshotId: string) => {
    if (!serviceRef.current) {
      setError('Service not initialized');
      return;
    }

    try {
      setIsLoading(true);
      setError(null);

      await serviceRef.current.restoreSnapshot(snapshotId, restoreOptions);
      setSelectedSnapshot(null);
    } catch (err) {
      const msg = `Failed to restore snapshot: ${String(err)}`;
      console.error('[SessionSnapshotManager]', msg);
      setError(msg);
    } finally {
      setIsLoading(false);
    }
  };

  /**
   * Handle delete snapshot
   */
  const handleDeleteSnapshot = async (snapshotId: string) => {
    if (!serviceRef.current) {
      setError('Service not initialized');
      return;
    }

    if (!confirm('Delete this snapshot?')) return;

    try {
      setError(null);
      await serviceRef.current.deleteSnapshot(snapshotId);
      await loadSnapshots();
    } catch (err) {
      const msg = `Failed to delete snapshot: ${String(err)}`;
      console.error('[SessionSnapshotManager]', msg);
      setError(msg);
    }
  };

  /**
   * Format timestamp
   */
  const formatTime = (ms: number): string => {
    const date = new Date(ms);
    return date.toLocaleString();
  };

  /**
   * Format bytes
   */
  const formatBytes = (bytes: number): string => {
    if (bytes < 1024) return `${bytes}B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)}KB`;
    return `${(bytes / (1024 * 1024)).toFixed(1)}MB`;
  };

  return (
    <div
      style={{
        background: '#1e1e1e',
        border: '1px solid #3e3e42',
        borderRadius: '4px',
        padding: '16px',
        color: '#cccccc',
        fontFamily: '"Segoe UI", Tahoma, Geneva, Verdana, sans-serif',
      }}
    >
      <div
        style={{
          marginBottom: '16px',
          paddingBottom: '12px',
          borderBottom: '1px solid #3e3e42',
        }}
      >
        <h3 style={{ margin: '0 0 12px 0', fontSize: '14px', color: '#4ec9b0' }}>
          <VscHistory style={{ marginRight: '8px', verticalAlign: 'middle' }} />
          Session Snapshots
        </h3>

        {/* Create snapshot section */}
        <div style={{ display: 'flex', gap: '8px', marginBottom: '12px' }}>
          <input
            type="text"
            placeholder="Optional label (e.g., 'Before refactor')"
            value={label}
            onChange={(e) => setLabel(e.target.value)}
            disabled={isSaving}
            style={{
              flex: 1,
              padding: '6px 8px',
              background: '#3e3e42',
              border: '1px solid #555555',
              color: '#cccccc',
              borderRadius: '2px',
              fontSize: '12px',
            }}
          />
          <button
            onClick={handleCreateSnapshot}
            disabled={isSaving || isLoading}
            style={{
              padding: '6px 12px',
              background: isSaving ? '#555555' : '#0e639c',
              border: 'none',
              color: '#ffffff',
              borderRadius: '2px',
              cursor: isSaving ? 'not-allowed' : 'pointer',
              display: 'flex',
              alignItems: 'center',
              gap: '6px',
              fontSize: '12px',
            }}
          >
            <VscSaveAll size={14} />
            {isSaving ? 'Saving...' : 'Create'}
          </button>
        </div>

        {/* Error display */}
        {error && (
          <div
            style={{
              background: '#5f2c2c',
              border: '1px solid #a1260d',
              color: '#f48771',
              padding: '8px 12px',
              borderRadius: '2px',
              marginBottom: '12px',
              fontSize: '12px',
              display: 'flex',
              justifyContent: 'space-between',
              alignItems: 'center',
            }}
          >
            <span>{error}</span>
            <button
              onClick={() => setError(null)}
              style={{
                background: 'transparent',
                border: 'none',
                color: '#f48771',
                cursor: 'pointer',
                padding: '2px',
              }}
            >
              <VscClose size={14} />
            </button>
          </div>
        )}

        {/* Loading state */}
        {isLoading && (
          <div style={{ fontSize: '12px', color: '#858585' }}>
            Loading snapshots...
          </div>
        )}
      </div>

      {/* Snapshots list */}
      <div
        style={{
          maxHeight: '400px',
          overflowY: 'auto',
          marginBottom: '12px',
        }}
      >
        {snapshots.length === 0 ? (
          <div
            style={{
              fontSize: '12px',
              color: '#858585',
              textAlign: 'center',
              padding: '24px 12px',
            }}
          >
            No snapshots yet. Create one to save session state.
          </div>
        ) : (
          snapshots.map((snap) => (
            <div
              key={snap.id}
              style={{
                background: selectedSnapshot === snap.id ? '#2d2d30' : 'transparent',
                border:
                  selectedSnapshot === snap.id ? '1px solid #4ec9b0' : '1px solid #3e3e42',
                borderRadius: '2px',
                padding: '10px 12px',
                marginBottom: '8px',
                cursor: 'pointer',
                transition: 'all 0.2s ease',
              }}
              onClick={() => setSelectedSnapshot(snap.id)}
            >
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'start' }}>
                <div style={{ flex: 1 }}>
                  <div style={{ fontSize: '12px', fontWeight: 'bold', marginBottom: '4px' }}>
                    {snap.label || `Snapshot #${snap.version}`}
                  </div>
                  <div style={{ fontSize: '11px', color: '#858585' }}>
                    {formatTime(snap.createdAt)} • {snap.fileCount} files • {snap.terminalCount} terminals
                  </div>
                  <div style={{ fontSize: '11px', color: '#858585', marginTop: '4px' }}>
                    Size: {formatBytes(snap.size)} • Restore: {snap.estimatedRestoreTimeMs}ms
                  </div>
                </div>
                <div style={{ display: 'flex', gap: '6px' }}>
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      handleRestoreSnapshot(snap.id);
                    }}
                    disabled={isLoading}
                    style={{
                      padding: '4px 8px',
                      background: '#0e639c',
                      border: 'none',
                      color: '#ffffff',
                      borderRadius: '2px',
                      cursor: 'pointer',
                      fontSize: '11px',
                    }}
                  >
                    Restore
                  </button>
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      handleDeleteSnapshot(snap.id);
                    }}
                    style={{
                      padding: '4px 8px',
                      background: '#5c2e2e',
                      border: 'none',
                      color: '#f48771',
                      borderRadius: '2px',
                      cursor: 'pointer',
                      fontSize: '11px',
                    }}
                  >
                    <VscTrash size={12} />
                  </button>
                </div>
              </div>
            </div>
          ))
        )}
      </div>

      {/* Pagination */}
      {total > 10 && (
        <div
          style={{
            display: 'flex',
            justifyContent: 'space-between',
            alignItems: 'center',
            fontSize: '12px',
            color: '#858585',
            borderTop: '1px solid #3e3e42',
            paddingTop: '8px',
          }}
        >
          <span>
            Page {page} of {Math.ceil(total / 10)}
          </span>
          <div style={{ display: 'flex', gap: '4px' }}>
            <button
              onClick={() => setPage(Math.max(1, page - 1))}
              disabled={page === 1}
              style={{
                padding: '2px 8px',
                background: page === 1 ? '#3e3e42' : '#0e639c',
                border: 'none',
                color: '#ffffff',
                cursor: page === 1 ? 'not-allowed' : 'pointer',
              }}
            >
              Prev
            </button>
            <button
              onClick={() => setPage(page + 1)}
              disabled={page >= Math.ceil(total / 10)}
              style={{
                padding: '2px 8px',
                background: page >= Math.ceil(total / 10) ? '#3e3e42' : '#0e639c',
                border: 'none',
                color: '#ffffff',
                cursor: page >= Math.ceil(total / 10) ? 'not-allowed' : 'pointer',
              }}
            >
              Next
            </button>
          </div>
        </div>
      )}

      {/* Restore options (when snapshot selected) */}
      {selectedSnapshot && (
        <div
          style={{
            background: '#2d2d30',
            border: '1px solid #3e3e42',
            borderRadius: '2px',
            padding: '12px',
            marginTop: '12px',
          }}
        >
          <div style={{ fontSize: '12px', marginBottom: '8px', fontWeight: 'bold' }}>
            Restore Options
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
            {(
              [
                ['includeFiles', 'Files'],
                ['includeTerminals', 'Terminals'],
                ['includeDebug', 'Debug Sessions'],
                ['includeSettings', 'Settings'],
                ['includeExtensions', 'Extensions'],
              ] as const
            ).map(([key, label]) => (
              <label key={key} style={{ display: 'flex', alignItems: 'center', gap: '6px', fontSize: '12px', cursor: 'pointer' }}>
                <input
                  type="checkbox"
                  checked={restoreOptions[key]}
                  onChange={(e) =>
                    setRestoreOptions({ ...restoreOptions, [key]: e.target.checked })
                  }
                  style={{ cursor: 'pointer' }}
                />
                {label}
              </label>
            ))}
          </div>
        </div>
      )}
    </div>
  );
};

export default SessionSnapshotManager;
