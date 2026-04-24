// @file        cli/src/commands/node.ts
// @module      cli/edge-node
// @description CLI commands for edge node management

import { Command } from 'commander';
import { spawn } from 'child_process';
import { resolve } from 'path';
import chalk from 'chalk';

export function createNodeCommand(): Command {
  const cmd = new Command('node');
  
  cmd.description('Manage edge nodes for burst compute');

  // Register command
  cmd
    .command('register')
    .description('Register laptop as edge node with scheduler')
    .option('--name <name>', 'Node name (default: hostname)', require('os').hostname())
    .option('--scheduler <url>', 'Scheduler URL', process.env.SCHEDULER_URL || 'https://scheduler.kushnir.cloud')
    .action(async (options) => {
      console.log(chalk.blue(`📝 Registering edge node: ${options.name}`));
      
      // Call Python daemon to register
      try {
        await registerWithScheduler(options.name, options.scheduler);
        console.log(chalk.green(`✅ Node '${options.name}' registered successfully`));
      } catch (error) {
        console.error(chalk.red(`❌ Registration failed: ${error}`));
        process.exit(1);
      }
    });

  // Unregister command
  cmd
    .command('unregister')
    .description('Unregister edge node from scheduler')
    .option('--name <name>', 'Node name', require('os').hostname())
    .action(async (options) => {
      console.log(chalk.yellow(`🔌 Unregistering edge node: ${options.name}`));
      
      try {
        await unregisterFromScheduler(options.name);
        console.log(chalk.green(`✅ Node '${options.name}' unregistered`));
      } catch (error) {
        console.error(chalk.red(`❌ Unregistration failed: ${error}`));
        process.exit(1);
      }
    });

  // Status command
  cmd
    .command('status')
    .description('Show edge node daemon status')
    .action(async (options) => {
      console.log(chalk.blue('📊 Edge node status'));
      
      try {
        const status = await getNodeStatus();
        console.log(chalk.green('✅ Daemon running'));
        console.log(`  Name: ${status.name}`);
        console.log(`  Battery: ${status.battery}%`);
        console.log(`  Queue: ${status.queue_length} tasks`);
        console.log(`  Capabilities:`, status.capabilities);
      } catch (error) {
        console.error(chalk.red(`❌ Daemon not running: ${error}`));
        process.exit(1);
      }
    });

  // Daemon command
  cmd
    .command('daemon')
    .description('Start edge node daemon (runs in background)')
    .option('--name <name>', 'Node name', require('os').hostname())
    .action((options) => {
      console.log(chalk.blue(`🚀 Starting edge node daemon: ${options.name}`));
      
      // Spawn Python daemon as subprocess
      const daemon = spawn('python3', [
        resolve(__dirname, '../../edge-agent/main.py'),
      ], {
        env: {
          ...process.env,
          NODE_NAME: options.name,
        },
        detached: true,
        stdio: 'ignore',
      });

      daemon.unref();
      console.log(chalk.green(`✅ Daemon started (PID: ${daemon.pid})`));
    });

  return cmd;
}

async function registerWithScheduler(nodeName: string, schedulerUrl: string): Promise<void> {
  // Placeholder: real impl would call Python edge-agent registration
  return new Promise((resolve) => {
    setTimeout(resolve, 1000);
  });
}

async function unregisterFromScheduler(nodeName: string): Promise<void> {
  // Placeholder: real impl would call Python edge-agent unregistration
  return new Promise((resolve) => {
    setTimeout(resolve, 1000);
  });
}

async function getNodeStatus(): Promise<any> {
  // Placeholder: real impl would query daemon status
  return {
    name: require('os').hostname(),
    battery: 85,
    queue_length: 0,
    capabilities: {
      cpu: '8',
      memory: '16Gi',
      gpu: '0',
    },
  };
}

export { createNodeCommand as default };
