import { test, expect } from '@playwright/test';
test.describe('E2E Framework Validation', () => {
    test('sanity check: test framework initializes', async () => {
        // This test just verifies the framework can run
        expect(true).toBe(true);
    });
    test('sanity check: environment variables accessible', async () => {
        const email = process.env.E2E_USER_EMAIL;
        const baseUrl = process.env.BASE_URL;
        expect(email).toBeDefined();
        expect(baseUrl).toBeDefined();
    });
});
//# sourceMappingURL=sanity-check.spec.js.map