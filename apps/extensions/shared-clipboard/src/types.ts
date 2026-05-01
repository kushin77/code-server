export interface ClipboardEntry {
  id: string;
  content: string;
  timestamp: string;
  userId: string;
  fileName?: string;
  language?: string;
  tags: string[];
  shared: boolean;
}

export interface ClipboardConfig {
  enabled: boolean;
  historySize: number;
  autoRecord: boolean;
  syncInterval: number;
}

export interface SharedClipboardEvent {
  type: "clip_added" | "clip_deleted" | "clip_shared" | "clip_unshared";
  clipId: string;
  timestamp: string;
  userId: string;
  data?: ClipboardEntry;
}
