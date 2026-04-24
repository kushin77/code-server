#!/usr/bin/env node
/**
 * k6 Load Test for WebSocket Gateway Cluster
 * Tests: 1000 concurrent WebSocket pairs with Redis Pub/Sub fan-out
 * Metrics: connection time, message latency, throughput, error rate
 */

import ws from 'k6/ws';
import { check, sleep } from 'k6';
import { Counter, Trend, Rate, Gauge } from 'k6/metrics';

// Custom metrics
const wsErrors = new Counter('ws_errors');
const connectionTime = new Trend('ws_connection_time');
const messageLatency = new Trend('ws_message_latency');
const messagesPerSecond = new Gauge('ws_messages_per_second');
const errorRate = new Rate('ws_error_rate');
const concurrentConnections = new Gauge('ws_concurrent_connections');

// Test configuration
export const options = {
    stages: [
        { duration: '2m', target: 100 },  // Ramp-up to 100 connections
        { duration: '5m', target: 500 },  // Scale to 500
        { duration: '5m', target: 1000 }, // Scale to 1000
        { duration: '5m', target: 1000 }, // Hold at 1000
        { duration: '2m', target: 0 },    // Ramp down
    ],
    thresholds: {
        'ws_connection_time': ['p(95)<2000'],      // 95th percentile < 2 seconds
        'ws_message_latency': ['p(95)<100'],       // 95th percentile < 100ms
        'ws_error_rate': ['rate<0.01'],            // Error rate < 1%
        'http_req_duration': ['p(95)<500'],
    },
};

// Test function - each VU represents a client
export default function() {
    const sessionId = `session-${__VU}-${__ITER}`;
    const gatewayUrl = `ws://${__ENV.GATEWAY_HOST || 'localhost'}:8080/ws?session_id=${sessionId}`;
    
    const startTime = new Date();
    let isConnected = false;
    let messagesSent = 0;
    let messagesReceived = 0;
    
    const res = ws.connect(gatewayUrl, {
        tags: { name: 'WebSocket' },
        callbacks: {
            open: (socket) => {
                isConnected = true;
                connectionTime.add(new Date() - startTime);
                concurrentConnections.add(1);
                
                check(socket.readyState, {
                    'connection opened': (state) => state === ws.OPEN,
                });
                
                // Send initial message to establish session
                const initMsg = JSON.stringify({
                    type: 'init',
                    session_id: sessionId,
                    client_id: __VU,
                });
                socket.send(initMsg);
                messagesSent++;
                
                // Send periodic messages throughout connection lifetime
                socket.setInterval(() => {
                    if (socket.readyState === ws.OPEN && messagesSent < 100) {
                        const msg = JSON.stringify({
                            type: 'message',
                            timestamp: Date.now(),
                            data: `Test message from VU ${__VU}`,
                        });
                        socket.send(msg);
                        messagesSent++;
                    }
                }, 100);  // Send message every 100ms
            },
            
            message: (socket, data) => {
                const receivedTime = Date.now();
                messagesReceived++;
                
                try {
                    const msg = JSON.parse(data);
                    
                    // Calculate latency if message has timestamp
                    if (msg.timestamp) {
                        const latency = receivedTime - msg.timestamp;
                        messageLatency.add(latency);
                    }
                    
                    check(msg, {
                        'message has type': (m) => m.type !== undefined,
                        'message is valid JSON': true,
                    });
                } catch (err) {
                    wsErrors.add(1);
                    errorRate.add(1);
                }
            },
            
            close: () => {
                isConnected = false;
                concurrentConnections.add(-1);
                
                // Calculate throughput
                const connectionDuration = (new Date() - startTime) / 1000;
                messagesPerSecond.add(messagesSent / connectionDuration);
                
                check({ messagesReceived }, {
                    'received messages': (m) => m.messagesReceived > 0,
                    'message delivery rate > 80%': (m) => 
                        m.messagesReceived >= messagesSent * 0.8,
                });
            },
            
            error: (msg) => {
                wsErrors.add(1);
                errorRate.add(1);
                
                check(null, {
                    'ws error occurred': false,
                });
            },
        },
    }, {
        timeout: '60s',
        linger: 10000,  // Keep connection open for 10 seconds after test
    });
    
    // Hold connection open for test duration
    sleep(5);
    
    check(res, {
        'status is 101': (r) => r && r.status === 101,
    });
}

/**
 * Teardown: Print summary statistics
 */
export function teardown(data) {
    console.log('=== WebSocket Gateway Cluster Load Test Results ===');
    console.log(`Total VUs: ${__ENV.VUS || 'N/A'}`);
    console.log(`Test Duration: ${__ENV.DURATION || 'N/A'}`);
    console.log(`Total Errors: ${wsErrors.value}`);
}
