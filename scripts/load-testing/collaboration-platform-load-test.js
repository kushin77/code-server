/**
 * @file collaboration-platform-load-test.js
 * @module load-testing/collaboration
 * @description Load testing framework for collaboration platform with SLO validation
 * 
 * Tests collaboration features:
 * - Real-time session synchronization
 * - Presence awareness and cursor tracking
 * - Collaborative editing (simultaneous edits)
 * - WebSocket connection resilience
 * - Message delivery latency and throughput
 */

import http from 'k6/http'
import ws from 'k6/ws'
import { check, group, sleep } from 'k6'
import { Rate, Trend, Counter, Gauge } from 'k6/metrics'

// ============================================================================
// CONFIGURATION
// ============================================================================

const BASE_URL = __ENV.BASE_URL || 'https://ide.kushnir.cloud'
const WS_URL = __ENV.WS_URL || 'wss://ide.kushnir.cloud/ws'
const SCENARIO = __ENV.SCENARIO || 'moderate'
const DURATION = __ENV.DURATION || '10m'
const VUS = parseInt(__ENV.VUS || '20')
const DRY_RUN = __ENV.DRY_RUN === '1'

// SLO Thresholds for Collaboration Platform
const SLO_THRESHOLDS = {
  // P99 latency for collaborative operations < 200ms
  collaborationLatencyP99: 200,
  // P95 latency < 100ms
  collaborationLatencyP95: 100,
  // P50 latency < 50ms
  collaborationLatencyP50: 50,
  // Message delivery success rate > 99.9%
  messageDeliverySuccess: 0.999,
  // Presence sync within 100ms
  presenceSyncP95: 100,
  // Edit conflict resolution < 10%
  editConflictRate: 0.10,
  // Connection establishment < 500ms
  connectionEstablishmentP95: 500,
  // WebSocket ping/pong success > 99.8%
  websocketHealthSuccess: 0.998,
}

// Load profiles by scenario
const LOAD_PROFILES = {
  light: {
    stages: [
      { duration: '1m', target: 10 },
      { duration: '3m', target: 10 },
      { duration: '1m', target: 0 },
    ],
  },
  moderate: {
    stages: [
      { duration: '2m', target: 20 },
      { duration: '5m', target: 20 },
      { duration: '2m', target: 0 },
    ],
  },
  stress: {
    stages: [
      { duration: '2m', target: 50 },
      { duration: '5m', target: 50 },
      { duration: '2m', target: 100 },
      { duration: '2m', target: 0 },
    ],
  },
}

// ============================================================================
// METRICS
// ============================================================================

// Latency metrics
const collaborationLatency = new Trend('collaboration_latency', { unit: 'ms' })
const presenceSyncLatency = new Trend('presence_sync_latency', { unit: 'ms' })
const messageDeliveryLatency = new Trend('message_delivery_latency', { unit: 'ms' })
const connectionEstablishmentTime = new Trend('connection_establishment_time', { unit: 'ms' })
const websocketPingTime = new Trend('websocket_ping_time', { unit: 'ms' })

// Success rates
const messageDeliveryRate = new Rate('message_delivery_success')
const websocketHealthRate = new Rate('websocket_health_success')
const editConflictRate = new Rate('edit_conflict_detected')
const presenceSyncSuccess = new Rate('presence_sync_success')

// Counters
const collaborativeEditsCount = new Counter('collaborative_edits_total')
const presenceUpdatesCount = new Counter('presence_updates_total')
const websocketMessagesCount = new Counter('websocket_messages_total')
const conflictResolutionsCount = new Counter('conflict_resolutions_total')

// Gauges
const activeSessions = new Gauge('active_sessions')
const activeCollaborators = new Gauge('active_collaborators')

// ============================================================================
// LOAD TEST CONFIGURATION
// ============================================================================

export const options = {
  stages: LOAD_PROFILES[SCENARIO]?.stages || LOAD_PROFILES.moderate.stages,
  thresholds: {
    'collaboration_latency': [`p(99) < ${SLO_THRESHOLDS.collaborationLatencyP99}`, `p(95) < ${SLO_THRESHOLDS.collaborationLatencyP95}`],
    'message_delivery_success': [`rate > ${SLO_THRESHOLDS.messageDeliverySuccess}`],
    'presence_sync_latency': [`p(95) < ${SLO_THRESHOLDS.presenceSyncP95}`],
    'websocket_health_success': [`rate > ${SLO_THRESHOLDS.websocketHealthSuccess}`],
    'edit_conflict_detected': [`rate < ${SLO_THRESHOLDS.editConflictRate}`],
    'connection_establishment_time': [`p(95) < ${SLO_THRESHOLDS.connectionEstablishmentP95}`],
    'http_req_duration': ['p(95)<500'],
    'http_req_failed': ['rate<0.1'],
  },
}

