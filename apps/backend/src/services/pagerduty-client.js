// @file        apps/backend/src/services/pagerduty-client.ts
// @module      services/pagerduty-client
// @description PagerDuty incident management client
import axios from 'axios';
/**
 * PagerDuty Incident Management Client
 *
 * Provides:
 * - View live incidents
 * - Acknowledge incidents
 * - Resolve incidents
 * - Escalate incidents
 * - Add notes and logs
 * - Service status monitoring
 * - On-call schedule tracking
 */
export class PagerDutyClient {
    constructor(authToken, baseUrl = 'https://api.pagerduty.com') {
        this.authToken = authToken;
        this.baseUrl = baseUrl;
        this.cacheMap = new Map();
        this.cacheExpiry = 5 * 60 * 1000; // 5 minutes
        this.apiClient = axios.create({
            baseURL: baseUrl,
            headers: {
                'Authorization': `Token token=${authToken}`,
                'Accept': 'application/vnd.pagerduty+json;version=2',
                'Content-Type': 'application/json',
            },
            timeout: 10000,
        });
    }
    /**
     * List all incidents
     */
    async listIncidents(status, limit = 25, offset = 0) {
        try {
            const params = { limit, offset, include: ['assignments', 'services', 'teams'] };
            if (status) {
                params.statuses = [status];
            }
            const response = await this.apiClient.get('/incidents', { params });
            return {
                incidents: response.data.incidents,
                total: response.data.limit,
            };
        }
        catch (error) {
            throw new Error(`Failed to list incidents: ${error instanceof Error ? error.message : 'Unknown'}`);
        }
    }
    /**
     * Get incident details
     */
    async getIncident(incidentId) {
        return this.cachedRequest(`incident_${incidentId}`, async () => {
            const response = await this.apiClient.get(`/incidents/${incidentId}`, {
                params: { include: ['assignments', 'services', 'teams'] },
            });
            return response.data.incident;
        });
    }
    /**
     * Acknowledge incident
     */
    async acknowledgeIncident(incidentId, userId) {
        const response = await this.apiClient.put(`/incidents/${incidentId}`, {
            incidents: [
                {
                    id: incidentId,
                    type: 'incident_reference',
                    status: 'acknowledged',
                    assignments: [
                        {
                            assignee: { id: userId, type: 'user_reference' },
                        },
                    ],
                },
            ],
        });
        this.invalidateCache(`incident_${incidentId}`);
        return response.data.incidents[0];
    }
    /**
     * Resolve incident
     */
    async resolveIncident(incidentId, resolution = 'Resolved') {
        const response = await this.apiClient.put(`/incidents/${incidentId}`, {
            incidents: [
                {
                    id: incidentId,
                    type: 'incident_reference',
                    status: 'resolved',
                },
            ],
        });
        this.invalidateCache(`incident_${incidentId}`);
        return response.data.incidents[0];
    }
    /**
     * Add note to incident
     */
    async addIncidentNote(incidentId, content, userId) {
        const response = await this.apiClient.post(`/incidents/${incidentId}/notes`, {
            note: { content },
        });
        return response.data;
    }
    /**
     * Escalate incident
     */
    async escalateIncident(incidentId) {
        const response = await this.apiClient.post(`/incidents/${incidentId}/escalate`, {});
        this.invalidateCache(`incident_${incidentId}`);
        return response.data.incident;
    }
    /**
     * List on-call users
     */
    async getOnCallUsers() {
        return this.cachedRequest('oncall_users', async () => {
            const response = await this.apiClient.get('/oncalls', {
                params: { include: ['users', 'escalation_policies', 'schedules'] },
            });
            const users = new Map();
            response.data.oncalls.forEach((oncall) => {
                if (oncall.user) {
                    users.set(oncall.user.id, oncall.user);
                }
            });
            return Array.from(users.values());
        });
    }
    /**
     * List services
     */
    async listServices(limit = 25) {
        return this.cachedRequest('services', async () => {
            const response = await this.apiClient.get('/services', {
                params: {
                    limit,
                    include: ['escalation_policies', 'teams'],
                },
            });
            return response.data.services;
        });
    }
    /**
     * Get service details
     */
    async getService(serviceId) {
        return this.cachedRequest(`service_${serviceId}`, async () => {
            const response = await this.apiClient.get(`/services/${serviceId}`, {
                params: { include: ['escalation_policies', 'teams'] },
            });
            return response.data.service;
        });
    }
    /**
     * Get incident urgency stats
     */
    async getIncidentStats() {
        return this.cachedRequest('incident_stats', async () => {
            const [triggered, acknowledged, resolved] = await Promise.all([
                this.listIncidents('triggered', 1),
                this.listIncidents('acknowledged', 1),
                this.listIncidents('resolved', 1),
            ]);
            return {
                triggered: triggered.total,
                acknowledged: acknowledged.total,
                resolved: resolved.total,
                avgResolutionTime: 3600, // Placeholder
            };
        });
    }
    /**
     * Get incident timeline
     */
    async getIncidentTimeline(incidentId) {
        try {
            const response = await this.apiClient.get(`/log_entries`, {
                params: {
                    incident_id: incidentId,
                    include: ['services', 'users'],
                },
            });
            return response.data.log_entries;
        }
        catch (error) {
            throw new Error(`Failed to get timeline: ${error instanceof Error ? error.message : 'Unknown'}`);
        }
    }
    /**
     * Create incident
     */
    async createIncident(serviceId, title, details, urgency = 'high', userId) {
        const response = await this.apiClient.post('/incidents', {
            incidents: [
                {
                    type: 'incident',
                    title,
                    description: details,
                    urgency,
                    service: { id: serviceId, type: 'service_reference' },
                    assignments: userId
                        ? [
                            {
                                assignee: { id: userId, type: 'user_reference' },
                            },
                        ]
                        : undefined,
                },
            ],
        });
        return response.data.incidents[0];
    }
    /**
     * Get incident status
     */
    async getIncidentStatus(incidentId) {
        const incident = await this.getIncident(incidentId);
        const timeline = await this.getIncidentTimeline(incidentId);
        return {
            status: incident.status,
            assignee: incident.assignments[0]?.assignee.summary || null,
            duration: Math.floor((new Date(incident.last_status_update_at).getTime() - new Date(incident.created_at).getTime()) /
                1000),
            notes: timeline.length,
        };
    }
    /**
     * Cached request
     */
    async cachedRequest(cacheKey, fetchFn) {
        const cached = this.cacheMap.get(cacheKey);
        if (cached && Date.now() - cached.timestamp < this.cacheExpiry) {
            return cached.data;
        }
        const data = await fetchFn();
        this.cacheMap.set(cacheKey, { data, timestamp: Date.now() });
        return data;
    }
    /**
     * Invalidate cache
     */
    invalidateCache(cacheKey) {
        this.cacheMap.delete(cacheKey);
    }
    /**
     * Clear all cache
     */
    clearCache() {
        this.cacheMap.clear();
    }
}
export default PagerDutyClient;
//# sourceMappingURL=pagerduty-client.js.map