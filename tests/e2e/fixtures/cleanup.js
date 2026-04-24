import { test as base } from '@playwright/test';
export const test = base.extend({
    qaCleanup: [
        async ({}, use) => {
            const resources = new Set();
            await use({
                track(resourceName) {
                    if (resourceName) {
                        resources.add(resourceName);
                    }
                },
                list() {
                    return Array.from(resources);
                }
            });
            for (const resourceName of resources) {
                console.log(`Cleaning up QA resource: ${resourceName}`);
            }
        },
        { auto: true }
    ]
});
//# sourceMappingURL=cleanup.js.map