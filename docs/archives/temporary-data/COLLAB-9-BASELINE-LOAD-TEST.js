#!/usr/bin/env node
/**
 * @file COLLAB-9-BASELINE-LOAD-TEST.js
 * @module collab-9-load-testing
 * @description Baseline load test for Collab-9 WebSocket feature
 */

const http = require('http');

const REPLICA_HOST = process.env.REPLICA_HOST || '192.168.168.31';
const REPLICA_PORT = process.env.REPLICA_PORT || 8080;
const BASE_URL = `http://${REPLICA_HOST}:${REPLICA_PORT}`;
const SCENARIO = process.env.SCENARIO || 'baseline';
const DURATION_MS = parseInt(process.env.DURATION_MS || '30000');
const CONCURRENT_CLIENTS = parseInt(process.env.CONCURRENT_CLIENTS || (SCENARIO === 'stress' ? 50 : 5));

console.log(`\nCOLLAB-9 BASELINE LOAD TEST`);
console.log(`Scenario: ${SCENARIO}`);
console.log(`Duration: ${DURATION_MS}ms`);
console.log(`Clients: ${CONCURRENT_CLIENTS}`);
console.log(`Target: ${BASE_URL}\n`);

const metrics = {
  requestLatencies: [],
  successCount: 0,
  failureCount: 0,
  totalRequests: 0,
  startTime: Date.now(),
};

function calculateStats(values) {
  if (values.length === 0) return null;
  
  const sorted = values.sort((a, b) => a - b);
  const sum = sorted.reduce((a, b) => a + b, 0);
  const avg = sum / sorted.length;
  const p50 = sorted[Math.floor(sorted.length * 0.5)];
  const p95 = sorted[Math.floor(sorted.length * 0.95)];
  const p99 = sorted[Math.floor(sorted.length * 0.99)];
  const max = sorted[sorted.length - 1];
  const min = sorted[0];
  
  return { min, avg, p50, p95, p99, max, count: sorted.length };
}

async function makeRequest() {
  return new Promise((resolve) => {
    const startTime = Date.now();
    
    const req = http.get(`${BASE_URL}/`, { timeout: 5000 }, (res) => {
      const latency = Date.now() - startTime;
      metrics.requestLatencies.push(latency);
      metrics.totalRequests++;
      
      if (res.statusCode === 302 || res.statusCode === 200) {
        metrics.successCount++;
      } else {
        metrics.failureCount++;
      }
      
      req.abort();
      resolve({ statusCode: res.statusCode, latency });
    });

    req.on('error', () => {
      const latency = Date.now() - startTime;
      metrics.failureCount++;
      metrics.totalRequests++;
      metrics.requestLatencies.push(latency);
      resolve({ statusCode: 0, latency, error: true });
    });

    req.on('timeout', () => {
      metrics.failureCount++;
      metrics.totalRequests++;
      metrics.requestLatencies.push(5000);
      req.abort();
      resolve({ statusCode: 0, latency: 5000, timeout: true });
    });
  });
}

async function runClient(clientId) {
  while (Date.now() - metrics.startTime < DURATION_MS) {
    await makeRequest();
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
}

async function runLoadTest() {
  console.log('================================================================================');
  console.log(`Starting load test with ${CONCURRENT_CLIENTS} concurrent clients...`);
  console.log('');
  
  const clientPromises = [];
  for (let i = 0; i < CONCURRENT_CLIENTS; i++) {
    clientPromises.push(runClient(i));
  }
  
  await Promise.all(clientPromises);
  const endTime = Date.now();
  
  const totalDuration = endTime - metrics.startTime;
  const successRate = metrics.totalRequests > 0 ? (metrics.successCount / metrics.totalRequests) * 100 : 0;
  const latencyStats = calculateStats(metrics.requestLatencies);
  const throughput = metrics.totalRequests / (totalDuration / 1000);
  
  console.log('================================================================================');
  console.log('LOAD TEST RESULTS');
  console.log('================================================================================\n');
  
  console.log(`Overall Performance:`);
  console.log(`  Total Duration:       ${totalDuration}ms`);
  console.log(`  Total Requests:       ${metrics.totalRequests}`);
  console.log(`  Successful:           ${metrics.successCount} (${successRate.toFixed(2)}%)`);
  console.log(`  Failed:               ${metrics.failureCount}`);
  console.log(`  Throughput:           ${throughput.toFixed(2)} req/s`);
  console.log('');
  
  if (latencyStats) {
    console.log(`Latency (ms):`);
    console.log(`  Min:                 ${latencyStats.min}ms`);
    console.log(`  Avg:                 ${latencyStats.avg.toFixed(2)}ms`);
    console.log(`  P50:                 ${latencyStats.p50}ms`);
    console.log(`  P95:                 ${latencyStats.p95}ms`);
    console.log(`  P99:                 ${latencyStats.p99}ms`);
    console.log(`  Max:                 ${latencyStats.max}ms`);
    console.log('');
  }
  
  console.log(`SLO Validation:`);
  const sloTarget = 100;
  const p99Latency = latencyStats ? latencyStats.p99 : 0;
  const sloMet = p99Latency < sloTarget && successRate > 99;
  
  console.log(`  P99 Latency Target:   < ${sloTarget}ms`);
  console.log(`  P99 Latency Actual:   ${p99Latency}ms ${p99Latency < sloTarget ? 'PASS' : 'FAIL'}`);
  console.log(`  Success Rate Target:  > 99%`);
  console.log(`  Success Rate Actual:  ${successRate.toFixed(2)}% ${successRate > 99 ? 'PASS' : 'FAIL'}`);
  console.log('');
  
  console.log('================================================================================');
  console.log(`Final Status: ${sloMet ? 'SUCCESS - SLO MET' : 'FAILED - SLO FAILED'}`);
  console.log('================================================================================\n');
  
  return sloMet ? 0 : 1;
}

runLoadTest()
  .then((exitCode) => process.exit(exitCode))
  .catch((err) => {
    console.error(`\nFailed: ${err.message}`);
    process.exit(1);
  });
