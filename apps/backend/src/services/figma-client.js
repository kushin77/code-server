// @file        apps/backend/src/services/figma-client.ts
// @module      services/figma-client
// @description Figma API client service for design integration
import axios from 'axios';
/**
 * Figma API Client Service
 *
 * Provides methods for:
 * - Fetching design files and components
 * - Retrieving component libraries
 * - Managing comments on designs
 * - Exporting design assets
 * - Tracking design changes
 */
export class FigmaClient {
    constructor(token) {
        this.token = token;
        this.cacheMap = new Map();
        this.cacheExpiry = 5 * 60 * 1000; // 5 minutes
        this.apiClient = axios.create({
            baseURL: 'https://api.figma.com/v1',
            headers: {
                'X-FIGMA-TOKEN': token,
                'Content-Type': 'application/json',
            },
            timeout: 10000,
        });
    }
    /**
     * Get file metadata
     */
    async getFile(fileKey) {
        return this.cachedRequest(`files/${fileKey}`, async () => {
            const response = await this.apiClient.get(`/files/${fileKey}`);
            return response.data;
        });
    }
    /**
     * List all files in team
     */
    async listFiles(teamId) {
        const cacheKey = `files_team_${teamId || 'all'}`;
        return this.cachedRequest(cacheKey, async () => {
            const params = teamId ? { team_id: teamId } : {};
            const response = await this.apiClient.get('/files', { params });
            return response.data.files || [];
        });
    }
    /**
     * Get file components
     */
    async getComponents(fileKey) {
        return this.cachedRequest(`components_${fileKey}`, async () => {
            const response = await this.apiClient.get(`/files/${fileKey}/components`);
            return response.data.components || [];
        });
    }
    /**
     * Get component library
     */
    async getComponentLibrary(teamId) {
        const cacheKey = `library_${teamId}`;
        return this.cachedRequest(cacheKey, async () => {
            const response = await this.apiClient.get(`/teams/${teamId}/components`);
            return response.data.components || [];
        });
    }
    /**
     * Get component usage in a file
     */
    async getComponentUsage(fileKey) {
        const file = await this.getFile(fileKey);
        const usageMap = new Map();
        this.traverseComponentUsage(file.document, usageMap);
        return usageMap;
    }
    /**
     * Traverse document and count component usage
     */
    traverseComponentUsage(node, usageMap) {
        if (!node)
            return;
        // Count component instances
        if (node.type === 'INSTANCE' && node.componentId) {
            const key = node.componentId;
            usageMap.set(key, (usageMap.get(key) || 0) + 1);
        }
        // Recurse children
        if (node.children && Array.isArray(node.children)) {
            node.children.forEach((child) => this.traverseComponentUsage(child, usageMap));
        }
    }
    /**
     * Export node as PNG
     */
    async exportNode(fileKey, nodeId, scale = 1) {
        try {
            const response = await this.apiClient.get(`/files/${fileKey}/export`, {
                params: {
                    ids: nodeId,
                    format: 'png',
                    scale,
                },
            });
            return response.data.exports[0].url;
        }
        catch (error) {
            throw new Error(`Failed to export node: ${error instanceof Error ? error.message : 'Unknown'}`);
        }
    }
    /**
     * Export node as SVG
     */
    async exportNodeSVG(fileKey, nodeId) {
        try {
            const response = await this.apiClient.get(`/files/${fileKey}/export`, {
                params: {
                    ids: nodeId,
                    format: 'svg',
                },
            });
            return response.data.exports[0].url;
        }
        catch (error) {
            throw new Error(`Failed to export SVG: ${error instanceof Error ? error.message : 'Unknown'}`);
        }
    }
    /**
     * Get file comments
     */
    async getComments(fileKey) {
        return this.cachedRequest(`comments_${fileKey}`, async () => {
            const response = await this.apiClient.get(`/files/${fileKey}/comments`);
            return response.data.comments || [];
        });
    }
    /**
     * Post comment on file
     */
    async postComment(fileKey, message, clientMeta) {
        const response = await this.apiClient.post(`/files/${fileKey}/comments`, {
            message,
            client_meta: clientMeta,
        });
        // Invalidate cache
        this.invalidateCache(`comments_${fileKey}`);
        return response.data;
    }
    /**
     * Delete comment
     */
    async deleteComment(fileKey, commentId) {
        await this.apiClient.delete(`/files/${fileKey}/comments/${commentId}`);
        // Invalidate cache
        this.invalidateCache(`comments_${fileKey}`);
    }
    /**
     * Get file version history
     */
    async getVersionHistory(fileKey) {
        const response = await this.apiClient.get(`/files/${fileKey}/versions`);
        return response.data.versions || [];
    }
    /**
     * Get specific version
     */
    async getVersion(fileKey, versionId) {
        const response = await this.apiClient.get(`/files/${fileKey}/versions/${versionId}`);
        return response.data;
    }
    /**
     * Search components across team
     */
    async searchComponents(teamId, query) {
        const response = await this.apiClient.get(`/teams/${teamId}/components/search`, {
            params: { q: query },
        });
        return response.data.components || [];
    }
    /**
     * Get file statistics
     */
    async getFileStats(fileKey) {
        const file = await this.getFile(fileKey);
        const comments = await this.getComments(fileKey);
        const stats = {
            totalNodes: 0,
            totalComponents: 0,
            totalFrames: 0,
            totalComments: comments.length,
            lastModified: file.lastModified,
        };
        this.countNodes(file.document, stats);
        return stats;
    }
    /**
     * Count nodes in document tree
     */
    countNodes(node, stats) {
        if (!node)
            return;
        stats.totalNodes++;
        if (node.type === 'COMPONENT') {
            stats.totalComponents++;
        }
        else if (node.type === 'FRAME') {
            stats.totalFrames++;
        }
        if (node.children && Array.isArray(node.children)) {
            node.children.forEach((child) => this.countNodes(child, stats));
        }
    }
    /**
     * Cached request with expiry
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
export default FigmaClient;
//# sourceMappingURL=figma-client.js.map