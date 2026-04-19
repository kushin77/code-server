-- ════════════════════════════════════════════════════════════════════════════
-- Session Management Schema (#752)
-- Per-user/per-session isolation for code-server runtime contexts
-- ════════════════════════════════════════════════════════════════════════════

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Sessions table: tracks isolated runtime contexts per user
CREATE TABLE IF NOT EXISTS sessions (
  session_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL,
  username VARCHAR(32) NOT NULL,
  email VARCHAR(255) NOT NULL,
  
  -- Docker container mapping
  container_id VARCHAR(64),
  container_name VARCHAR(128) NOT NULL UNIQUE,
  container_port INT NOT NULL UNIQUE,
  base_image_id VARCHAR(255) NOT NULL,
  
  -- Lifecycle
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  expires_at TIMESTAMP NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'creating'
    CHECK (status IN ('creating', 'running', 'paused', 'terminated')),
  last_activity TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  
  -- Resource quotas (JSON)
  quotas JSONB DEFAULT '{"cpuLimit": "2.0", "memoryLimit": "4g", "storageLimit": "50g"}',
  
  -- Metadata
  created_by_ip INET,
  created_by_user_agent TEXT,
  
  -- Indexes for common queries
  CONSTRAINT session_user_fk FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX idx_sessions_user_id ON sessions(user_id);
CREATE INDEX idx_sessions_username ON sessions(username);
CREATE INDEX idx_sessions_status ON sessions(status);
CREATE INDEX idx_sessions_expires_at ON sessions(expires_at);
CREATE INDEX idx_sessions_container_port ON sessions(container_port);

-- Session activity log: audit trail for security/debugging
CREATE TABLE IF NOT EXISTS session_activity (
  activity_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  session_id UUID NOT NULL REFERENCES sessions(session_id) ON DELETE CASCADE,
  user_id UUID NOT NULL,
  
  -- Activity details
  activity_type VARCHAR(50) NOT NULL
    CHECK (activity_type IN ('login', 'logout', 'file_access', 'terminal_exec', 'extension_install', 'keep_alive', 'timeout')),
  resource_path TEXT,
  command_executed TEXT,
  exit_code INT,
  
  -- Metadata
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  client_ip INET,
  user_agent TEXT,
  details JSONB
);

CREATE INDEX idx_session_activity_session ON session_activity(session_id);
CREATE INDEX idx_session_activity_user ON session_activity(user_id);
CREATE INDEX idx_session_activity_created ON session_activity(created_at);
CREATE INDEX idx_session_activity_type ON session_activity(activity_type);

-- Session resource usage: track CPU/memory/storage per session
CREATE TABLE IF NOT EXISTS session_resource_usage (
  usage_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  session_id UUID NOT NULL REFERENCES sessions(session_id) ON DELETE CASCADE,
  
  -- Resource snapshot
  cpu_percent NUMERIC(5, 2),
  memory_bytes BIGINT,
  memory_limit_bytes BIGINT,
  disk_usage_bytes BIGINT,
  disk_limit_bytes BIGINT,
  
  -- Process counts
  running_processes INT,
  open_files INT,
  
  -- Timing
  recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  sample_duration_ms INT
);

CREATE INDEX idx_resource_usage_session ON session_resource_usage(session_id);
CREATE INDEX idx_resource_usage_recorded ON session_resource_usage(recorded_at);

-- Session isolation policies: define access controls between sessions
CREATE TABLE IF NOT EXISTS session_policies (
  policy_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  session_id UUID NOT NULL REFERENCES sessions(session_id) ON DELETE CASCADE,
  
  -- Policy type
  policy_type VARCHAR(50) NOT NULL
    CHECK (policy_type IN ('filesystem', 'network', 'process', 'extension', 'terminal')),
  
  -- Enforcement rules
  action VARCHAR(20) NOT NULL DEFAULT 'deny'
    CHECK (action IN ('allow', 'deny', 'audit')),
  resource_pattern VARCHAR(512),
  scope VARCHAR(50) DEFAULT 'session'
    CHECK (scope IN ('session', 'user', 'organization')),
  
  -- Lifecycle
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  expires_at TIMESTAMP,
  active BOOLEAN DEFAULT true,
  
  -- Metadata
  reason TEXT,
  applied_by UUID REFERENCES users(id)
);

CREATE INDEX idx_policies_session ON session_policies(session_id);
CREATE INDEX idx_policies_type ON session_policies(policy_type);
CREATE INDEX idx_policies_active ON session_policies(active);

-- View: active user sessions
CREATE OR REPLACE VIEW active_user_sessions AS
SELECT
  s.session_id,
  s.user_id,
  s.username,
  s.email,
  s.status,
  s.container_name,
  s.container_port,
  s.created_at,
  s.expires_at,
  s.last_activity,
  EXTRACT(EPOCH FROM (s.expires_at - CURRENT_TIMESTAMP)) AS seconds_remaining,
  (SELECT COUNT(*) FROM session_activity sa WHERE sa.session_id = s.session_id) AS activity_count,
  (SELECT MAX(recorded_at) FROM session_resource_usage sru WHERE sru.session_id = s.session_id) AS last_resource_sample
FROM sessions s
WHERE s.status = 'running'
  AND s.expires_at > CURRENT_TIMESTAMP
ORDER BY s.last_activity DESC;

-- View: session isolation compliance
CREATE OR REPLACE VIEW session_isolation_audit AS
SELECT
  s.session_id,
  s.username,
  s.container_name,
  s.status,
  COUNT(DISTINCT sp.policy_id) AS active_policies,
  COUNT(DISTINCT CASE WHEN sp.policy_type = 'filesystem' THEN sp.policy_id END) AS filesystem_policies,
  COUNT(DISTINCT CASE WHEN sp.policy_type = 'network' THEN sp.policy_id END) AS network_policies,
  COUNT(DISTINCT CASE WHEN sp.policy_type = 'process' THEN sp.policy_id END) AS process_policies,
  MAX(CASE WHEN sp.active = false THEN sp.expires_at END) AS oldest_inactive_policy
FROM sessions s
LEFT JOIN session_policies sp ON sp.session_id = s.session_id
WHERE s.status IN ('running', 'paused')
GROUP BY s.session_id, s.username, s.container_name, s.status
ORDER BY s.created_at DESC;
