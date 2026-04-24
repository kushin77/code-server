// @file        apps/backend/src/services/figma-client.ts
// @module      services/figma-client
// @description Figma API client service for design integration

import axios, { AxiosInstance } from 'axios';

interface FigmaFile {
  key: string;
  name: string;
  lastModified: string;
  version: string;
  editorType: string;
}

interface FigmaComponent {
  id: string;
  key: string;
  name: string;
  description: string;
  createdAt: string;
  updatedAt: string;
  documentationLinks: Array<{ uri: string; title: string }>;
}

interface FigmaLibraryUsage {
  fileKey: string;
  componentKey: string;
  count: number;
}

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
  private apiClient: AxiosInstance;
  private cacheMap: Map<string, { data: any; timestamp: number }> = new Map();
  private cacheExpiry = 5 * 60 * 1000; // 5 minutes

  constructor(private token: string) {
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
  async getFile(fileKey: string): Promise<any> {
    return this.cachedRequest(`files/${fileKey}`, async () => {
      const response = await this.apiClient.get(`/files/${fileKey}`);
      return response.data;
    });
  }

  /**
   * List all files in team
   */
  async listFiles(teamId?: string): Promise<FigmaFile[]> {
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
  async getComponents(fileKey: string): Promise<FigmaComponent[]> {
    return this.cachedRequest(`components_${fileKey}`, async () => {
      const response = await this.apiClient.get(`/files/${fileKey}/components`);
      return response.data.components || [];
    });
  }

  /**
   * Get component library
   */
  async getComponentLibrary(teamId: string): Promise<FigmaComponent[]> {
    const cacheKey = `library_${teamId}`;

    return this.cachedRequest(cacheKey, async () => {
      const response = await this.apiClient.get(`/teams/${teamId}/components`);
      return response.data.components || [];
    });
  }

  /**
   * Get component usage in a file
   */
  async getComponentUsage(fileKey: string): Promise<Map<string, number>> {
    const file = await this.getFile(fileKey);
    const usageMap = new Map<string, number>();

    this.traverseComponentUsage(file.document, usageMap);

    return usageMap;
  }

  /**
   * Traverse document and count component usage
   */
  private traverseComponentUsage(node: any, usageMap: Map<string, number>): void {
    if (!node) return;

    // Count component instances
    if (node.type === 'INSTANCE' && node.componentId) {
      const key = node.componentId;
      usageMap.set(key, (usageMap.get(key) || 0) + 1);
    }

    // Recurse children
    if (node.children && Array.isArray(node.children)) {
      node.children.forEach((child: any) => this.traverseComponentUsage(child, usageMap));
    }
  }

  /**
   * Export node as PNG
   */
  async exportNode(fileKey: string, nodeId: string, scale: number = 1): Promise<string> {
    try {
      const response = await this.apiClient.get(`/files/${fileKey}/export`, {
        params: {
          ids: nodeId,
          format: 'png',
          scale,
        },
      });

      return response.data.exports[0].url;
    } catch (error) {
      throw new Error(`Failed to export node: ${error instanceof Error ? error.message : 'Unknown'}`);
    }
  }

  /**
   * Export node as SVG
   */
  async exportNodeSVG(fileKey: string, nodeId: string): Promise<string> {
    try {
      const response = await this.apiClient.get(`/files/${fileKey}/export`, {
        params: {
          ids: nodeId,
          format: 'svg',
        },
      });

      return response.data.exports[0].url;
    } catch (error) {
      throw new Error(`Failed to export SVG: ${error instanceof Error ? error.message : 'Unknown'}`);
    }
  }

  /**
   * Get file comments
   */
  async getComments(fileKey: string): Promise<any[]> {
    return this.cachedRequest(`comments_${fileKey}`, async () => {
      const response = await this.apiClient.get(`/files/${fileKey}/comments`);
      return response.data.comments || [];
    });
  }

  /**
   * Post comment on file
   */
  async postComment(fileKey: string, message: string, clientMeta?: any): Promise<any> {
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
  async deleteComment(fileKey: string, commentId: string): Promise<void> {
    await this.apiClient.delete(`/files/${fileKey}/comments/${commentId}`);

    // Invalidate cache
    this.invalidateCache(`comments_${fileKey}`);
  }

  /**
   * Get file version history
   */
  async getVersionHistory(fileKey: string): Promise<any[]> {
    const response = await this.apiClient.get(`/files/${fileKey}/versions`);
    return response.data.versions || [];
  }

  /**
   * Get specific version
   */
  async getVersion(fileKey: string, versionId: string): Promise<any> {
    const response = await this.apiClient.get(`/files/${fileKey}/versions/${versionId}`);
    return response.data;
  }

  /**
   * Search components across team
   */
  async searchComponents(teamId: string, query: string): Promise<FigmaComponent[]> {
    const response = await this.apiClient.get(`/teams/${teamId}/components/search`, {
      params: { q: query },
    });

    return response.data.components || [];
  }

  /**
   * Get file statistics
   */
  async getFileStats(fileKey: string): Promise<{
    totalNodes: number;
    totalComponents: number;
    totalFrames: number;
    totalComments: number;
    lastModified: string;
  }> {
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
  private countNodes(
    node: any,
    stats: { totalNodes: number; totalComponents: number; totalFrames: number }
  ): void {
    if (!node) return;

    stats.totalNodes++;

    if (node.type === 'COMPONENT') {
      stats.totalComponents++;
    } else if (node.type === 'FRAME') {
      stats.totalFrames++;
    }

    if (node.children && Array.isArray(node.children)) {
      node.children.forEach((child: any) => this.countNodes(child, stats));
    }
  }

  /**
   * Cached request with expiry
   */
  private async cachedRequest(cacheKey: string, fetchFn: () => Promise<any>): Promise<any> {
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
  private invalidateCache(cacheKey: string): void {
    this.cacheMap.delete(cacheKey);
  }

  /**
   * Clear all cache
   */
  clearCache(): void {
    this.cacheMap.clear();
  }
}

export default FigmaClient;
