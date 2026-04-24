#!/usr/bin/env node
// @file        apps/backend/src/services/failover/index.ts
// @module      services/failover
// @description Failover management service exports
//

export {
  FailoverWebhookService,
  type AlertPayload,
  type Alert,
  type FailoverEvent,
  type FailoverConfig,
} from './failover-webhook-service'
