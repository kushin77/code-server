import { beforeEach, describe, expect, it, vi } from 'vitest'
import { getFeatureFlagService } from "../index";

describe("FeatureFlagService", () => {
  let ff: any;
  let mockRedis: any;

  beforeEach(() => {
    // Reset singleton if necessary or use a fresh service
    mockRedis = {
      data: new Map<string, string>(),
      get: vi.fn(async (key: string) => mockRedis.data.get(key) || null),
      set: vi.fn(async (key: string, val: string) => { mockRedis.data.set(key, val); }),
      del: vi.fn(async (key: string) => { mockRedis.data.delete(key); }),
    };
    ff = getFeatureFlagService(mockRedis);
  });

  describe("isEnabled", () => {
    it("should return false if flag does not exist", async () => {
      const enabled = await ff.isEnabled("non_existent_flag");
      expect(enabled).toBe(false);
    });

    it("should return true if flag is enabled with no rollout", async () => {
      await ff.setFlag("test_flag", { enabled: true });
      const enabled = await ff.isEnabled("test_flag");
      expect(enabled).toBe(true);
    });

    it("should return false if flag is disabled", async () => {
      await ff.setFlag("test_flag", { enabled: false });
      const enabled = await ff.isEnabled("test_flag");
      expect(enabled).toBe(false);
    });

    it("should handle gradual rollout correctly", async () => {
      const flag = "rollout_flag";
      await ff.setFlag(flag, {
        enabled: true,
        rollout: { percentage: 50 },
      });

      // Test with a set of user IDs to check if rollout is roughly 50%
      // and consistent for the same user.
      const users = Array.from({ length: 100 }, (_, i) => `user_${i}`);
      const results = await Promise.all(users.map(u => ff.isEnabled(flag, u)));
      
      const enabledCount = results.filter(Boolean).length;
      
      // With MD5 hashing, it should be approximately balanced.
      // 50% rollout for user_0 might be false, user_1 might be true.
      expect(enabledCount).toBeGreaterThan(30);
      expect(enabledCount).toBeLessThan(70);

      // Verify consistency: same user gets same result
      const consistencyCheck = await ff.isEnabled(flag, "user_0");
      expect(consistencyCheck).toBe(results[0]);
    });

    it("should respect user overrides", async () => {
      const flag = "override_flag";
      await ff.setFlag(flag, {
        enabled: true,
        rollout: { 
          percentage: 0, 
          users: ["power_user"] 
        },
      });

      expect(await ff.isEnabled(flag, "power_user")).toBe(true);
      expect(await ff.isEnabled(flag, "normal_user")).toBe(false);
    });
  });

  describe("getFlagValue", () => {
    it("should return the default value if flag does not exist", async () => {
      const val = await ff.getFlagValue("some_value", "default");
      expect(val).toBe("default");
    });

    it("should return the configured value if flag exists", async () => {
      await ff.setFlag("feature_limit", { 
        enabled: true, 
        value: 100 
      });
      const val = await ff.getFlagValue("feature_limit", 50);
      expect(val).toBe(100);
    });

    it("should return correct type for complex objects", async () => {
      const configObj = { api_version: "v2", retry_count: 3 };
      await ff.setFlag("api_config", { 
        enabled: true, 
        value: configObj 
      });
      const val = await ff.getFlagValue("api_config", {});
      expect(val).toEqual(configObj);
    });
  });
});
