#!/usr/bin/env node
// @file        apps/backend/src/services/communication-optimization/types.ts
// @module      collaboration/communication-optimization
// @description Type definitions for CommunicationOptimizationEngine
// @owner       collab-6.3
// @status      active

/**
 * Communication pattern metrics for a team
 */
export interface CommunicationMetrics {
  teamId: string;
  syncAsyncRatio: number; // 0-100: 0=all async, 100=all sync
  avgResponseTime: number; // minutes
  meetingEffectiveness: number; // 0-100
  asyncCommunicationAdoption: number; // 0-100
  decisionVelocity: number; // hours from proposal to decision
  notificationOverloadScore: number; // 0-100
  communicationLatencyP50: number; // milliseconds
  communicationLatencyP99: number; // milliseconds
  channelFragmentation: number; // 0-100: 0=organized, 100=chaotic
  documentationAdherence: number; // 0-100
  meetingHeaviness: number; // meetings per person per day
  contextSwitchingFrequency: number; // switches per hour
  timestamp: Date;
}

/**
 * Analysis of a single meeting
 */
export interface MeetingAnalysis {
  meetingId: string;
  teamId: string;
  title: string;
  duration: number; // minutes
  attendeeCount: number;
  attendees: string[]; // user IDs
  startTime: Date;
  endTime: Date;
  necessityScore: number; // 0-100: how necessary was this meeting
  couldBeAsync: boolean;
  decisionMade: boolean;
  actionItems: ActionItem[];
  effectivenessScore: number; // 0-100: value delivered per minute
  attendeeEngagement: number; // 0-100: participation level
  hasAgenda: boolean;
  hasNotes: boolean;
  hoursOutsideWorkingHours: number; // for someone
  recommendedFor: 'keep' | 'async' | 'split' | 'eliminate';
  asyncAlternative?: string;
  estimatedAsyncTime?: number; // minutes
}

/**
 * Action item from meeting
 */
export interface ActionItem {
  id: string;
  owner: string;
  description: string;
  dueDate: Date;
  completed: boolean;
  priority: 'low' | 'medium' | 'high';
}

/**
 * Channel communication metrics
 */
export interface ChannelMetrics {
  channelId: string;
  teamId: string;
  channelName: string;
  purpose: string;
  messageCount: number;
  activeMembers: number;
  signalToNoiseRatio: number; // 0-100: on-topic vs off-topic
  channelHealthScore: number; // 0-100
  lastActivityDate: Date;
  messageVelocity: number; // messages per day
  avgThreadLength: number; // messages per thread
  threadDiscipline: number; // 0-100: adherence to threading
  responseTime: number; // minutes to first response
  relevanceScore: number; // 0-100
}

/**
 * Communication recommendation
 */
export interface CommunicationRecommendation {
  id: string;
  teamId: string;
  userId?: string;
  type:
    | 'async_first'
    | 'reduce_meetings'
    | 'documentation'
    | 'channel_consolidation'
    | 'notification_reduction'
    | 'decision_process'
    | 'meeting_structure'
    | 'remote_first';
  title: string;
  description: string;
  rationale: string;
  estimatedTimeSavings: number; // hours per month
  impactScore: number; // 0-100
  confidence: number; // 0-1
  effort: 'low' | 'medium' | 'high';
  targetMetrics: string[];
  implementationSteps: string[];
  successMetrics: string[];
}

/**
 * Decision tracking
 */
export interface Decision {
  id: string;
  teamId: string;
  title: string;
  description: string;
  proposerId: string;
  decisionMakers: string[];
  proposedDate: Date;
  decidedDate?: Date;
  status: 'pending' | 'approved' | 'rejected' | 'deferred';
  decisionCycleMinutes?: number;
  documented: boolean;
  documentationUrl?: string;
  rationale?: string;
  alternatives?: string[];
}

/**
 * Async communication best practice
 */
export interface AsyncBestPractice {
  id: string;
  title: string;
  description: string;
  context: string; // when/where to apply
  benefits: string[];
  implementation: string[];
  estimatedAdoption: number; // 0-100: likelihood of adoption
}

/**
 * Communication pattern analysis result
 */
export interface CommunicationPatternAnalysis {
  teamId: string;
  period: AnalysisPeriod;
  metrics: CommunicationMetrics;
  meetingsAnalyzed: MeetingAnalysis[];
  channelsAnalyzed: ChannelMetrics[];
  recommendations: CommunicationRecommendation[];
  asyncOpportunities: {
    meetingsCouldBeAsync: MeetingAnalysis[];
    estimatedTimeSavings: number; // hours per month
    documentationNeeded: string[]; // topics
  };
  decisionVelocity: {
    avgCycleDays: number;
    bottlenecks: string[];
    improvedProcesses: string[];
  };
  remoteCollaborationReadiness: number; // 0-100
  distributedTeamScore: number; // 0-100: how well suited for async
}

/**
 * Time zone impact analysis
 */
export interface TimeZoneImpact {
  teamId: string;
  timezone: string;
  workingHours: { start: number; end: number };
  membersInTimezone: string[];
  meetingsOutsideHours: number;
  averageOverlapMinutes: number; // with team average
  recommendedMeetingTime?: string; // e.g., "9:00-10:00 UTC"
}

/**
 * Meeting optimization result
 */
export interface MeetingOptimizationResult {
  teamId: string;
  meetings: MeetingAnalysis[];
  unnecessaryMeetings: MeetingAnalysis[];
  meetingTimeToOptimize: number; // hours per month
  asyncCandidates: MeetingAnalysis[];
  structureImprovements: string[];
  recommendedAgendaTemplate: string;
  estimatedProductivityGain: number; // hours per month
}

/**
 * Remote collaboration profile
 */
export interface RemoteCollaborationProfile {
  teamId: string;
  asyncFirstCapability: number; // 0-100
  documentationMaturity: number; // 0-100
  toolStackOptimization: number; // 0-100
  timezoneComplexity: number; // 0-100: 0=simple, 100=complex
  currentCollaborationScore: number; // 0-100
  recommendations: string[];
}

/**
 * Analysis period
 */
export type AnalysisPeriod = 'week' | 'month' | 'quarter' | 'year';

/**
 * Configuration for CommunicationOptimizationEngine
 */
export interface CommunicationOptimizationConfig {
  enablePatternAnalysis: boolean;
  enableMeetingOptimization: boolean;
  enableAsyncRecommendations: boolean;
  enableRemoteOptimization: boolean;
  enableDecisionTracking: boolean;
  analysisWindowDays: number;
  minConfidenceThreshold: number;
  enableAutoUpdates: boolean;
  updateIntervalMinutes?: number;
  timeZoneContextEnabled?: boolean;
  meetingEffectivenessThreshold?: number;
}
