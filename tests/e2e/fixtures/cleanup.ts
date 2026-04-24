import { test as base } from '@playwright/test';

export type QaResourceTracker = {
  track(resourceName: string): void;
  list(): string[];
};

export const test = base.extend<{ qaCleanup: QaResourceTracker }>({
  qaCleanup: [
    async ({}, use) => {
      const resources = new Set<string>();

      await use({
        track(resourceName: string) {
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