// ============================================================================
// TEST FUNCTIONS
// ============================================================================

/**
 * Simulate collaborative editing session
 */
function testCollaborativeEditingSession(sessionId) {
  return group('Collaborative Editing', () => {
    const startTime = new Date()

    const editPayload = {
      sessionId,
      operation: {
        type: 'insert',
        position: Math.floor(Math.random() * 100),
        content: 'Lorem ipsum dolor sit amet ' + Date.now(),
        userId: `user-${__VU}-${Date.now()}`,
      },
      timestamp: new Date().toISOString(),
    }

    const res = http.post(`${BASE_URL}/api/collaborate/edit`, JSON.stringify(editPayload), {
      headers: { 'Content-Type': 'application/json' },
      timeout: '5s',
    })

    const latency = new Date() - startTime
    collaborationLatency.add(latency)
    collaborativeEditsCount.add(1)
    messageDeliveryRate.add(res.status === 200 || res.status === 201)

    check(res, {
      'edit operation succeeded': (r) => r.status === 200 || r.status === 201,
      'response time acceptable': (r) => latency < SLO_THRESHOLDS.collaborationLatencyP99,
    })

    sleep(0.5)
  })
}

/**
 * Test presence sync (cursor tracking and user awareness)
 */
function testPresenceSync(sessionId) {
  return group('Presence Synchronization', () => {
    const startTime = new Date()

    const presencePayload = {
      sessionId,
      presence: {
        userId: `user-${__VU}`,
        cursorPosition: Math.floor(Math.random() * 500),
        selectionStart: Math.floor(Math.random() * 500),
        selectionEnd: Math.floor(Math.random() * 500),
        viewportStart: 0,
        viewportEnd: 50,
      },
      timestamp: new Date().toISOString(),
    }

    const res = http.post(`${BASE_URL}/api/collaborate/presence`, JSON.stringify(presencePayload), {
      headers: { 'Content-Type': 'application/json' },
      timeout: '5s',
    })

    const latency = new Date() - startTime
    presenceSyncLatency.add(latency)
    presenceUpdatesCount.add(1)
    presenceSyncSuccess.add(res.status === 200 || res.status === 201)

    check(res, {
      'presence update succeeded': (r) => r.status === 200 || r.status === 201,
      'presence sync within SLO': (r) => latency < SLO_THRESHOLDS.presenceSyncP95,
    })

    sleep(0.3)
  })
}

/**
 * Test WebSocket real-time collaboration
 */
function testWebSocketCollaboration(sessionId) {
  return group('WebSocket Real-Time Collaboration', () => {
    const connectionStart = new Date()

    ws.connect(
      `${WS_URL}?sessionId=${sessionId}&userId=user-${__VU}`,
      {
        tags: { name: 'WebSocketCollaboration' },
        timeout: '10s',
      },
      (socket) => {
        const connectionTime = new Date() - connectionStart
        connectionEstablishmentTime.add(connectionTime)

        check(socket.status, {
          'WebSocket connection established': (s) => s === 101,
          'connection time within SLO': () => connectionTime < SLO_THRESHOLDS.connectionEstablishmentP95,
        })

        if (socket.status === 101) {
          activeSessions.add(1)

          // Send collaborative edit via WebSocket
          const editMessage = {
            type: 'edit',
            sessionId,
            operation: {
              type: 'insert',
              position: Math.floor(Math.random() * 100),
              content: `Message from VU ${__VU} at ${Date.now()}`,
            },
            timestamp: Date.now(),
          }

          const sendStart = new Date()
          socket.send(JSON.stringify(editMessage))
          websocketMessagesCount.add(1)

          // Receive confirmation
          socket.setTimeout(() => {
            socket.send(JSON.stringify({ type: 'ping' }))
          }, 3000)

          socket.on('message', (msg) => {
            try {
              const data = JSON.parse(msg)
              const deliveryLatency = Date.now() - sendStart

              if (data.type === 'edit-ack') {
                messageDeliveryLatency.add(deliveryLatency)
                messageDeliveryRate.add(true)

                check(deliveryLatency, {
                  'message delivery time < SLO': (d) => d < SLO_THRESHOLDS.collaborationLatencyP99,
                })
              } else if (data.type === 'pong') {
                const pingTime = Date.now() - sendStart
                websocketPingTime.add(pingTime)
                websocketHealthRate.add(true)
              } else if (data.type === 'conflict') {
                editConflictRate.add(true)
                conflictResolutionsCount.add(1)
              } else if (data.type === 'presence') {
                activeCollaborators.add(data.activeUsers || 1)
              }
            } catch (e) {
              messageDeliveryRate.add(false)
            }
          })

          socket.on('close', () => {
            activeSessions.add(-1)
          })

          socket.on('error', () => {
            websocketHealthRate.add(false)
            messageDeliveryRate.add(false)
          })

          // Keep connection alive for 10 seconds
          sleep(10)
        }

        socket.close()
      }
    )
  })
}

