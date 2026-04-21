// @file        apps/frontend/src/extensions/figma-embed.tsx
// @module      extensions/figma-embed
// @description Figma design embed panel for viewing and commenting on designs in IDE

import React, { useState, useEffect, useCallback } from 'react';
import {
  Panel,
  PanelHeader,
  PanelBody,
  Button,
  TextInput,
  Spinner,
  Alert,
  Badge,
  Box,
  Flex,
} from '@primer/react';
import axios, { AxiosInstance } from 'axios';

interface FigmaFile {
  key: string;
  name: string;
  lastModified: string;
  thumbnailUrl: string;
  version: string;
  editorType: string;
}

interface FigmaNode {
  id: string;
  name: string;
  type: string;
  description?: string;
  x?: number;
  y?: number;
  width?: number;
  height?: number;
  absoluteBoundingBox?: {
    x: number;
    y: number;
    width: number;
    height: number;
  };
  visible?: boolean;
}

interface FigmaComment {
  id: string;
  user: {
    id: string;
    handle: string;
    imgUrl: string;
  };
  text: string;
  createdAt: string;
  resolvedAt?: string;
  clientMeta?: {
    nodeId?: string;
    x?: number;
    y?: number;
  };
}

interface FigmaConfig {
  token: string;
  personalToken?: string;
  fileKey?: string;
  teamId?: string;
}

/**
 * Figma Embed Panel Component
 *
 * Features:
 * - View Figma design files in IDE side panel
 * - Real-time design preview
 * - Browse design components and frames
 * - View and add comments on designs
 * - Quick links to Figma for detailed edits
 * - Design version history
 */
