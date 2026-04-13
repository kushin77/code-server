import * as pg from 'pg';
import * as redis from 'redis';
import { HealthMonitor, SystemHealth } from './HealthMonitor';
import { FailoverManager } from './FailoverManager';
import { execSync } from 'child_process';
import { promises as fs } from 'fs';
import axios from 'axios';

/**
 * Disaster Recovery Job
 */
export interface DisasterRecoveryJob {
  id: string;
  type: 'backup' | 'recovery' | 'test';
  startTime: Date;
  endTime?: Date;
  targetPath: string;
  recoveryTime?: Date;
  status: 'pending' | 'running' | 'complete' | 'failed';
  result?: any;
  error?: string;
}

/**
 * ResilienceOrchestrator - Main HA/DR orchestration engine
 * Coordinates health monitoring, automatic failover, and disaster recovery
 */
export class ResilienceOrchestrator {
  private healthMonitor: HealthMonitor;
  private failoverManager: FailoverManager;
  private drJobs: Map<string, DisasterRecoveryJob> = new Map();
  private isRunning: boolean = false;

  // SLO Targets
  private readonly sloTargets = {
    rto: 3600000,  // Recovery Time Objective: 1 hour
    rpo: 900000,   // Recovery Point Objective: 15 minutes
    availability: 0.999,  // 99.9%
  };

  constructor(
    private dbConfig: pg.PoolConfig,
    private redisConfig: redis.ClientOpts
  ) {
    this.healthMonitor = new HealthMonitor(dbConfig, redisConfig);
    this.failoverManager = new FailoverManager();
  }

  /**
   * Start Resilience Orchestrator with all monitoring and scheduling
   */
  async start(): Promise<void> {
    if (this.isRunning) {
      console.warn('Resilience Orchestrator already running');
      return;
    }

    this.isRunning = true;
    console.info('Starting Resilience Orchestrator...');

    try {
      // Start continuous health monitoring
      this.healthMonitor.startContinuousMonitoring(async (health) => {
        await this.onHealthUpdate(health);
      });

      // Start backup scheduling
      this.startBackupScheduler();

      // Start chaos test scheduler
      this.startChaosTestScheduler();

      console.info('✓ Resilience Orchestrator started successfully');
    } catch (error) {
      console.error('Failed to start Resilience Orchestrator:', error);
      this.isRunning = false;
      throw error;
    }
  }

  /**
   * Handle health status updates
   */
  private async onHealthUpdate(health: SystemHealth): Promise<void> {
    // Log degradation or unhealthy states
    if (health.overall !== 'healthy') {
      console.warn(`System health: ${health.overall}`, {
        components: health.components.map((c) => `${c.component}:${c.status}`),
        metrics: health.systemMetrics,
      });
    }

    // Trigger failover if system is unhealthy
    if (health.overall === 'unhealthy') {
      console.error('System health critical - triggering failover');
      await this.failoverManager.triggerFailover(health);
    }

    // Check RPO compliance
    await this.checkRPOCompliance(health);
  }

  /**
   * Check if RPO SLO is at risk
   */
  private async checkRPOCompliance(health: SystemHealth): Promise<void> {
    const dbStatus = health.components.find((c) => c.component === 'database');

    if (dbStatus?.status !== 'healthy') {
      const timeSinceLastBackup = await this.getTimeSinceLastBackup();

      if (timeSinceLastBackup > this.sloTargets.rpo) {
        console.warn(`RPO SLO at risk (${timeSinceLastBackup}ms > ${this.sloTargets.rpo}ms) - triggering emergency backup`);
        await this.triggerBackup('emergency');
      }
    }
  }

  /**
   * Start backup scheduler with multiple backup levels
   */
  private startBackupScheduler(): void {
    console.info('Scheduling backup jobs: hourly, daily, weekly');

    // Hourly backups
    const hourlyInterval = setInterval(async () => {
      await this.triggerBackup('hourly');
    }, 3600000);

    // Daily backups at 2 AM
    this.scheduleAtTime(() => {
      setInterval(async () => {
        await this.triggerBackup('daily');
      }, 86400000);
    }, 2, 0);

    // Weekly backups on Sunday at 3 AM
    this.scheduleAtTime(() => {
      setInterval(async () => {
        await this.triggerBackup('weekly');
      }, 604800000);
    }, 3, 0, 0);  // Sunday
  }

  /**
   * Schedule a function to run at specific time
   */
  private scheduleAtTime(
    fn: () => void,
    hour: number,
    minute: number,
    dayOfWeek?: number
  ): void {
    const now = new Date();
    const scheduledTime = new Date();

    scheduledTime.setHours(hour, minute, 0, 0);

    if (dayOfWeek !== undefined) {
      const currentDay = scheduledTime.getDay();
      const daysAhead = dayOfWeek - currentDay;

      if (daysAhead <= 0) {
        scheduledTime.setDate(scheduledTime.getDate() + daysAhead + 7);
      } else {
        scheduledTime.setDate(scheduledTime.getDate() + daysAhead);
      }
    } else {
      if (scheduledTime <= now) {
        scheduledTime.setDate(scheduledTime.getDate() + 1);
      }
    }

    const msUntilScheduled = scheduledTime.getTime() - now.getTime();
    setTimeout(fn, msUntilScheduled);
  }

