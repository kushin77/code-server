// @file        apps/frontend/src/extensions/pagerduty-incidents-panel.tsx
// @module      extensions/pagerduty-incidents-panel
// @description React panel for PagerDuty incident management

import React, { useState, useEffect } from 'react';
import * as vscode from 'vscode';

interface IncidentData {
  id: string;
  incident_number: number;
  title: string;
  status: 'triggered' | 'acknowledged' | 'resolved';
  urgency: 'high' | 'low';
  created_at: string;
  assignee?: string;
  service: string;
}

interface IncidentStats {
  triggered: number;
  acknowledged: number;
  resolved: number;
}

/**
 * PagerDuty Incidents Panel
 *
 * Provides:
 * - Real-time incident list
 * - Quick status updates
 * - Acknowledgment and resolution
 * - Incident details and timeline
 * - On-call schedule visibility
 * - Incident creation
 */
export const PagerDutyIncidentsPanel: React.FC = () => {
  const [incidents, setIncidents] = useState<IncidentData[]>([]);
  const [stats, setStats] = useState<IncidentStats>({ triggered: 0, acknowledged: 0, resolved: 0 });
  const [loading, setLoading] = useState(true);
  const [filterStatus, setFilterStatus] = useState<string>('triggered');
  const [selectedIncident, setSelectedIncident] = useState<IncidentData | null>(null);

  useEffect(() => {
    loadIncidents();
    const interval = setInterval(loadIncidents, 15000); // Refresh every 15 seconds

    return () => clearInterval(interval);
  }, [filterStatus]);

  const loadIncidents = async (): Promise<void> => {
    try {
      setLoading(true);

      const response = await fetch(
        `http://localhost:3100/api/incidents?status=${filterStatus}&limit=20`
      );
      const data = await response.json();

      setIncidents(data.incidents || []);
      setStats(data.stats || { triggered: 0, acknowledged: 0, resolved: 0 });
    } catch (error) {
      vscode.window.showErrorMessage(
        `Failed to load incidents: ${error instanceof Error ? error.message : 'Unknown error'}`
      );
    } finally {
      setLoading(false);
    }
  };

  const acknowledgeIncident = async (incidentId: string): Promise<void> => {
    try {
      const response = await fetch(
        `http://localhost:3100/api/incidents/${incidentId}/acknowledge`,
        { method: 'POST' }
      );

      if (response.ok) {
        await loadIncidents();
        vscode.window.showInformationMessage('Incident acknowledged');
      }
    } catch (error) {
      vscode.window.showErrorMessage(
        `Failed to acknowledge: ${error instanceof Error ? error.message : 'Unknown error'}`
      );
    }
  };

  const resolveIncident = async (incidentId: string): Promise<void> => {
    try {
      const response = await fetch(
        `http://localhost:3100/api/incidents/${incidentId}/resolve`,
        { method: 'POST' }
      );

      if (response.ok) {
        await loadIncidents();
        vscode.window.showInformationMessage('Incident resolved');
      }
    } catch (error) {
      vscode.window.showErrorMessage(
        `Failed to resolve: ${error instanceof Error ? error.message : 'Unknown error'}`
      );
    }
  };

  const getStatusIcon = (status: string): string => {
    switch (status) {
      case 'triggered':
        return '🚨';
      case 'acknowledged':
        return '👀';
      case 'resolved':
        return '✅';
      default:
        return '●';
    }
  };

  const getStatusColor = (status: string): string => {
    switch (status) {
      case 'triggered':
        return '#ff0000';
      case 'acknowledged':
        return '#ffff00';
      case 'resolved':
        return '#00ff00';
      default:
        return '#808080';
    }
  };

  const getUrgencyIcon = (urgency: string): string => {
    return urgency === 'high' ? '🔴' : '🟡';
  };

  return (
    <div style={{ padding: '16px', fontFamily: 'var(--vscode-font-family)' }}>
      <div style={{ marginBottom: '16px' }}>
        <h2 style={{ marginTop: 0 }}>PagerDuty Incidents</h2>

        <div
          style={{
            display: 'grid',
            gridTemplateColumns: '1fr 1fr 1fr',
            gap: '8px',
            marginBottom: '16px',
          }}
        >
          <div
            style={{
              padding: '12px',
              background: 'var(--vscode-editor-background)',
              border: '1px solid var(--vscode-editor-lineHighlightBorder)',
              borderRadius: '4px',
              textAlign: 'center',
            }}
          >
            <div style={{ fontSize: '18px', fontWeight: 'bold', color: '#ff6666' }}>
              {stats.triggered}
            </div>
            <div style={{ fontSize: '12px', opacity: 0.7 }}>Triggered</div>
          </div>

          <div
            style={{
              padding: '12px',
              background: 'var(--vscode-editor-background)',
              border: '1px solid var(--vscode-editor-lineHighlightBorder)',
              borderRadius: '4px',
              textAlign: 'center',
            }}
          >
            <div style={{ fontSize: '18px', fontWeight: 'bold', color: '#ffff66' }}>
              {stats.acknowledged}
            </div>
            <div style={{ fontSize: '12px', opacity: 0.7 }}>Acknowledged</div>
          </div>

          <div
            style={{
              padding: '12px',
              background: 'var(--vscode-editor-background)',
              border: '1px solid var(--vscode-editor-lineHighlightBorder)',
              borderRadius: '4px',
              textAlign: 'center',
            }}
          >
            <div style={{ fontSize: '18px', fontWeight: 'bold', color: '#66ff66' }}>
              {stats.resolved}
            </div>
            <div style={{ fontSize: '12px', opacity: 0.7 }}>Resolved</div>
          </div>
        </div>

        <div style={{ display: 'flex', gap: '8px', marginBottom: '12px' }}>
          {['triggered', 'acknowledged', 'resolved'].map((status) => (
            <button
              key={status}
              onClick={() => setFilterStatus(status)}
              style={{
                padding: '6px 12px',
                background:
                  filterStatus === status
                    ? 'var(--vscode-button-background)'
                    : 'var(--vscode-button-secondaryBackground)',
                color:
                  filterStatus === status
                    ? 'var(--vscode-button-foreground)'
                    : 'var(--vscode-button-secondaryForeground)',
                border: 'none',
                borderRadius: '4px',
                cursor: 'pointer',
                textTransform: 'capitalize',
              }}
            >
              {status}
            </button>
          ))}

          <button
            onClick={loadIncidents}
            style={{
              padding: '6px 12px',
              background: 'var(--vscode-button-secondaryBackground)',
              color: 'var(--vscode-button-secondaryForeground)',
              border: 'none',
              borderRadius: '4px',
              cursor: 'pointer',
              marginLeft: 'auto',
            }}
          >
            {loading ? 'Loading...' : 'Refresh'}
          </button>
        </div>
      </div>

      {loading ? (
        <div style={{ color: 'var(--vscode-foreground)', opacity: 0.7 }}>Loading incidents...</div>
      ) : incidents.length === 0 ? (
        <div style={{ color: 'var(--vscode-foreground)', opacity: 0.7 }}>No incidents</div>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
          {incidents.map((incident) => (
            <div
              key={incident.id}
              style={{
                padding: '12px',
                background: 'var(--vscode-editor-background)',
                border: `2px solid ${getStatusColor(incident.status)}`,
                borderRadius: '4px',
                cursor: 'pointer',
              }}
              onClick={() => setSelectedIncident(incident)}
            >
              <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '8px' }}>
                <span>{getStatusIcon(incident.status)}</span>
                <span>{getUrgencyIcon(incident.urgency)}</span>
                <span style={{ fontWeight: 'bold' }}>{incident.title}</span>
                <span style={{ marginLeft: 'auto', fontSize: '12px', opacity: 0.7 }}>
                  #{incident.incident_number}
                </span>
              </div>

              <div style={{ fontSize: '12px', opacity: 0.7 }}>
                <div>{incident.service}</div>
                <div>Created: {new Date(incident.created_at).toLocaleString()}</div>
                {incident.assignee && <div>Assigned to: {incident.assignee}</div>}
              </div>

              {filterStatus === 'triggered' && (
                <div style={{ display: 'flex', gap: '8px', marginTop: '8px' }}>
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      acknowledgeIncident(incident.id);
                    }}
                    style={{
                      padding: '4px 8px',
                      fontSize: '12px',
                      background: 'var(--vscode-button-background)',
                      color: 'var(--vscode-button-foreground)',
                      border: 'none',
                      borderRadius: '3px',
                      cursor: 'pointer',
                    }}
                  >
                    Acknowledge
                  </button>
                </div>
              )}

              {filterStatus === 'acknowledged' && (
                <div style={{ display: 'flex', gap: '8px', marginTop: '8px' }}>
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      resolveIncident(incident.id);
                    }}
                    style={{
                      padding: '4px 8px',
                      fontSize: '12px',
                      background: 'var(--vscode-button-background)',
                      color: 'var(--vscode-button-foreground)',
                      border: 'none',
                      borderRadius: '3px',
                      cursor: 'pointer',
                    }}
                  >
                    Resolve
                  </button>
                </div>
              )}
            </div>
          ))}
        </div>
      )}

      {selectedIncident && (
        <div
          style={{
            marginTop: '16px',
            padding: '12px',
            background: 'var(--vscode-editor-background)',
            border: '1px solid var(--vscode-editor-lineHighlightBorder)',
            borderRadius: '4px',
          }}
        >
          <h3>{selectedIncident.title}</h3>
          <div>Status: {selectedIncident.status}</div>
          <div>Urgency: {selectedIncident.urgency}</div>
          <button
            onClick={() => setSelectedIncident(null)}
            style={{
              marginTop: '8px',
              padding: '4px 8px',
              background: 'var(--vscode-button-secondaryBackground)',
              color: 'var(--vscode-button-secondaryForeground)',
              border: 'none',
              borderRadius: '3px',
              cursor: 'pointer',
            }}
          >
            Close
          </button>
        </div>
      )}
    </div>
  );
};

export default PagerDutyIncidentsPanel;