export const FigmaEmbedPanel: React.FC = () => {
  const [config, setConfig] = useState<FigmaConfig | null>(null);
  const [apiClient, setApiClient] = useState<AxiosInstance | null>(null);
  const [files, setFiles] = useState<FigmaFile[]>([]);
  const [selectedFile, setSelectedFile] = useState<FigmaFile | null>(null);
  const [nodes, setNodes] = useState<FigmaNode[]>([]);
  const [comments, setComments] = useState<FigmaComment[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [commentText, setCommentText] = useState('');
  const [selectedNode, setSelectedNode] = useState<FigmaNode | null>(null);

  // Load configuration
  useEffect(() => {
    loadConfig();
  }, []);

  // Initialize API client when config loads
  useEffect(() => {
    if (config?.token) {
      const client = axios.create({
        baseURL: 'https://api.figma.com/v1',
        headers: {
          'X-FIGMA-TOKEN': config.token,
          'Content-Type': 'application/json',
        },
        timeout: 10000,
      });
      setApiClient(client);
      fetchFiles();
    }
  }, [config]);

  /**
   * Load Figma configuration from VS Code settings
   */
  const loadConfig = useCallback(() => {
    // In real implementation, would call VS Code API
    const token = localStorage.getItem('figma.token');
    const fileKey = localStorage.getItem('figma.fileKey');

    if (token) {
      setConfig({ token, fileKey });
    } else {
      setError('Figma token not configured. Open settings to configure.');
    }
  }, []);

  /**
   * Fetch list of Figma files
   */
  const fetchFiles = useCallback(async () => {
    if (!apiClient) return;

    try {
      setLoading(true);
      setError(null);

      // Get files from team or recent files
      const response = await apiClient.get('/files', {
        params: { team_id: config?.teamId },
      });

      setFiles(response.data.files || []);
    } catch (err) {
      setError(`Failed to fetch files: ${err instanceof Error ? err.message : 'Unknown error'}`);
      console.error('[Figma] Error fetching files:', err);
    } finally {
      setLoading(false);
    }
  }, [apiClient, config?.teamId]);

  /**
   * Fetch nodes (components, frames) from selected file
   */
  const fetchFileNodes = useCallback(
    async (fileKey: string) => {
      if (!apiClient) return;

      try {
        setLoading(true);
        setError(null);

        const response = await apiClient.get(`/files/${fileKey}`);
        const fileData = response.data;

        // Extract nodes from document tree
        const extractedNodes = extractNodes(fileData.document);
        setNodes(extractedNodes);
        setSelectedFile(files.find((f) => f.key === fileKey) || null);

        // Fetch comments for this file
        await fetchFileComments(fileKey);
      } catch (err) {
        setError(`Failed to fetch file: ${err instanceof Error ? err.message : 'Unknown error'}`);
        console.error('[Figma] Error fetching file:', err);
      } finally {
        setLoading(false);
      }
    },
    [apiClient, files]
  );

  /**
   * Extract nodes from Figma document tree
   */
  const extractNodes = (node: any, nodes: FigmaNode[] = []): FigmaNode[] => {
    if (!node) return nodes;

    // Add current node if it's relevant (frames, components, etc.)
    if (
      node.type === 'FRAME' ||
      node.type === 'COMPONENT' ||
      node.type === 'COMPONENT_SET' ||
      node.type === 'INSTANCE'
    ) {
      nodes.push({
        id: node.id,
        name: node.name,
        type: node.type,
        description: node.description,
        absoluteBoundingBox: node.absoluteBoundingBox,
        visible: node.visible !== false,
      });
    }

    // Recursively process children
    if (node.children && Array.isArray(node.children)) {
      node.children.forEach((child: any) => extractNodes(child, nodes));
    }

    return nodes;
  };

  /**
   * Fetch comments for file
   */
  const fetchFileComments = useCallback(
    async (fileKey: string) => {
      if (!apiClient) return;

      try {
        const response = await apiClient.get(`/files/${fileKey}/comments`);
        setComments(response.data.comments || []);
      } catch (err) {
        console.error('[Figma] Error fetching comments:', err);
        // Don't fail if comments fail to load
      }
    },
    [apiClient]
  );

  /**
   * Add comment to design
   */
  const handleAddComment = useCallback(async () => {
    if (!apiClient || !selectedFile || !commentText.trim()) return;

    try {
      setLoading(true);

      await apiClient.post(`/files/${selectedFile.key}/comments`, {
        message: commentText,
        client_meta: selectedNode
          ? {
              node_id: selectedNode.id,
              x: selectedNode.absoluteBoundingBox?.x || 0,
              y: selectedNode.absoluteBoundingBox?.y || 0,
            }
          : undefined,
      });

      setCommentText('');
      await fetchFileComments(selectedFile.key);
    } catch (err) {
      setError(`Failed to post comment: ${err instanceof Error ? err.message : 'Unknown error'}`);
    } finally {
      setLoading(false);
    }
  }, [apiClient, selectedFile, selectedNode, commentText]);

  /**
   * Open file in Figma
   */
  const handleOpenInFigma = useCallback(() => {
    if (selectedFile) {
      window.open(`https://figma.com/file/${selectedFile.key}`, '_blank');
    }
  }, [selectedFile]);

  /**
   * Get design statistics
   */
  const getStatistics = useCallback(() => {
    return {
      totalFrames: nodes.filter((n) => n.type === 'FRAME').length,
      totalComponents: nodes.filter((n) => n.type === 'COMPONENT' || n.type === 'COMPONENT_SET')
        .length,
      totalComments: comments.length,
      unresolvedComments: comments.filter((c) => !c.resolvedAt).length,
    };
  }, [nodes, comments]);

  if (!config?.token) {
    return (
      <Box p={3}>
        <Alert variant="warning">
          Figma token not configured. Open settings to enable design integration.
        </Alert>
      </Box>
    );
  }

  const stats = getStatistics();

  return (
    <Box p={3}>
      <Panel>
        <PanelHeader>
          <Box display="flex" justifyContent="space-between" alignItems="center" width="100%">
            <span>Figma Designs</span>
            <Button size="small" onClick={fetchFiles} disabled={loading}>
              {loading ? <Spinner size="small" /> : 'Refresh'}
            </Button>
          </Box>
        </PanelHeader>

        <PanelBody>
          {error && (
            <Alert variant="error" onClose={() => setError(null)}>
              {error}
            </Alert>
          )}

          {/* File List */}
          {!selectedFile ? (
            <Box>
              <Box mb={2}>
                <strong>Design Files</strong>
              </Box>
              {files.length === 0 ? (
                <p>No Figma files found.</p>
              ) : (
                files.map((file) => (
                  <Box
                    key={file.key}
                    p={2}
                    mb={2}
                    style={{
                      border: '1px solid #e1e4e8',
                      borderRadius: '6px',
                      cursor: 'pointer',
                      transition: 'background 0.2s',
                    }}
                    onClick={() => fetchFileNodes(file.key)}
                  >
                    {file.thumbnailUrl && (
                      <img
                        src={file.thumbnailUrl}
                        alt={file.name}
                        style={{ width: '100%', marginBottom: '8px', borderRadius: '4px' }}
                      />
                    )}
                    <div style={{ fontWeight: 'bold' }}>{file.name}</div>
                    <div style={{ fontSize: '12px', color: '#666' }}>
                      Modified: {new Date(file.lastModified).toLocaleDateString()}
                    </div>
                  </Box>
                ))
              )}
            </Box>
          ) : (
            <Box>
              {/* File Header */}
              <Flex mb={2} justifyContent="space-between" alignItems="center">
                <Box>
                  <Button size="small" onClick={() => setSelectedFile(null)}>
                    ← Back
                  </Button>
                </Box>
                <Button size="small" onClick={handleOpenInFigma}>
                  Open in Figma
                </Button>
              </Flex>

              {/* File Info */}
              <Box mb={3} p={2} style={{ background: '#f6f8fa', borderRadius: '4px' }}>
                <div style={{ fontWeight: 'bold', marginBottom: '4px' }}>{selectedFile.name}</div>
                <Flex gap={2}>
                  <Badge>{stats.totalFrames} frames</Badge>
                  <Badge>{stats.totalComponents} components</Badge>
                  <Badge variant="attention">{stats.unresolvedComments} comments</Badge>
                </Flex>
              </Box>

              {/* Nodes List */}
              <Box mb={3}>
                <Box mb={2}>
                  <strong>Components & Frames</strong>
                </Box>
                {nodes.length === 0 ? (
                  <p>No components or frames found.</p>
                ) : (
                  nodes.map((node) => (
                    <Box
                      key={node.id}
                      p={2}
                      mb={1}
                      style={{
                        border: selectedNode?.id === node.id ? '2px solid #0366d6' : 'none',
                        background: selectedNode?.id === node.id ? '#f1f4f8' : undefined,
                        borderRadius: '4px',
                        cursor: 'pointer',
                      }}
                      onClick={() => setSelectedNode(node)}
                    >
                      <div style={{ fontWeight: 'bold' }}>{node.name}</div>
                      <div style={{ fontSize: '12px', color: '#666' }}>{node.type}</div>
                    </Box>
                  ))
                )}
              </Box>

              {/* Comments Section */}
              <Box mb={3}>
                <Box mb={2}>
                  <strong>Comments ({comments.length})</strong>
                </Box>

                {/* Add Comment */}
                <Box mb={2} p={2} style={{ background: '#f6f8fa', borderRadius: '4px' }}>
                  <TextInput
                    placeholder="Add a comment..."
                    value={commentText}
                    onChange={(e: any) => setCommentText(e.target.value)}
                    disabled={loading}
                    block
                    mb={1}
                  />
                  <Button
                    size="small"
                    onClick={handleAddComment}
                    disabled={!commentText.trim() || loading}
                  >
                    {loading ? 'Posting...' : 'Post Comment'}
                  </Button>
                </Box>

                {/* Comments List */}
                {comments.map((comment) => (
                  <Box
                    key={comment.id}
                    p={2}
                    mb={1}
                    style={{ border: '1px solid #e1e4e8', borderRadius: '4px' }}
                  >
                    <Flex mb={1} alignItems="center" gap={1}>
                      <img
                        src={comment.user.imgUrl}
                        alt={comment.user.handle}
                        style={{ width: '24px', height: '24px', borderRadius: '50%' }}
                      />
                      <strong>{comment.user.handle}</strong>
                      {comment.resolvedAt && <Badge>Resolved</Badge>}
                    </Flex>
                    <div>{comment.text}</div>
                    <div style={{ fontSize: '12px', color: '#666', marginTop: '4px' }}>
                      {new Date(comment.createdAt).toLocaleString()}
                    </div>
                  </Box>
                ))}
              </Box>
            </Box>
          )}
        </PanelBody>
      </Panel>
    </Box>
  );
};

export default FigmaEmbedPanel;
