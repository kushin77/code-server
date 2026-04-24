#!/usr/bin/env node
const test = require('node:test');
const assert = require('node:assert/strict');

const WebSocketGatewayClusterService = require('../clustering/websocket-gateway-cluster-service');

test('service routes the same session key to the same node even when connection counts change', () => {
    const service = new WebSocketGatewayClusterService({ nodeCount: 3 });

    const first = service.routeConnectionToNode({
        connectionId: 'conn-a',
        sessionId: 'stable-session',
        channel: 'route',
    });

    const second = service.routeConnectionToNode({
        connectionId: 'conn-b',
        sessionId: 'stable-session',
        channel: 'route',
    });

    assert.equal(first.nodeId, second.nodeId);
    assert.notEqual(first.connectionId, second.connectionId);
});

test('connection tokens remain idempotent', () => {
    const service = new WebSocketGatewayClusterService({ nodeCount: 3 });

    const first = service.routeConnectionToNode({
        connectionId: 'conn-token-a',
        sessionId: 'token-session-a',
        channel: 'connections',
    }, 'shared-token');

    const second = service.routeConnectionToNode({
        connectionId: 'conn-token-b',
        sessionId: 'token-session-b',
        channel: 'connections',
    }, 'shared-token');

    assert.equal(first.connectionId, second.connectionId);
    assert.equal(first.nodeId, second.nodeId);
});

test('routes connection data without an explicit connectionId when a token is present', () => {
    const service = new WebSocketGatewayClusterService({ nodeCount: 3 });

    const first = service.routeConnectionToNode({
        sessionId: 'cluster-session-1',
        userId: 'user-1',
        workspaceId: 'workspace-1',
        channel: 'route',
    }, 'cluster-token-1');

    const second = service.routeConnectionToNode({
        sessionId: 'cluster-session-1',
        userId: 'user-1',
        workspaceId: 'workspace-1',
        channel: 'route',
    }, 'cluster-token-1');

    assert.ok(first.connectionId);
    assert.equal(first.connectionId, second.connectionId);
    assert.equal(first.nodeId, second.nodeId);
});