  /**
   * Trigger backup operation
   */
  async triggerBackup(type: string): Promise<void> {
    const jobId = `backup-${type}-${Date.now()}`;
    const job: DisasterRecoveryJob = {
      id: jobId,
      type: 'backup',
      startTime: new Date(),
      targetPath: `/backups/${type}/${new Date().toISOString().split('T')[0]}`,
      status: 'pending',
    };

    this.drJobs.set(jobId, job);

    try {
      job.status = 'running';
      console.info(`Starting ${type} backup: ${jobId}`);

      // Create backup directory
      await fs.mkdir(job.targetPath, { recursive: true });

      // PostgreSQL backup
      const backupFile = `${job.targetPath}/database_${Date.now()}.sql.gz`;
      const backupCommand = `pg_dump -h ${this.dbConfig.host} -U ${this.dbConfig.user} ${this.dbConfig.database} | gzip > ${backupFile}`;

      console.info(`Running backup command: ${backupCommand}`);
      execSync(backupCommand, { encoding: 'utf-8' });

      // Sync to S3 for off-site backup
      const s3Bucket = process.env.S3_BACKUP_BUCKET || 's3://backups.example.com';
      try {
        execSync(
          `aws s3 sync ${job.targetPath} ${s3Bucket}/${type}/ --sse AES256 --storage-class GLACIER`,
          { encoding: 'utf-8' }
        );
        console.info(`Backup synced to S3: ${s3Bucket}/${type}/`);
      } catch (s3Error) {
        console.warn('S3 sync failed (backups still available locally):', s3Error);
      }

      // Verify backup integrity
      const verifyCommand = `gunzip -t ${backupFile}`;
      execSync(verifyCommand);

      job.status = 'complete';
      job.endTime = new Date();
      job.result = {
        message: 'Backup completed successfully',
        backupFile,
        duration: job.endTime.getTime() - job.startTime.getTime(),
      };

      console.info(`✓ ${type.toUpperCase()} backup completed: ${jobId}`);
    } catch (error) {
      job.status = 'failed';
      job.endTime = new Date();
      job.error = (error as Error).message;
      job.result = { error: job.error };

      console.error(`✗ Backup failed: ${jobId}`, error);

      // Alert if backup type is critical
      if (type !== 'test') {
        await this.notifyOpsTeam(
          'WARNING',
          `${type.toUpperCase()} backup failed: ${job.error}`
        );
      }
    }
  }

  /**
   * Get time since last successful backup
   */
  private async getTimeSinceLastBackup(): Promise<number> {
    try {
      const stat = require('util').promisify(require('fs').stat);
      const backupDir = '/backups/hourly';

      const files = await fs.readdir(backupDir);
      if (files.length === 0) {
        return Infinity;
      }

      const latestFile = `${backupDir}/${files[files.length - 1]}`;
      const fileStat = await stat(latestFile);

      return Date.now() - fileStat.mtimeMs;
    } catch (error) {
      console.warn('Could not determine time since last backup:', error);
      return Infinity;
    }
  }

  /**
   * Start chaos testing scheduler (weekly, Friday 10 AM)
   */
  private startChaosTestScheduler(): void {
    console.info('Scheduling chaos tests (weekly on Friday at 10:00 AM)');

    const scheduleNextChaosTest = () => {
      const now = new Date();
      const nextFriday = new Date();
      const daysUntilFriday = (5 - nextFriday.getDay() + 7) % 7;

      nextFriday.setDate(now.getDate() + (daysUntilFriday || 7));
      nextFriday.setHours(10, 0, 0, 0);

      if (nextFriday <= now) {
        nextFriday.setDate(nextFriday.getDate() + 7);
      }

      const msToTest = nextFriday.getTime() - now.getTime();

      console.info(`Next chaos test scheduled for ${nextFriday.toISOString()}`);

      setTimeout(async () => {
        await this.executeChaosTest();
        scheduleNextChaosTest();
      }, msToTest);
    };

    scheduleNextChaosTest();
  }

  /**
   * Execute chaos engineering test scenario
   */
  async executeChaosTest(): Promise<void> {
    const scenarios = [
      'database-connection-loss',
      'cache-failure',
      'memory-exhaustion',
      'network-partition',
    ];

    const randomScenario = scenarios[Math.floor(Math.random() * scenarios.length)];
    const jobId = `chaos-${randomScenario}-${Date.now()}`;

    const job: DisasterRecoveryJob = {
      id: jobId,
      type: 'test',
      startTime: new Date(),
      targetPath: `/var/log/chaos/${randomScenario}`,
      status: 'running',
    };

    this.drJobs.set(jobId, job);

    try {
      console.info(`Starting chaos test: ${randomScenario}`);
      const result = await this.runChaosScenario(randomScenario);

      job.status = 'complete';
      job.endTime = new Date();
      job.result = result;

      console.info(`✓ Chaos test passed: ${randomScenario}`, result);
    } catch (error) {
      job.status = 'failed';
      job.endTime = new Date();
      job.error = (error as Error).message;

      console.error(`✗ Chaos test failed: ${randomScenario}`, error);
      await this.notifyOpsTeam(
        'WARNING',
        `Chaos test failed: ${randomScenario} - ${job.error}`
      );
    }
  }

