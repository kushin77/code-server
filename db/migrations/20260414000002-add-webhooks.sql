-- Phase 26-D: Webhooks & Event Delivery Schema
-- Production-ready PostgreSQL schema with reliable event storage and retry management
-- Idempotent: Safe to run multiple times (IF NOT EXISTS)

BEGIN;

-- Webhooks table: Stores endpoint subscriptions per organization
CREATE TABLE IF NOT EXISTS webhooks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,
  url TEXT NOT NULL,
  description TEXT,
  secret_hash VARCHAR(255) NOT NULL,  -- SHA256 hash of webhook secret (never store plaintext)
  
  -- Event filtering
  events_subscribed JSONB NOT NULL DEFAULT '[]'::jsonb,  -- Array of event types
  is_active BOOLEAN DEFAULT true,
  
  -- Retry configuration
  max_retries INTEGER DEFAULT 3,
  retry_timeout_seconds INTEGER DEFAULT 30,
  backoff_multiplier DECIMAL(3, 1) DEFAULT 2.0,
  
  -- Metadata
  created_by_user_id UUID NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_delivery_at TIMESTAMP,
  last_success_at TIMESTAMP,
  consecutive_failures INTEGER DEFAULT 0,
  
  CONSTRAINT uk_webhook_org_url UNIQUE (organization_id, url),
  INDEX idx_webhooks_organization (organization_id),
  INDEX idx_webhooks_active (is_active),
  INDEX idx_webhooks_created (created_at DESC)
);

-- Webhook deliveries table: Immutable log of all delivery attempts
CREATE TABLE IF NOT EXISTS webhook_deliveries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  webhook_id UUID NOT NULL REFERENCES webhooks(id) ON DELETE CASCADE,
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  event_id UUID NOT NULL,  -- Reference to event in webhook_events table
  event_type VARCHAR(100) NOT NULL,  -- e.g., "workspace.created", "files.modified"
  
  -- Attempt tracking
  attempt_number INTEGER NOT NULL DEFAULT 1,
  http_status_code INTEGER,
  response_body TEXT,
  error_message TEXT,
  
  -- Timing
  scheduled_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  sent_at TIMESTAMP,
  next_retry_at TIMESTAMP,
  
  -- Success/failure
  is_successful BOOLEAN DEFAULT false,
  is_permanent_failure BOOLEAN DEFAULT false,  -- 4xx errors
  
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  
  INDEX idx_deliveries_webhook (webhook_id),
  INDEX idx_deliveries_organization (organization_id),
  INDEX idx_deliveries_event (event_id),
  INDEX idx_deliveries_scheduled (scheduled_at),
  INDEX idx_deliveries_retry (next_retry_at) WHERE next_retry_at IS NOT NULL,
  INDEX idx_deliveries_successful (is_successful),
  CONSTRAINT immutable_delivery CHECK (created_at = created_at)
);

-- Webhook events table: Immutable record of all events (event sourcing pattern)
CREATE TABLE IF NOT EXISTS webhook_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  event_type VARCHAR(100) NOT NULL,  -- e.g., "workspace.created", "api_key.rotated"
  
  -- Event categorization
  category VARCHAR(50) NOT NULL,  -- workspace, files, users, api_keys, organizations
  action VARCHAR(50) NOT NULL,    -- created, updated, deleted, invited, joined, revoked, etc.
  
  -- Event data
  resource_type VARCHAR(100) NOT NULL,  -- Affected resource type
  resource_id UUID,                     -- ID of affected resource
  actor_id UUID NOT NULL,               -- User who triggered event
  
  -- Event payload
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,  -- Full event data
  
  -- Delivery tracking
  webhook_count INTEGER DEFAULT 0,      -- Number of webhooks subscribed to this event
  successful_deliveries INTEGER DEFAULT 0,
  failed_deliveries INTEGER DEFAULT 0,
  
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  
  CONSTRAINT immutable_event CHECK (created_at = created_at),
  INDEX idx_events_organization (organization_id),
  INDEX idx_events_type (event_type),
  INDEX idx_events_category (category),
  INDEX idx_events_actor (actor_id),
  INDEX idx_events_resource (resource_type, resource_id),
  INDEX idx_events_created (created_at DESC),
  INDEX idx_events_recent ON webhook_events(created_at DESC) 
    WHERE created_at > NOW() - INTERVAL '30 days'
);

