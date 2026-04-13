CREATE INDEX idx_workspaces_user_id ON workspaces(user_id);
CREATE INDEX idx_files_workspace_id ON files(workspace_id);
CREATE INDEX idx_sessions_user_id ON sessions(user_id);
