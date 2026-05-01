// Status bar tile configuration and types

export interface TileConfig {
  type: "pr" | "ci" | "incidents" | "team-online";
  enabled: boolean;
  refreshInterval: number;
}

export interface StatusTileData {
  icon: string;
  label: string;
  tooltip: string;
  color?: "green" | "yellow" | "red";
  count?: number;
  command?: string;
}

export interface PRTile extends StatusTileData {
  type: "pr";
  unreadReviews: number;
  assignedPRs: number;
}

export interface CITile extends StatusTileData {
  type: "ci";
  status: "passing" | "failing" | "pending";
  branch: string;
  failureCount: number;
}

export interface IncidentTile extends StatusTileData {
  type: "incidents";
  activeIncidents: number;
  severity: "critical" | "high" | "medium" | "low";
}

export interface TeamOnlineTile extends StatusTileData {
  type: "team-online";
  onlineCount: number;
  totalTeamSize: number;
}
