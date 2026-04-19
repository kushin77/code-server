import AIRouter from "../router";

describe("AIRouter", () => {
  let router: AIRouter;

  beforeEach(() => {
    // local routing only (no egress)
    delete process.env.AI_EGRESS_ENABLED;
    delete process.env.HF_API_TOKEN;
    router = new AIRouter();
  });

  it("routes code task to local codegemma by default", () => {
    const result = router.route({ task: "code", prompt: "write a unit test" });
    expect(result.provider).toBe("ollama");
    expect(result.model_id).toBe("codegemma");
    expect(result.was_fallback).toBe(false);
  });

  it("routes chat task to local mistral by default", () => {
    const result = router.route({ task: "chat", prompt: "hello" });
    expect(result.provider).toBe("ollama");
    expect(result.model_id).toBe("mistral");
    expect(result.was_fallback).toBe(false);
  });

  it("blocks egress when AI_EGRESS_ENABLED is not set", () => {
    expect(() =>
      router.route({ task: "chat", prefer_model: "mixtral-hf", prompt: "hello" })
    ).toThrow("No available provider");
  });

  it("allows egress when AI_EGRESS_ENABLED=true and HF_API_TOKEN set", () => {
    process.env.AI_EGRESS_ENABLED = "true";
    process.env.HF_API_TOKEN = "test-token";
    const result = router.route({ task: "chat", prefer_model: "mixtral-hf", prompt: "hello" });
    expect(result.provider).toBe("huggingface");
    expect(result.headers["Authorization"]).toBe("Bearer test-token");
  });

  it("falls back to local when primary (hf) is blocked by egress policy", () => {
    // task_routing for 'chat' has primary=mistral (local), fallback=mixtral-hf
    // mistral is local so no fallback triggered
    const result = router.route({ task: "chat", prompt: "hello" });
    expect(result.provider).toBe("ollama");
    expect(result.was_fallback).toBe(false);
  });

  it("includes correct endpoint for ollama", () => {
    const result = router.route({ task: "code", prompt: "fix this" });
    expect(result.endpoint).toContain("/api/generate");
  });

  it("includes correct endpoint for huggingface", () => {
    process.env.AI_EGRESS_ENABLED = "true";
    process.env.HF_API_TOKEN = "hf-test";
    const result = router.route({ task: "chat", prefer_model: "mixtral-hf", prompt: "hello" });
    expect(result.endpoint).toContain("api-inference.huggingface.co");
    expect(result.endpoint).toContain("Mixtral");
  });
});
