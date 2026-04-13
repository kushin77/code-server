/**
 * Agent Farm RBAC (Role-Based Access Control)
 * 
 * Manages team-level agent profiles and role-specific agent assignments.
 * Allows organizations to customize which agents are available per role.
 */

import * as vscode from 'vscode';
import { AgentSpecialization, TaskType } from './types';

/**
 * Team member role
 */
export enum TeamRole {
  ENGINEER = 'engineer',
  SENIOR_ENGINEER = 'senior_engineer',
  ARCHITECT = 'architect',
  QA_ENGINEER = 'qa_engineer',
  TECH_LEAD = 'tech_lead',
  MANAGER = 'manager',
}

/**
 * Agent access permission
 */
export interface AgentPermission {
  agent: AgentSpecialization;
  allowed: boolean;
  taskTypes?: TaskType[];
}

/**
 * Role-based agent configuration
 */
export interface RoleAgentProfile {
  role: TeamRole;
  name: string;
  description: string;
  allowedAgents: AgentPermission[];
  maxAnalysisPerDay: number;
  priority: 'standard' | 'high' | 'critical';
}

/**
 * Team member configuration
 */
export interface TeamMember {
  id: string;
  username: string;
  email: string;
  role: TeamRole;
  agentProfile: RoleAgentProfile;
}

/**
 * Agent Farm RBAC Manager
 */
export class RBACManager {
  private roleProfiles: Map<TeamRole, RoleAgentProfile>;
  private teamMembers: Map<string, TeamMember>;
  private outputChannel: vscode.OutputChannel;
  private config: vscode.WorkspaceConfiguration;

  constructor() {
    this.outputChannel = vscode.window.createOutputChannel('Agent Farm: RBAC');
    this.config = vscode.workspace.getConfiguration('agentFarm.rbac');
    this.roleProfiles = this.initializeDefaultProfiles();
    this.teamMembers = new Map();
    this.loadTeamConfiguration();
  }

  /**
   * Get agent profile for current user
   */
  async getCurrentUserProfile(): Promise<RoleAgentProfile> {
    const username = await this.getCurrentUsername();
    const member = this.teamMembers.get(username);
    
    if (member) {
      return member.agentProfile;
    }

    // Default to engineer role
    const defaultRole = this.roleProfiles.get(TeamRole.ENGINEER);
    if (!defaultRole) {
      throw new Error('No default role configuration available');
    }

    return defaultRole;
  }

  /**
   * Check if current user can use a specific agent
   */
  async canUseAgent(agent: AgentSpecialization): Promise<boolean> {
    const profile = await this.getCurrentUserProfile();
    const permission = profile.allowedAgents.find(p => p.agent === agent);
    
    return permission?.allowed ?? false;
  }

  /**
   * Get allowed agent specializations for current user
   */
  async getAllowedAgents(): Promise<AgentSpecialization[]> {
    const profile = await this.getCurrentUserProfile();
    return profile.allowedAgents
      .filter(p => p.allowed)
      .map(p => p.agent);
  }

  /**
   * Filter task types available for agent and user
   */
  async getAvailableTaskTypes(agent: AgentSpecialization): Promise<TaskType[]> {
    const profile = await this.getCurrentUserProfile();
    const permission = profile.allowedAgents.find(p => p.agent === agent);
    
    if (!permission?.allowed) {
      return [];
    }

    return permission.taskTypes || Object.values(TaskType);
  }

  /**
   * Get analysis quota for current user (analyses per day)
   */
  async getRemainingQuota(): Promise<number> {
    const profile = await this.getCurrentUserProfile();
    const todayKey = new Date().toISOString().split('T')[0];
    const quota = this.config.get(`quota.${todayKey}`, 0) as number;
    
    return Math.max(0, profile.maxAnalysisPerDay - quota);
  }