/**
 * Test conflict resolution under concurrent edits
 */
function testConflictResolution(sessionId) {
  return group('Conflict Resolution', () => {
    // Simulate two users editing same content simultaneously
    const conflictPayload = {
      sessionId,
      operations: [
        {
          type: 'insert',
          position: 50,
          content: `VU${__VU}-Edit1`,
          userId: `user-${__VU}`,
          timestamp: Date.now(),
        },
        {
          type: 'insert',
          position: 50,
          content: `VU${__VU}-Edit2`,
          userId: `user-${__VU + 1}`,
          timestamp: Date.now() + 1, // Slightly delayed
        },
      ],
    }

    const startTime = new Date()
    const res = http.post(`${BASE_URL}/api/collaborate/resolve-conflict`, JSON.stringify(conflictPayload), {
      headers: { 'Content-Type': 'application/json' },
      timeout: '5s',
    })

    const latency = new Date() - startTime
    messageDeliveryLatency.add(latency)

    try {
      const data = JSON.parse(res.body)
      const hasConflict = data.conflict === true
      editConflictRate.add(hasConflict)
    } catch (e) {
      editConflictRate.add(false)
    }

    check(res, {
      'conflict resolution succeeded': (r) => r.status === 200 || r.status === 201,
      'resolution time acceptable': () => latency < SLO_THRESHOLDS.collaborationLatencyP99,
    })

    sleep(0.5)
  })
}

/**
 * Test session recovery after network failure
 */
function testSessionRecovery(sessionId) {
  return group('Session Recovery', () => {
    const res = http.post(
      `${BASE_URL}/api/collaborate/session/recover`,
      JSON.stringify({ sessionId, userId: `user-${__VU}` }),
      {
        headers: { 'Content-Type': 'application/json' },
        timeout: '5s',
      }
    )

    check(res, {
      'session recovery successful': (r) => r.status === 200,
    })

    sleep(1)
  })
}

// ============================================================================
// MAIN TEST EXECUTION
// ============================================================================

export default function () {
  const sessionId = `session-${__VU}-${Date.now()}`

  group('Collaboration Platform Load Test', () => {
    if (DRY_RUN) {
      console.log(
        `[DRY RUN] Would execute collaboration tests for VU ${__VU} with scenario: ${SCENARIO}`
      )
      sleep(2)
    } else {
      // Test sequence for each virtual user
      testCollaborativeEditingSession(sessionId)
      testPresenceSync(sessionId)
      testWebSocketCollaboration(sessionId)
      testConflictResolution(sessionId)
      testSessionRecovery(sessionId)
    }
  })
}

// ============================================================================
// TEARDOWN
// ============================================================================

export function teardown(data) {
  console.log('Load Test Summary:')
  console.log(`  Scenario: ${SCENARIO}`)
  console.log(`  Duration: ${DURATION}`)
  console.log(`  Virtual Users: ${VUS}`)
  console.log(`  SLO Status:`)
  console.log(`    - Collaboration Latency P99: ${SLO_THRESHOLDS.collaborationLatencyP99}ms`)
  console.log(`    - Message Delivery Success: ${(SLO_THRESHOLDS.messageDeliverySuccess * 100).toFixed(2)}%`)
  console.log(`    - Presence Sync P95: ${SLO_THRESHOLDS.presenceSyncP95}ms`)
  console.log(`    - WebSocket Health: ${(SLO_THRESHOLDS.websocketHealthSuccess * 100).toFixed(2)}%`)
}
