-- ════════════════════════════════════════════════════════════════════════════
-- Incident Correlation & Error Budget Schema (#1061)
-- Tracks collaboration platform SLO breaches and correlates with infrastructure events
-- ════════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────
-- Collaboration SLO Metrics
-- Tracks latency, disconnect rate, sync failure rate
-- ─────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS collaboration_slos (
  slo_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  metric_type VARCHAR(32) NOT NULL
    CHECK (metric_type IN ('latency', 'disconnect_rate', 'sync_failure_rate')),
  
  -- SLO thresholds
  threshold FLOAT NOT NULL,  -- e.g., 0.95 for 95% success, 500 for 500ms latency
  threshold_unit VARCHAR(16),  -- 'percentage', 'milliseconds', 'count'
  
  -- Measurement window
  window_size_seconds INT NOT NULL DEFAULT 300,  -- 5 min default
  
  -- Current state
  current_value FLOAT NOT NULL,
  status VARCHAR(16) NOT NULL DEFAULT 'healthy'
    CHECK (status IN ('healthy', 'degraded', 'breached')),
  
  breach_start_time TIMESTAMP,
  breach_severity VARCHAR(16) DEFAULT 'medium'
    CHECK (breach_severity IN ('low', 'medium', 'high', 'critical')),
  
  -- Metadata
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  
  CONSTRAINT unique_slo_metric UNIQUE (metric_type)
);

-- ─────────────────────────────────────────────────────────────────────────
-- Infrastructure Change Events
-- Captures deployments, config changes, service restarts
-- ─────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS change_events (
  event_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  
  -- Event classification
  event_type VARCHAR(32) NOT NULL
    CHECK (event_type IN ('deployment', 'config_change', 'service_restart', 'resource_spike', 'database_migration')),
  
  -- Event details
  service_name VARCHAR(64) NOT NULL,  -- e.g., 'matrix-homeserver', 'session-broker', 'oauth2-proxy'
  description TEXT NOT NULL,
  
  -- Change metadata
  change_reason VARCHAR(256),  -- e.g., 'bug fix', 'performance tuning', 'config rollback'
  changed_by VARCHAR(255),  -- git user, CI system, manual admin
  
  -- Timing
  event_timestamp TIMESTAMP NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  
  -- Loki label set for correlation
  loki_labels JSONB NOT NULL,  -- e.g., {"service": "matrix", "version": "1.2.3", "env": "prod"}
  
  -- Link to potential incident (if correlated)
  incident_id UUID REFERENCES incidents(incident_id) ON DELETE SET NULL
);

-- ─────────────────────────────────────────────────────────────────────────
-- Incidents: SLO Breach Reports
-- Stores automatically generated incident summaries
-- ─────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS incidents (
  incident_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  
  -- Incident classification
  slo_id UUID NOT NULL REFERENCES collaboration_slos(slo_id),
  metric_type VARCHAR(32) NOT NULL,  -- e.g., 'latency', 'disconnect_rate'
  
  -- Timing and severity
  breach_start_time TIMESTAMP NOT NULL,
  breach_end_time TIMESTAMP,
  detection_time TIMESTAMP NOT NULL,  -- when we first detected it
  time_to_detection_seconds INT,  -- metric: how fast did we notice?
  
  severity VARCHAR(16) NOT NULL DEFAULT 'medium'
    CHECK (severity IN ('low', 'medium', 'high', 'critical')),
  status VARCHAR(16) NOT NULL DEFAULT 'detected'
    CHECK (status IN ('detected', 'acknowledged', 'investigating', 'mitigated', 'resolved')),
  
  -- SLO details
  metric_value FLOAT NOT NULL,  -- actual measured value
  threshold_value FLOAT NOT NULL,  -- SLO threshold
  breach_percentage FLOAT,  -- how much over threshold? (100 = threshold breached)
  
  -- Correlated change events
  correlated_event_ids UUID[],  -- array of change_event UUIDs within ±10 min
  correlation_count INT DEFAULT 0,
  correlation_confidence FLOAT,  -- 0.0-1.0: how confident is the correlation?
  
  -- Auto-generated incident summary
  auto_summary TEXT NOT NULL,  -- e.g., "Sync latency spiked 23% at 14:32 UTC, 4 min after docker-compose restart"
  timeline_json JSONB,  -- structured timeline with events
  
  -- Integration
  matrix_room_id VARCHAR(255),  -- #incidents room ID in Matrix
  matrix_message_id VARCHAR(255),  -- message posted to Matrix
  posted_to_matrix BOOLEAN DEFAULT false,
  
  -- Post-mortem  
  root_cause_analysis TEXT,
  remediation_steps TEXT,
  mitigation_successful BOOLEAN,
  
  -- Metadata
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  created_by VARCHAR(255)  -- 'correlation-engine' or manual entry
);

-- ─────────────────────────────────────────────────────────────────────────
-- Incident Timeline Events (for detailed post-mortem)
-- ─────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS incident_timeline_events (
  timeline_event_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  incident_id UUID NOT NULL REFERENCES incidents(incident_id) ON DELETE CASCADE,
  
  event_time TIMESTAMP NOT NULL,
  event_type VARCHAR(64) NOT NULL,  -- 'slo_breach_start', 'slo_breach_end', 'change_event', 'manual_annotation'
  
  description TEXT NOT NULL,
  
  -- Link to contributing event if applicable
  change_event_id UUID REFERENCES change_events(event_id) ON DELETE SET NULL,
  
  -- Metadata
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ─────────────────────────────────────────────────────────────────────────
-- Indexes for performance
-- ─────────────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_collaboration_slos_metric_type 
  ON collaboration_slos(metric_type);

CREATE INDEX IF NOT EXISTS idx_collaboration_slos_status 
  ON collaboration_slos(status);

CREATE INDEX IF NOT EXISTS idx_change_events_timestamp 
  ON change_events(event_timestamp DESC);

CREATE INDEX IF NOT EXISTS idx_change_events_service_type 
  ON change_events(service_name, event_type);

CREATE INDEX IF NOT EXISTS idx_incidents_slo_id 
  ON incidents(slo_id);

CREATE INDEX IF NOT EXISTS idx_incidents_breach_time 
  ON incidents(breach_start_time DESC);

CREATE INDEX IF NOT EXISTS idx_incidents_status 
  ON incidents(status);

CREATE INDEX IF NOT EXISTS idx_incidents_matrix_posted 
  ON incidents(posted_to_matrix) WHERE posted_to_matrix = false;

CREATE INDEX IF NOT EXISTS idx_incident_timeline_incident_id 
  ON incident_timeline_events(incident_id);

CREATE INDEX IF NOT EXISTS idx_incident_timeline_event_time 
  ON incident_timeline_events(event_time DESC);