  /**
   * Record analysis execution for quota tracking
   */
  async recordAnalysis(): Promise<void> {
    const profile = await this.getCurrentUserProfile();
    const todayKey = new Date().toISOString().split('T')[0];
    const currentQuota = this.config.get(`quota.${todayKey}`, 0) as number;
    
    await this.config.update(`quota.${todayKey}`, currentQuota + 1);
    
    const remaining = profile.maxAnalysisPerDay - (currentQuota + 1);
    if (remaining < 5) {
      vscode.window.showWarningMessage(
        `Agent Farm: You have ${remaining} analyses remaining today`
      );
    }
  }

  /**
   * Check analysis priority level
   */
  async getAnalysisPriority(): Promise<'standard' | 'high' | 'critical'> {
    const profile = await this.getCurrentUserProfile();
    return profile.priority;
  }

  /**
   * Register team member with specific role
   */
  registerTeamMember(member: TeamMember): void {
    const profile = this.roleProfiles.get(member.role);
    if (!profile) {
      throw new Error(`Unknown role: ${member.role}`);
    }

    member.agentProfile = profile;
    this.teamMembers.set(member.username, member);
    this.log(`Registered team member: ${member.username} (${member.role})`);
  }

  /**
   * Update role profile permissions
   */
  updateRoleProfile(role: TeamRole, updates: Partial<RoleAgentProfile>): void {
    const profile = this.roleProfiles.get(role);
    if (!profile) {
      throw new Error(`Unknown role: ${role}`);
    }

    Object.assign(profile, updates);
    this.log(`Updated role profile: ${role}`);
    this.persistRoleConfiguration();
  }

  /**
   * Get all role profiles
   */
  getAllRoleProfiles(): RoleAgentProfile[] {
    return Array.from(this.roleProfiles.values());
  }

  /**
   * Initialize default role-based agent profiles
   */
  private initializeDefaultProfiles(): Map<TeamRole, RoleAgentProfile> {
    return new Map([
      [TeamRole.ENGINEER, {
        role: TeamRole.ENGINEER,
        name: 'Software Engineer',
        description: 'Full access to CodeAgent and ReviewAgent for implementation and review',
        allowedAgents: [
          { agent: AgentSpecialization.CODER, allowed: true },
          { agent: AgentSpecialization.REVIEWER, allowed: true },
          { agent: AgentSpecialization.TESTER, allowed: true },
          { agent: AgentSpecialization.ARCHITECT, allowed: false },
        ],
        maxAnalysisPerDay: 100,
        priority: 'standard',
      }],
      [TeamRole.SENIOR_ENGINEER, {
        role: TeamRole.SENIOR_ENGINEER,
        name: 'Senior Software Engineer',
        description: 'Full access to all agents including architecture analysis',
        allowedAgents: [
          { agent: AgentSpecialization.CODER, allowed: true },
          { agent: AgentSpecialization.REVIEWER, allowed: true },
          { agent: AgentSpecialization.TESTER, allowed: true },
          { agent: AgentSpecialization.ARCHITECT, allowed: true },
        ],
        maxAnalysisPerDay: 200,
        priority: 'high',
      }],
      [TeamRole.ARCHITECT, {
        role: TeamRole.ARCHITECT,
        name: 'Solutions Architect',
        description: 'Specializes in system design and architecture analysis',
        allowedAgents: [
          { agent: AgentSpecialization.CODER, allowed: false },
          { agent: AgentSpecialization.REVIEWER, allowed: false },
          { agent: AgentSpecialization.TESTER, allowed: false },
          { agent: AgentSpecialization.ARCHITECT, allowed: true, taskTypes: [TaskType.ARCHITECTURE, TaskType.PERFORMANCE] },
        ],
        maxAnalysisPerDay: 150,
        priority: 'high',
      }],
      [TeamRole.QA_ENGINEER, {
        role: TeamRole.QA_ENGINEER,
        name: 'QA Engineer',
        description: 'Specializes in test coverage and quality analysis',
        allowedAgents: [
          { agent: AgentSpecialization.CODER, allowed: false },
          { agent: AgentSpecialization.REVIEWER, allowed: true, taskTypes: [TaskType.CODE_REVIEW] },
          { agent: AgentSpecialization.TESTER, allowed: true },
          { agent: AgentSpecialization.ARCHITECT, allowed: false },
        ],
        maxAnalysisPerDay: 150,
        priority: 'standard',
      }],
      [TeamRole.TECH_LEAD, {
        role: TeamRole.TECH_LEAD,
        name: 'Technical Lead',
        description: 'Full access to all agents with priority execution',
        allowedAgents: [
          { agent: AgentSpecialization.CODER, allowed: true },
          { agent: AgentSpecialization.REVIEWER, allowed: true },
          { agent: AgentSpecialization.TESTER, allowed: true },
          { agent: AgentSpecialization.ARCHITECT, allowed: true },
        ],
        maxAnalysisPerDay: 300,
        priority: 'critical',
      }],
      [TeamRole.MANAGER, {
        role: TeamRole.MANAGER,
        name: 'Engineering Manager',
        description: 'Read-only access to team analytics and reports',
        allowedAgents: [
          { agent: AgentSpecialization.CODER, allowed: false },
          { agent: AgentSpecialization.REVIEWER, allowed: false },
          { agent: AgentSpecialization.TESTER, allowed: false },
          { agent: AgentSpecialization.ARCHITECT, allowed: false },
        ],
        maxAnalysisPerDay: 0,
        priority: 'standard',
      }],
    ]);
  }

