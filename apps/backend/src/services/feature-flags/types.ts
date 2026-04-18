/**
 * Feature flag service types.
 */

export interface FeatureFlagRollout {
  percentage: number; // 0-100
  users?: string[]; // Specific user overrides (whitelist)
}

export type FeatureFlagValue = string | number | boolean | object;

export interface FeatureFlag {
  enabled: boolean;
  rollout?: FeatureFlagRollout;
  value?: FeatureFlagValue;
}

export interface IFeatureFlagService {
  /**
   * Check if a feature flag is enabled for a specific user.
   * If userId is provided, handles gradual rollout check.
   */
  isEnabled(flag: string, userId?: string | null): Promise<boolean>;

  /**
   * Get the value of a feature flag, or a default value if not set.
   */
  getFlagValue<T extends FeatureFlagValue>(flag: string, defaultValue: T): Promise<T>;

  /**
   * Set a feature flag configuration.
   */
  setFlag(flag: string, config: FeatureFlag): Promise<void>;

  /**
   * Delete a feature flag.
   */
  deleteFlag(flag: string): Promise<void>;
}
