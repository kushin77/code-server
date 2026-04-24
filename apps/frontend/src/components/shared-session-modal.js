// @file        apps/frontend/src/components/shared-session-modal.tsx
// @module      components/shared-session-modal
// @description Modal for displaying and managing shared IDE sessions
import React, { useState, useEffect } from 'react';
import { Dialog, DialogTitle, DialogContent, DialogActions, Button, TextField, Chip, Box, Typography, CircularProgress, Alert, } from '@mui/material';
import { ContentCopy, OpenInNew, Delete } from '@mui/icons-material';
/**
 * Shared Session Modal Component
 *
 * Displays:
 * - Session ID and creation info
 * - Share URL with copy button
 * - Expiration time
 * - Repository path (if applicable)
 * - Join button linking to shared session
 * - Revoke option (admin only)
 */
export const SharedSessionModal = ({ open, session, onClose, onRevoke, }) => {
    const [copied, setCopied] = useState(false);
    const [revoking, setRevoking] = useState(false);
    const [error, setError] = useState(null);
    useEffect(() => {
        if (copied) {
            const timer = setTimeout(() => setCopied(false), 2000);
            return () => clearTimeout(timer);
        }
    }, [copied]);
    const handleCopyLink = async () => {
        if (session?.shareUrl) {
            try {
                await navigator.clipboard.writeText(session.shareUrl);
                setCopied(true);
            }
            catch (err) {
                setError('Failed to copy link');
            }
        }
    };
    const handleRevoke = async () => {
        if (!session || !onRevoke)
            return;
        try {
            setRevoking(true);
            await onRevoke(session.sessionId);
            onClose();
        }
        catch (err) {
            setError(`Failed to revoke session: ${err instanceof Error ? err.message : 'Unknown error'}`);
        }
        finally {
            setRevoking(false);
        }
    };
    const formatTime = (timestamp) => {
        return new Date(timestamp).toLocaleString();
    };
    const getTimeRemaining = (expiresAt) => {
        const remaining = expiresAt - Date.now();
        if (remaining < 0)
            return 'Expired';
        const hours = Math.floor(remaining / (1000 * 60 * 60));
        const minutes = Math.floor((remaining % (1000 * 60 * 60)) / (1000 * 60));
        if (hours > 0) {
            return `${hours}h ${minutes}m remaining`;
        }
        return `${minutes}m remaining`;
    };
    return (<Dialog open={open} onClose={onClose} maxWidth="sm" fullWidth>
      <DialogTitle>Shared IDE Session</DialogTitle>
      <DialogContent>
        {error && (<Alert severity="error" onClose={() => setError(null)} sx={{ mb: 2 }}>
            {error}
          </Alert>)}

        {session ? (<Box sx={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
            {/* Session ID */}
            <Box>
              <Typography variant="subtitle2" color="textSecondary">
                Session ID
              </Typography>
              <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                <TextField fullWidth value={session.sessionId} readOnly size="small" variant="outlined"/>
                <Button size="small" startIcon={<ContentCopy />} onClick={() => {
                navigator.clipboard.writeText(session.sessionId);
                setCopied(true);
            }}>
                  Copy
                </Button>
              </Box>
            </Box>

            {/* Share URL */}
            <Box>
              <Typography variant="subtitle2" color="textSecondary">
                Share Link
              </Typography>
              <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                <TextField fullWidth value={session.shareUrl} readOnly size="small" variant="outlined"/>
                <Button size="small" startIcon={copied ? undefined : <ContentCopy />} onClick={handleCopyLink} color={copied ? 'success' : 'primary'}>
                  {copied ? 'Copied!' : 'Copy'}
                </Button>
              </Box>
            </Box>

            {/* Created By */}
            <Box>
              <Typography variant="subtitle2" color="textSecondary">
                Created By
              </Typography>
              <Typography variant="body2">{session.createdBy.userName}</Typography>
            </Box>

            {/* Creation Time */}
            <Box>
              <Typography variant="subtitle2" color="textSecondary">
                Created At
              </Typography>
              <Typography variant="body2">{formatTime(session.createdAt)}</Typography>
            </Box>

            {/* Expiration */}
            <Box>
              <Typography variant="subtitle2" color="textSecondary">
                Expires
              </Typography>
              <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                <Typography variant="body2">{formatTime(session.expiresAt)}</Typography>
                <Chip size="small" label={getTimeRemaining(session.expiresAt)} color={Date.now() > session.expiresAt ? 'error' : 'primary'}/>
              </Box>
            </Box>

            {/* Repository Path */}
            {session.repositoryPath && (<Box>
                <Typography variant="subtitle2" color="textSecondary">
                  Repository
                </Typography>
                <Typography variant="body2" sx={{ fontFamily: 'monospace' }}>
                  {session.repositoryPath}
                </Typography>
              </Box>)}

            {/* Channel ID */}
            <Box>
              <Typography variant="subtitle2" color="textSecondary">
                Slack Channel
              </Typography>
              <Typography variant="body2" sx={{ fontFamily: 'monospace' }}>
                #{session.channelId}
              </Typography>
            </Box>

            {/* Info */}
            <Alert severity="info">
              This session is temporary and will auto-terminate when the last user disconnects or after
              24 hours, whichever comes first.
            </Alert>
          </Box>) : (<Box sx={{ display: 'flex', justifyContent: 'center', p: 2 }}>
            <CircularProgress />
          </Box>)}
      </DialogContent>

      <DialogActions>
        {onRevoke && session && (<Button onClick={handleRevoke} disabled={revoking} startIcon={revoking ? <CircularProgress size={20}/> : <Delete />} color="error">
            {revoking ? 'Revoking...' : 'Revoke'}
          </Button>)}

        {session?.shareUrl && (<Button onClick={() => window.open(session.shareUrl, '_blank')} startIcon={<OpenInNew />} color="primary">
            Join Session
          </Button>)}

        <Button onClick={onClose} variant="outlined">
          Close
        </Button>
      </DialogActions>
    </Dialog>);
};
export default SharedSessionModal;
//# sourceMappingURL=shared-session-modal.js.map