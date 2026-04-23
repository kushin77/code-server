import { beforeEach, describe, expect, it, vi } from 'vitest';
const mockAuditService = { emit: vi.fn() };
const mockRegistry = {
    providers: {
        ollama: { base_url: 'http://localhost:11434' },
        huggingface: { base_url: 'https://api-inference.huggingface.co', api_key_env: 'HF_API_TOKEN' },
    },
    models: [],
    routing: {
        default_policy: 'local_first',
        fallback_enabled: false,
        fallback_timeout_ms: 1000,
        egress_enabled_env: 'AI_EGRESS_ENABLED',
        task_routing: {},
    },
};
vi.mock('fs', () => ({
    readFileSync: vi.fn(() => 'mock-registry'),
}));
vi.mock('js-yaml', () => ({
    default: { load: vi.fn(() => mockRegistry) },
    load: vi.fn(() => mockRegistry),
}));
vi.mock('../../audit/audit-service', () => ({
    getAuditService: () => mockAuditService,
}));
import AIRouter from '../router';
describe('AIRouter audit hook', () => {
    beforeEach(() => {
        mockAuditService.emit.mockReset();
        delete process.env.AI_EGRESS_ENABLED;
        delete process.env.HF_API_TOKEN;
    });
    it('audits the registry read when the router loads', () => {
        new AIRouter();
        expect(mockAuditService.emit).toHaveBeenCalledWith(expect.objectContaining({
            action: 'allow',
            resourceType: 'config',
            fileAction: 'read',
            method: 'READ',
        }));
    });
});
//# sourceMappingURL=audit-router.test.js.map