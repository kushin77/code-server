/**
 * Help Queue Service
 * SOC2-grade audit logging for help requests, assignments, responses
 */
import { EventEmitter } from 'events';
/**
 * Help Queue Service
 * Manage help requests with SOC2-grade audit logging
 */
export class HelpQueueService extends EventEmitter {
    constructor(config, auditService) {
        super();
        this.isInitialized = false;
        this.requests = new Map();
        this.experts = new Map();
        this.responses = new Map();
        this.auditLog = new Map();
        this.settings = new Map();
        this.assignments = new Map();
        this.stats = {
            totalRequests: 0,
            requestsByType: {},
            requestsByStatus: {},
            requestsByPriority: {},
            requestsByUser: {},
            averageResolutionTime: 0,
            averageRating: 0,
            totalExperts: 0,
            expertsByLevel: {},
            activeRequests: 0,
            resolvedRequests: 0,
            averageResponseTime: 0,
            totalResponses: 0,
        };
        this.auditService = auditService;
        this.config = {
            enabled: true,
            auditLoggingEnabled: true,
            maxRequestsPerUser: 10,
            maxRequestsPerDay: 5,
            assignmentTimeout: 3600000, // 1 hour
            responseTimeout: 86400000, // 24 hours
            retentionDays: 90,
            notificationsEnabled: true,
            maxAuditLogSize: 10000,
            enableExpertRating: true,
            enableRequestRating: true,
            ...config,
        };
    }
    /**
     * Initialize service
     */
    async initialize() {
        if (this.isInitialized)
            return;
        this.isInitialized = true;
        this.emit('initialized');
    }
    /**
     * Shutdown service
     */
    async shutdown() {
        this.emit('shutdown');
    }
    /**
     * Create help request
     */
    async createRequest(userId, userEmail, type, title, description, priority = 'normal', code, codeLanguage, context, workspaceId, sessionId, ipAddress, userAgent) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        const request = {
            id: `req-${Date.now()}-${Math.random().toString(36).slice(2, 9)}`,
            userId,
            userEmail,
            type,
            title,
            description,
            code,
            codeLanguage,
            context,
            priority,
            createdAt: Date.now(),
            updatedAt: Date.now(),
            status: 'open',
            workspaceId,
            sessionId,
        };
        this.requests.set(request.id, request);
        // Log audit entry
        const auditEntry = {
            id: `audit-${request.id}`,
            requestId: request.id,
            userId,
            userEmail,
            userRole: 'requester',
            operation: 'created',
            status: 'success',
            ipAddress,
            userAgent,
            timestamp: Date.now(),
            resourceType: 'help-request',
            resourceId: request.id,
            details: { type, priority },
        };
        await this.logAudit(userId, auditEntry);
        if (this.auditService) {
            this.auditService.emit({
                userId,
                action: 'create',
                resourceType: 'help-request',
                resource: `help-request:${request.id}`,
                metadata: {
                    type,
                    priority,
                    title,
                    workspaceId,
                    sessionId,
                },
                reason: 'SOC2: Help Queue request creation',
            });
        }
        this.updateStats();
        this.emit('request-created', { request });
        return request;
    }
    /**
     * Register expert
     */
    async registerExpert(userId, email, name, expertise, skills, ipAddress, userAgent) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        const expert = {
            id: `expert-${userId}-${Date.now()}`,
            userId,
            email,
            name,
            expertise,
            skills,
            registeredAt: Date.now(),
            activeRequests: 0,
            totalResolved: 0,
            averageResolutionTime: 0,
            rating: 0,
            isActive: true,
        };
        this.experts.set(expert.id, expert);
        // Log audit entry
        const auditEntry = {
            id: `audit-${expert.id}`,
            requestId: '',
            userId,
            userEmail: email,
            userRole: 'expert',
            operation: 'expert-registered',
            status: 'success',
            ipAddress,
            userAgent,
            timestamp: Date.now(),
            resourceType: 'help-expert',
            resourceId: expert.id,
            details: { expertise, skills },
        };
        await this.logAudit(userId, auditEntry);
        if (this.auditService) {
            this.auditService.emit({
                userId,
                action: 'create',
                resourceType: 'help-expert',
                resource: `help-expert:${expert.id}`,
                metadata: {
                    expertise,
                    skills,
                    email,
                    name,
                },
                reason: 'SOC2: Help Queue expert registration',
            });
        }
        this.updateStats();
        this.emit('expert-registered', { expert });
        return expert;
    }
    /**
     * Get request
     */
    async getRequest(requestId) {
        return this.requests.get(requestId);
    }
    /**
     * Get expert
     */
    async getExpert(expertId) {
        return this.experts.get(expertId);
    }
    /**
     * Query requests
     */
    async queryRequests(query) {
        let results = Array.from(this.requests.values());
        // Filter by user
        if (query.userId) {
            results = results.filter((r) => r.userId === query.userId);
        }
        // Filter by type
        if (query.type) {
            results = results.filter((r) => r.type === query.type);
        }
        // Filter by status
        if (query.status) {
            results = results.filter((r) => r.status === query.status);
        }
        // Filter by priority
        if (query.priority) {
            results = results.filter((r) => r.priority === query.priority);
        }
        // Filter by time range
        if (query.startTime) {
            results = results.filter((r) => r.createdAt >= query.startTime);
        }
        if (query.endTime) {
            results = results.filter((r) => r.createdAt <= query.endTime);
        }
        // Sort
        const sortBy = query.sortBy || 'created';
        const sortOrder = query.sortOrder === 'asc' ? 1 : -1;
        results.sort((a, b) => {
            let aVal = a.createdAt;
            let bVal = b.createdAt;
            if (sortBy === 'updated') {
                aVal = a.updatedAt;
                bVal = b.updatedAt;
            }
            else if (sortBy === 'priority') {
                const priorityOrder = { low: 0, normal: 1, high: 2, urgent: 3 };
                aVal = priorityOrder[a.priority];
                bVal = priorityOrder[b.priority];
            }
            else if (sortBy === 'status') {
                aVal = a.status;
                bVal = b.status;
            }
            if (aVal < bVal)
                return -sortOrder;
            if (aVal > bVal)
                return sortOrder;
            return 0;
        });
        // Paginate
        const limit = query.limit || 20;
        const offset = query.offset || 0;
        const paginated = results.slice(offset, offset + limit);
        return {
            requests: paginated,
            total: results.length,
            limit,
            offset,
        };
    }
    /**
     * Assign request to expert
     */
    async assignRequest(requestId, expertId, assignerId, assignerEmail, ipAddress, userAgent) {
        const request = this.requests.get(requestId);
        if (!request)
            throw new Error(`Request not found: ${requestId}`);
        const expert = this.experts.get(expertId);
        if (!expert)
            throw new Error(`Expert not found: ${expertId}`);
        // Update request
        request.assignedExpertId = expertId;
        request.assignedExpertEmail = expert.email;
        request.assignedAt = Date.now();
        request.status = 'assigned';
        request.updatedAt = Date.now();
        // Update expert
        expert.activeRequests++;
        // Log audit entry
        const auditEntry = {
            id: `audit-${requestId}-assign`,
            requestId,
            userId: assignerId,
            userEmail: assignerEmail,
            userRole: 'admin',
            operation: 'assigned',
            status: 'success',
            ipAddress,
            userAgent,
            timestamp: Date.now(),
            resourceType: 'help-request',
            resourceId: requestId,
            details: { expertId, expertEmail: expert.email },
            newStatus: 'assigned',
            previousStatus: 'open',
        };
        await this.logAudit(requestId, auditEntry);
        if (this.auditService) {
            this.auditService.emit({
                userId: assignerId,
                action: 'update',
                resourceType: 'help-request',
                resource: `help-request:${requestId}`,
                metadata: {
                    expertId,
                    expertEmail: expert.email,
                    previousStatus: 'open',
                    newStatus: 'assigned',
                },
                reason: 'SOC2: Help Queue request assignment',
            });
        }
        this.updateStats();
        this.emit('request-assigned', { request, expert });
        return request;
    }
    /**
     * Add response to request
     */
    async addResponse(requestId, responderId, responderEmail, responderRole, message, code, codeLanguage, isResolution = false, ipAddress, userAgent) {
        const request = this.requests.get(requestId);
        if (!request)
            throw new Error(`Request not found: ${requestId}`);
        const response = {
            id: `resp-${Date.now()}-${Math.random().toString(36).slice(2, 9)}`,
            requestId,
            responderId,
            responderEmail,
            responderRole,
            message,
            code,
            codeLanguage,
            createdAt: Date.now(),
            isResolution,
        };
        this.responses.set(response.id, response);
        // Update request
        request.updatedAt = Date.now();
        if (isResolution) {
            request.status = 'resolved';
            request.resolvedAt = Date.now();
        }
        else if (request.status === 'open' && responderRole === 'expert') {
            request.status = 'in-progress';
        }
        // Log audit entry
        const auditEntry = {
            id: `audit-${response.id}`,
            requestId,
            userId: responderId,
            userEmail: responderEmail,
            userRole: responderRole,
            operation: 'responded',
            status: 'success',
            ipAddress,
            userAgent,
            timestamp: Date.now(),
            resourceType: 'help-response',
            resourceId: response.id,
            details: { isResolution, messageLength: message.length },
            previousStatus: request.status === 'resolved' ? request.status : undefined,
            newStatus: isResolution ? 'resolved' : request.status,
        };
        await this.logAudit(requestId, auditEntry);
        if (this.auditService) {
            this.auditService.emit({
                userId: responderId,
                action: 'create',
                resourceType: 'help-response',
                resource: `help-response:${response.id}`,
                metadata: {
                    requestId,
                    responderRole,
                    isResolution,
                    messageLength: message.length,
                },
                reason: 'SOC2: Help Queue response creation',
            });
        }
        this.updateStats();
        this.emit('response-added', { response });
        return response;
    }
    /**
     * Resolve request
     */
    async resolveRequest(requestId, expertId, expertEmail, resolutionNotes, ipAddress, userAgent) {
        const request = this.requests.get(requestId);
        if (!request)
            throw new Error(`Request not found: ${requestId}`);
        request.status = 'resolved';
        request.resolvedAt = Date.now();
        request.resolutionNotes = resolutionNotes;
        request.updatedAt = Date.now();
        // Update expert
        if (request.assignedExpertId) {
            const expert = this.experts.get(request.assignedExpertId);
            if (expert) {
                expert.totalResolved++;
                expert.activeRequests = Math.max(0, expert.activeRequests - 1);
                if (request.resolvedAt && request.assignedAt) {
                    const resolutionTime = request.resolvedAt - request.assignedAt;
                    const newAvg = (expert.averageResolutionTime * (expert.totalResolved - 1) + resolutionTime) /
                        expert.totalResolved;
                    expert.averageResolutionTime = newAvg;
                }
            }
        }
        // Log audit entry
        const auditEntry = {
            id: `audit-${requestId}-resolve`,
            requestId,
            userId: expertId,
            userEmail: expertEmail,
            userRole: 'expert',
            operation: 'resolved',
            status: 'success',
            ipAddress,
            userAgent,
            timestamp: Date.now(),
            resourceType: 'help-request',
            resourceId: requestId,
            details: { resolutionNotesLength: resolutionNotes.length },
            previousStatus: 'in-progress',
            newStatus: 'resolved',
        };
        await this.logAudit(requestId, auditEntry);
        if (this.auditService) {
            this.auditService.emit({
                userId: expertId,
                action: 'update',
                resourceType: 'help-request',
                resource: `help-request:${requestId}`,
                metadata: {
                    previousStatus: 'in-progress',
                    newStatus: 'resolved',
                    resolutionNotesLength: resolutionNotes.length,
                },
                reason: 'SOC2: Help Queue request resolution',
            });
        }
        this.updateStats();
        this.emit('request-resolved', { request });
        return request;
    }
    /**
     * Rate request resolution
     */
    async rateResolution(requestId, rating, feedback, ipAddress, userAgent) {
        if (!this.config.enableRequestRating) {
            throw new Error('Rating is disabled');
        }
        const request = this.requests.get(requestId);
        if (!request)
            throw new Error(`Request not found: ${requestId}`);
        if (request.status !== 'resolved')
            throw new Error('Can only rate resolved requests');
        request.rating = Math.min(5, Math.max(1, rating));
        request.feedback = feedback;
        request.updatedAt = Date.now();
        // Update expert rating
        if (request.assignedExpertId) {
            const expert = this.experts.get(request.assignedExpertId);
            if (expert) {
                const responses = Array.from(this.requests.values()).filter((r) => r.assignedExpertId === expert.id && r.rating !== undefined);
                const totalRating = responses.reduce((sum, r) => sum + (r.rating || 0), 0);
                expert.rating = totalRating / responses.length;
            }
        }
        // Log audit entry
        const auditEntry = {
            id: `audit-${requestId}-rate`,
            requestId,
            userId: request.userId,
            userEmail: request.userEmail,
            userRole: 'requester',
            operation: 'rated',
            status: 'success',
            ipAddress,
            userAgent,
            timestamp: Date.now(),
            resourceType: 'help-request',
            resourceId: requestId,
            details: { rating, feedbackLength: feedback?.length || 0 },
        };
        await this.logAudit(requestId, auditEntry);
        this.updateStats();
        this.emit('request-rated', { request });
        return request;
    }
    /**
     * Get audit log for request
     */
    async getAuditLog(requestId, limit) {
        const log = this.auditLog.get(requestId) || [];
        if (limit) {
            return log.slice(-limit);
        }
        return log;
    }
    /**
     * Get expert stats
     */
    async getExpertStats(expertId) {
        const expert = this.experts.get(expertId);
        if (!expert)
            throw new Error(`Expert not found: ${expertId}`);
        const requests = Array.from(this.requests.values()).filter((r) => r.assignedExpertId === expertId);
        const skillsUsed = {};
        for (const skill of expert.skills) {
            skillsUsed[skill] = 0;
        }
        for (const request of requests) {
            if (request.type) {
                skillsUsed[request.type] = (skillsUsed[request.type] || 0) + 1;
            }
        }
        return {
            expertId,
            totalAssigned: requests.length,
            totalResolved: expert.totalResolved,
            averageResolutionTime: expert.averageResolutionTime,
            averageRating: expert.rating,
            activeRequests: expert.activeRequests,
            skillsUsed,
        };
    }
    /**
     * Get user settings
     */
    async getSettings(userId) {
        return this.settings.get(userId);
    }
    /**
     * Update user settings
     */
    async updateSettings(userId, settings) {
        let userSettings = this.settings.get(userId);
        if (!userSettings) {
            userSettings = {
                userId,
                emailNotifications: this.config.notificationsEnabled,
                pushNotifications: this.config.notificationsEnabled,
                slackIntegration: false,
                privacyLevel: 'internal',
                showProfile: true,
                allowExpertContact: true,
                createdAt: Date.now(),
                updatedAt: Date.now(),
            };
        }
        userSettings = {
            ...userSettings,
            ...settings,
            userId,
            updatedAt: Date.now(),
        };
        this.settings.set(userId, userSettings);
        this.emit('settings-updated', { userId });
        return userSettings;
    }
    /**
     * Get statistics
     */
    async getStatistics() {
        return { ...this.stats };
    }
    /**
     * Get all requests
     */
    async getAllRequests() {
        return Array.from(this.requests.values());
    }
    /**
     * Get all experts
     */
    async getAllExperts() {
        return Array.from(this.experts.values());
    }
    /**
     * Get responses for request
     */
    async getResponses(requestId) {
        return Array.from(this.responses.values()).filter((r) => r.requestId === requestId);
    }
    /**
     * Private: Log audit entry
     */
    async logAudit(key, entry) {
        let log = this.auditLog.get(key);
        if (!log) {
            log = [];
            this.auditLog.set(key, log);
        }
        log.push(entry);
        // Keep only maxAuditLogSize entries
        if (log.length > this.config.maxAuditLogSize) {
            log.splice(0, log.length - this.config.maxAuditLogSize);
        }
        this.emit('audit-logged', { key, entry });
    }
    /**
     * Private: Update statistics
     */
    updateStats() {
        this.stats.totalRequests = this.requests.size;
        this.stats.totalExperts = this.experts.size;
        // Initialize counts
        this.stats.requestsByType = {};
        this.stats.requestsByStatus = {};
        this.stats.requestsByPriority = {};
        this.stats.requestsByUser = {};
        this.stats.expertsByLevel = {};
        let totalResolutionTime = 0;
        let resolvedCount = 0;
        let totalRating = 0;
        let ratedCount = 0;
        let totalResponseTime = 0;
        let responseCount = 0;
        this.stats.activeRequests = 0;
        this.stats.resolvedRequests = 0;
        for (const request of this.requests.values()) {
            // Type
            this.stats.requestsByType[request.type] =
                (this.stats.requestsByType[request.type] || 0) + 1;
            // Status
            this.stats.requestsByStatus[request.status] =
                (this.stats.requestsByStatus[request.status] || 0) + 1;
            // Priority
            this.stats.requestsByPriority[request.priority] =
                (this.stats.requestsByPriority[request.priority] || 0) + 1;
            // User
            this.stats.requestsByUser[request.userId] =
                (this.stats.requestsByUser[request.userId] || 0) + 1;
            // Active requests
            if (request.status === 'open' || request.status === 'assigned' || request.status === 'in-progress') {
                this.stats.activeRequests++;
            }
            // Resolved
            if (request.status === 'resolved') {
                this.stats.resolvedRequests++;
            }
            // Resolution time
            if (request.resolvedAt && request.assignedAt) {
                totalResolutionTime += request.resolvedAt - request.assignedAt;
                resolvedCount++;
            }
            // Rating
            if (request.rating) {
                totalRating += request.rating;
                ratedCount++;
            }
            // Response time
            if (request.status === 'in-progress' && request.assignedAt) {
                totalResponseTime += Date.now() - request.assignedAt;
                responseCount++;
            }
        }
        this.stats.averageResolutionTime = resolvedCount > 0 ? totalResolutionTime / resolvedCount : 0;
        this.stats.averageRating = ratedCount > 0 ? totalRating / ratedCount : 0;
        this.stats.averageResponseTime = responseCount > 0 ? totalResponseTime / responseCount : 0;
        for (const expert of this.experts.values()) {
            this.stats.expertsByLevel[expert.expertise] =
                (this.stats.expertsByLevel[expert.expertise] || 0) + 1;
        }
        this.stats.totalResponses = this.responses.size;
    }
    static getInstance(config) {
        if (!HelpQueueService.instance) {
            HelpQueueService.instance = new HelpQueueService(config);
        }
        return HelpQueueService.instance;
    }
}
//# sourceMappingURL=help-queue-service.js.map