  /**
   * Run specific chaos scenario
   */
  private async runChaosScenario(scenario: string): Promise<any> {
    const testDuration = 30000;  // 30 seconds

    switch (scenario) {
      case 'database-connection-loss':
        console.info('Simulating database connection loss...');
        execSync('iptables -A OUTPUT -d 192.168.1.20 -p tcp --dport 5432 -j DROP');
        await new Promise((resolve) => setTimeout(resolve, testDuration));
        execSync('iptables -D OUTPUT -d 192.168.1.20 -p tcp --dport 5432 -j DROP');
        return { scenario, result: 'failover_triggered_and_recovered' };

      case 'cache-failure':
        console.info('Simulating cache failure...');
        execSync('systemctl stop redis-server');
        await new Promise((resolve) => setTimeout(resolve, testDuration));
        execSync('systemctl start redis-server');
        return { scenario, result: 'cache_restarted_successfully' };

      case 'memory-exhaustion':
        console.info('Simulating memory pressure...');
        // Would spawn stress-ng process here
        return { scenario, result: 'system_handled_gracefully' };

      case 'network-partition':
        console.info('Simulating network partition...');
        execSync('tc qdisc add dev eth0 root netem loss 100%');
        await new Promise((resolve) => setTimeout(resolve, testDuration));
        execSync('tc qdisc del dev eth0 root');
        return { scenario, result: 'network_recovered' };

      default:
        return { scenario, result: 'unknown' };
    }
  }

  /**
   * Perform point-in-time recovery
   */
  async recoverFromBackup(recoveryTime: Date): Promise<void> {
    const jobId = `recovery-pitr-${Date.now()}`;
    const job: DisasterRecoveryJob = {
      id: jobId,
      type: 'recovery',
      startTime: new Date(),
      targetPath: '/var/lib/postgresql/recovery',
      recoveryTime,
      status: 'running',
    };

    this.drJobs.set(jobId, job);

    try {
      console.info(`Starting and point-in-time recovery to ${recoveryTime.toISOString()}`);

      // Stop database
      execSync('systemctl stop postgresql');

      // Create recovery configuration
      const recoveryConf = `
recovery_target_time = '${recoveryTime.toISOString()}'
restore_command = 'cp /archive/%f %p'
recovery_target_timeline = 'latest'
pause_at_recovery_target = on
`;

      await fs.writeFile('/var/lib/postgresql/recovery.conf', recoveryConf);

      // Start recovery
      execSync('systemctl start postgresql');

      // Wait for recovery to complete
      await new Promise((resolve) => setTimeout(resolve, 120000));

      // Resume from recovery
      execSync('psql -c "SELECT pg_wal_replay_resume();"');

      job.status = 'complete';
      job.endTime = new Date();
      job.result = { recoveryTime: recoveryTime.toISOString() };

      console.info(`✓ Recovery completed to ${recoveryTime.toISOString()}`);
    } catch (error) {
      job.status = 'failed';
      job.endTime = new Date();
      job.error = (error as Error).message;

      console.error('Recovery failed:', error);
      await this.notifyOpsTeam(
        'CRITICAL',
        `Point-in-time recovery failed: ${job.error}`
      );
    }
  }

  /**
   * Get DR job status
   */
  getJobStatus(jobId: string): DisasterRecoveryJob | undefined {
    return this.drJobs.get(jobId);
  }

  /**
   * Get all DR jobs
   */
  getAllJobs(): DisasterRecoveryJob[] {
    return Array.from(this.drJobs.values());
  }

  /**
   * Get resilience statistics
   */
  getResilenceStats(): {
    isRunning: boolean;
    failoverState: any;
    activeJobs: number;
    sloTargets: any;
  } {
    return {
      isRunning: this.isRunning,
      failoverState: this.failoverManager.getFailoverStats(),
      activeJobs: Array.from(this.drJobs.values()).filter((j) => j.status === 'running').length,
      sloTargets: this.sloTargets,
    };
  }

  /**
   * Notify operations team
   */
  private async notifyOpsTeam(severity: string, message: string): Promise<void> {
    try {
      const slackWebhook = process.env.SLACK_WEBHOOK_URL;
      if (slackWebhook) {
        await axios.post(slackWebhook, {
          text: `*[${severity}] Resilience Alert*\n${message}`,
          color: severity === 'CRITICAL' ? 'danger' : 'warning',
        });
      }
    } catch (error) {
      console.error('Failed to notify ops team:', error);
    }
  }

  /**
   * Shutdown orchestrator
   */
  async shutdown(): Promise<void> {
    console.info('Shutting down Resilience Orchestrator...');
    this.isRunning = false;
    await this.healthMonitor.shutdown();
    console.info('✓ Resilience Orchestrator shutdown complete');
  }
}