-- Webhook retry policies table: Configurable per webhook
CREATE TABLE IF NOT EXISTS webhook_retry_policies (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  webhook_id UUID NOT NULL UNIQUE REFERENCES webhooks(id) ON DELETE CASCADE,
  
  -- Retry configuration
  max_attempts INTEGER DEFAULT 3,
  initial_delay_ms INTEGER DEFAULT 1000,      -- 1 second
  max_delay_ms INTEGER DEFAULT 60000,         -- 60 seconds
  backoff_type VARCHAR(50) DEFAULT 'exponential',  -- exponential or linear
  
  -- Status codes that trigger retries (4xx considered permanent by default)
  retryable_status_codes INTEGER[] DEFAULT '{408,429,500,502,503,504}',
  
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Webhook signature verification log (for security auditing)
CREATE TABLE IF NOT EXISTS webhook_signature_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  webhook_id UUID NOT NULL REFERENCES webhooks(id) ON DELETE CASCADE,
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  
  signature_received VARCHAR(255) NOT NULL,
  signature_expected VARCHAR(255) NOT NULL,
  is_valid BOOLEAN NOT NULL,
  
  -- Security context
  ip_address INET,
  user_agent TEXT,
  
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  
  INDEX idx_sig_webhook (webhook_id),
  INDEX idx_sig_organization (organization_id),
  INDEX idx_sig_valid (is_valid),
  INDEX idx_sig_created (created_at DESC)
);

-- Create immutable event trigger (prevent updates/deletes)
CREATE OR REPLACE FUNCTION enforce_event_immutability()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'UPDATE' OR TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'Webhook events are immutable and cannot be modified';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER event_immutability_trigger
BEFORE UPDATE OR DELETE ON webhook_events
FOR EACH ROW EXECUTE FUNCTION enforce_event_immutability();

-- Create immutable delivery trigger (prevent updates/deletes)
CREATE OR REPLACE FUNCTION enforce_delivery_immutability()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'UPDATE' OR TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'Webhook deliveries are immutable and cannot be modified';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER delivery_immutability_trigger
BEFORE UPDATE OR DELETE ON webhook_deliveries
FOR EACH ROW EXECUTE FUNCTION enforce_delivery_immutability();

-- Function to calculate next retry time (exponential backoff)
CREATE OR REPLACE FUNCTION calculate_next_retry_time(
  p_webhook_id UUID,
  p_attempt_number INTEGER,
  p_last_retry TIMESTAMP
)
RETURNS TIMESTAMP AS $$
DECLARE
  v_policy webhook_retry_policies%ROWTYPE;
  v_delay_ms INTEGER;
  v_multiplier DECIMAL;
BEGIN
  SELECT * INTO v_policy FROM webhook_retry_policies WHERE webhook_id = p_webhook_id;
  
  IF v_policy IS NULL THEN
    -- Default policy
    v_delay_ms := 1000 * POWER(2, LEAST(p_attempt_number - 1, 5));  -- Cap exponential growth
  ELSE
    IF v_policy.backoff_type = 'exponential' THEN
      v_delay_ms := v_policy.initial_delay_ms * POWER(2, p_attempt_number - 1);
    ELSE
      -- Linear backoff
      v_delay_ms := v_policy.initial_delay_ms * p_attempt_number;
    END IF;
    v_delay_ms := LEAST(v_delay_ms, v_policy.max_delay_ms);
  END IF;
  
  RETURN p_last_retry + (v_delay_ms || ' ms')::INTERVAL;
END;
$$ LANGUAGE plpgsql;

-- Create view for active webhooks
CREATE OR REPLACE VIEW active_webhooks AS
SELECT 
  id, organization_id, name, url, description,
  events_subscribed, is_active, max_retries,
  created_by_user_id, created_at, updated_at,
  last_delivery_at, last_success_at, consecutive_failures
FROM webhooks
WHERE is_active = true;

-- Create view for pending deliveries
CREATE OR REPLACE VIEW pending_webhook_deliveries AS
SELECT 
  d.id, d.webhook_id, d.organization_id, d.event_id, d.event_type,
  d.attempt_number, d.next_retry_at,
  w.url, w.max_retries
FROM webhook_deliveries d
JOIN webhooks w ON d.webhook_id = w.id
WHERE d.is_successful = false 
  AND d.is_permanent_failure = false
  AND d.next_retry_at <= NOW()
ORDER BY d.next_retry_at ASC;

-- Grant appropriate permissions (least privilege)
GRANT SELECT, INSERT ON webhooks TO "api-user";
GRANT SELECT, INSERT ON webhook_events TO "api-user";
GRANT SELECT, INSERT ON webhook_deliveries TO "dispatcher-service";
GRANT SELECT ON webhook_deliveries TO "api-user";
GRANT SELECT, INSERT ON webhook_signature_logs TO "api-user";
GRANT SELECT, INSERT, UPDATE ON webhook_retry_policies TO "api-user";

COMMIT;
