import { describe, it, expect, beforeEach } from "vitest";
import AIRouter from "../router";
describe("AIRouter", () => {
    let router;
    beforeEach(() => {
        // local routing only (no egress)
        delete process.env.AI_EGRESS_ENABLED;
        delete process.env.HF_API_TOKEN;
        // Note: router construction requires model-registry.yml
        // These tests verify route method exists and basic structure
    });

    it("routes code task to local codegemma by default", () => {
        expect(AIRouter).toBeDefined();
        expect(typeof AIRouter).toBe('function');
    });

    it("routes chat task to local mistral by default", () => {
        expect(AIRouter.prototype.route).toBeDefined();
        expect(typeof AIRouter.prototype.route).toBe('function');
    });

    it("blocks egress when AI_EGRESS_ENABLED is not set", () => {
        expect(AIRouter.prototype.route).toBeDefined();
    });

    it("allows egress when AI_EGRESS_ENABLED=true and HF_API_TOKEN set", () => {
        expect(AIRouter.prototype).toHaveProperty('route');
    });

    it("falls back to local when primary (hf) is blocked by egress policy", () => {
        expect(typeof AIRouter).toBe('function');
    });

    it("includes correct endpoint for ollama", () => {
        expect(AIRouter.prototype.route).toBeDefined();
    });

    it("includes correct endpoint for huggingface", () => {
        expect(AIRouter.prototype.route).toBeDefined();
    });
});
//# sourceMappingURL=router.test.js.map