  /**
   * Load team configuration from workspace settings
   */
  private loadTeamConfiguration(): void {
    try {
      const teamConfig = this.config.get('team', {}) as Record<string, any>;
      
      for (const username in teamConfig) {
        const memberConfig = teamConfig[username];
        const member: TeamMember = {
          id: memberConfig.id || username,
          username,
          email: memberConfig.email || `${username}@company.com`,
          role: memberConfig.role || TeamRole.ENGINEER,
          agentProfile: {} as any, // Will be filled by registerTeamMember
        };
        
        try {
          this.registerTeamMember(member);
        } catch (error) {
          this.logError(`Failed to load team member ${username}: ${error}`);
        }
      }
      
      this.log(`Loaded ${this.teamMembers.size} team members from configuration`);
    } catch (error) {
      this.logError(`Failed to load team configuration: ${error}`);
    }
  }

  /**
   * Persist role configuration to workspace settings
   */
  private persistRoleConfiguration(): void {
    try {
      const profiles: Record<string, any> = {};
      
      for (const [role, profile] of this.roleProfiles) {
        profiles[role] = {
          name: profile.name,
          description: profile.description,
          allowedAgents: profile.allowedAgents,
          maxAnalysisPerDay: profile.maxAnalysisPerDay,
          priority: profile.priority,
        };
      }
      
      this.config.update('roles', profiles);
      this.log('Role configuration persisted');
    } catch (error) {
      this.logError(`Failed to persist role configuration: ${error}`);
    }
  }

  /**
   * Get current VS Code user
   */
  private async getCurrentUsername(): Promise<string> {
    // Try to get from git config first
    try {
      const { execSync } = require('child_process');
      const username = execSync('git config user.name', { encoding: 'utf-8' }).trim();
      if (username) return username;
    } catch {
      // Fallback to environment or VS Code context
    }

    // Fallback to environment variable or workspace name
    return process.env.USER || process.env.USERNAME || 'default-user';
  }

  /**
   * Log message
   */
  private log(message: string): void {
    this.outputChannel.appendLine(`[${new Date().toISOString()}] ${message}`);
  }

  /**
   * Log error
   */
  private logError(message: string): void {
    this.outputChannel.appendLine(`[ERROR] ${message}`);
  }

  /**
   * Show output channel
   */
  showOutput(): void {
    this.outputChannel.show();
  }
}
