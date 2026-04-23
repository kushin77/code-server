#!/usr/bin/env node
// @file        apps/backend/src/services/conflict-prediction/index.ts
// @module      collaboration/conflict-prediction
// @description Exports for ConflictPredictionService
// @owner       collab-services
// @status      active

// Service exports
export {
  ConflictPredictionService,
  createConflictPredictionService,
  getConflictPredictionService,
} from './conflict-prediction-service';

// Type exports
export type {
  ActiveEdit,
  ConflictAlert,
  MergePreview,
  RiskScoreFactors,
  ConflictMetrics,
  ConflictPredictionConfig,
  ConflictServiceStats,
  ActivityReportResult,
  ConflictQueryOptions,
  ConflictQueryResult,
} from './types';
