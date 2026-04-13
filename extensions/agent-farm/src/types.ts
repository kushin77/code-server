/**
 * Agent Farm Types and Interfaces
 */

import * as vscode from 'vscode';

/**
 * Task types that agents can handle
 */
export enum TaskType {
  ARCHITECTURE = 'architecture',
  CODE_IMPLEMENTATION = 'code_implementation',
  TEST_COVERAGE = 'test_coverage',
  CODE_REVIEW = 'code_review',
  REFACTORING = 'refactoring',
  PERFORMANCE = 'performance',
  SECURITY = 'security',
  CI_CD = 'ci_cd',
}

/**
 * Agent specialization domains
 */
export enum AgentSpecialization {
  ARCHITECT = 'architect',
  CODER = 'coder',
  TESTER = 'tester',
  REVIEWER = 'reviewer',
  CI_CD = 'ci_cd',
}

/**
 * Single recommendation from an agent
 */
export interface Recommendation {
  id: string;
  title: string;
  description: string;
  severity: 'info' | 'warning' | 'critical';
  actionable: boolean;
  suggestedFix?: string;
  codeSnippet?: string;
  documentationUrl?: string;
}

/**
 * Result of an agent analysis/recommendation
 */
export interface AgentResult {
  agent: string;
  specialization: AgentSpecialization;
  taskType: TaskType;
  timestamp: number;
  duration: number; // milliseconds
  recommendations: Recommendation[];
  confidence: number; // 0-100
  metadata: Record<string, unknown>;
}

/**
 * Orchestrator result combining all agent analyses
 */
export interface OrchestratorResult {
  documentUri: string;
  totalDuration: number;
  agentResults: AgentResult[];
  aggregatedRecommendations: Recommendation[];
  summary: {
    totalRecommendations: number;
    criticalCount: number;
    warningCount: number;
    infoCount: number;
    averageConfidence: number;
  };
}

/**
 * Code element types (for indexing)
 */
export enum CodeElementType {
  FUNCTION = 'function',
  CLASS = 'class',
  INTERFACE = 'interface',
  TYPE = 'type',
  CONSTANT = 'constant',
  VARIABLE = 'variable',
  IMPORT = 'import',
  EXPORT = 'export',
}

/**
 * Represents a code element (function, class, etc.)
 */
export interface CodeElement {
  type: CodeElementType;
  name: string;
  lineStart: number;
  lineEnd: number;
  complexity: number; // Cyclomatic complexity estimate
  hasTests: boolean;
  isExported: boolean;
  documentation: string | undefined;
  children: CodeElement[]; // For nested elements
}

/**
 * Code index result
 */
export interface CodeIndex {
  fileName: string;
  totalLines: number;
  elements: CodeElement[];
  statistics: {
    totalFunctions: number;
    totalClasses: number;
    averageComplexity: number;
    hasTests: boolean;
    documentationRatio: number;
  };
}

