// @file        apps/frontend/src/extensions/pagerduty-incidents.ts
// @module      extensions/pagerduty-incidents
// @description PagerDuty incident fetching and API utilities
import axios from 'axios';
export function createPagerDutyApiClient(token) {
    return axios.create({
        baseURL: 'https://api.pagerduty.com',
        headers: {
            Authorization: `Token token=${token}`,
            Accept: 'application/vnd.pagerduty+json;version=2',
            'Content-Type': 'application/json',
        },
        timeout: 10000,
    });
}
export async function fetchPagerDutyIncidents(config, status, apiClient = createPagerDutyApiClient(config.token)) {
    try {
        const params = {
            limit: 25,
            include: ['assignees', 'services'],
            sort_by: 'created_at:desc',
        };
        if (status) {
            params.statuses = [status];
        }
        const response = await apiClient.get('/incidents', { params });
        const incidents = Array.isArray(response.data?.incidents) ? response.data.incidents : [];
        // Calculate stats from incidents
        const stats = {
            triggered: 0,
            acknowledged: 0,
            resolved: 0,
            total: incidents.length,
        };
        for (const incident of incidents) {
            const inc_status = incident.status;
            if (inc_status === 'triggered')
                stats.triggered++;
            else if (inc_status === 'acknowledged')
                stats.acknowledged++;
            else if (inc_status === 'resolved')
                stats.resolved++;
        }
        const mapped = incidents.map((incident, index) => ({
            id: String(incident.id ?? incident.incident_number ?? index),
            incident_number: Number(incident.incident_number ?? 0),
            title: String(incident.title ?? incident.summary ?? 'Untitled incident'),
            status: (incident.status ?? 'triggered'),
            urgency: (incident.urgency ?? 'high'),
            created_at: String(incident.created_at ?? ''),
            last_status_update_at: String(incident.last_status_update_at ?? ''),
            html_url: incident.html_url,
            service: {
                id: String(incident.service?.id ?? ''),
                summary: String(incident.service?.summary ?? 'Unknown service'),
            },
            assignees: Array.isArray(incident.assignments)
                ? incident.assignments.map((a) => ({
                    summary: String(a.assignee?.summary ?? a.assignee?.name ?? 'Unassigned'),
                    email: String(a.assignee?.email ?? ''),
                }))
                : [],
            total_affected_services: 1,
        }));
        return { incidents: mapped, stats };
    }
    catch (error) {
        throw new Error(`Failed to fetch PagerDuty incidents: ${error instanceof Error ? error.message : 'Unknown error'}`);
    }
}
export async function acknowledgeIncident(incidentId, userId, config, apiClient = createPagerDutyApiClient(config.token)) {
    try {
        const response = await apiClient.put(`/incidents/${incidentId}`, {
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
        const incident = response.data?.incidents?.[0];
        return {
            id: String(incident?.id ?? incidentId),
            incident_number: Number(incident?.incident_number ?? 0),
            title: String(incident?.title ?? ''),
            status: incident?.status ?? 'acknowledged',
            urgency: incident?.urgency ?? 'high',
            created_at: String(incident?.created_at ?? ''),
            last_status_update_at: String(incident?.last_status_update_at ?? ''),
            html_url: incident?.html_url,
            service: {
                id: String(incident?.service?.id ?? ''),
                summary: String(incident?.service?.summary ?? ''),
            },
            assignees: [],
        };
    }
    catch (error) {
        throw new Error(`Failed to acknowledge incident: ${error instanceof Error ? error.message : 'Unknown error'}`);
    }
}
export async function resolveIncident(incidentId, config, apiClient = createPagerDutyApiClient(config.token)) {
    try {
        const response = await apiClient.put(`/incidents/${incidentId}`, {
            incidents: [
                {
                    id: incidentId,
                    type: 'incident_reference',
                    status: 'resolved',
                },
            ],
        });
        const incident = response.data?.incidents?.[0];
        return {
            id: String(incident?.id ?? incidentId),
            incident_number: Number(incident?.incident_number ?? 0),
            title: String(incident?.title ?? ''),
            status: incident?.status ?? 'resolved',
            urgency: incident?.urgency ?? 'high',
            created_at: String(incident?.created_at ?? ''),
            last_status_update_at: String(incident?.last_status_update_at ?? ''),
            html_url: incident?.html_url,
            service: {
                id: String(incident?.service?.id ?? ''),
                summary: String(incident?.service?.summary ?? ''),
            },
            assignees: [],
        };
    }
    catch (error) {
        throw new Error(`Failed to resolve incident: ${error instanceof Error ? error.message : 'Unknown error'}`);
    }
}
//# sourceMappingURL=pagerduty-incidents.js.map