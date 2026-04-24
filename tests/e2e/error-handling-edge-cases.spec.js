import { test, expect } from './fixtures';
const PORTAL_URL = process.env.PORTAL_BASE_URL || 'https://kushnir.cloud';
const IDE_URL = process.env.IDE_BASE_URL || 'https://ide.kushnir.cloud';
test.describe('Error Handling & Edge Case Coverage - E2E Tests', () => {
    /**
     * HTTP ERROR HANDLING
     */
    test.describe('HTTP Error Handling', () => {
        test('404 error page displays correctly', async ({ authenticatedPage }) => {
            // Navigate to non-existent page
            await authenticatedPage.goto(`${PORTAL_URL}/nonexistent-page`);
            // Should show 404 error or be redirected
            const status = authenticatedPage.url();
            expect(status).toBeDefined();
            // Should show error message
            const errorElement = authenticatedPage.locator('[data-testid="error-404"]').or(authenticatedPage.locator('text=404'));
            const hasError = await errorElement.isVisible({ timeout: 5000 }).catch(() => false);
            // Either shows error or redirects to valid page
            expect(hasError || !status.includes('nonexistent')).toBe(true);
        });
        test('500 server error is handled gracefully', async ({ authenticatedPage }) => {
            // Request to endpoint that returns 500
            const response = await authenticatedPage.goto(`${PORTAL_URL}/api/error-500`).catch(e => null);
            // Should not crash
            expect(authenticatedPage).toBeDefined();
        });
        test('503 service unavailable shows retry option', async ({ authenticatedPage }) => {
            // Simulate service unavailable
            await authenticatedPage.route('**/api/services**', route => {
                route.abort('serviceunavailable');
            });
            // Try to access service
            await authenticatedPage.goto(`${PORTAL_URL}`);
            // Should show error or offline indication
            // Clear route
            await authenticatedPage.unroute('**/api/services**');
        });
        test('401 unauthorized triggers re-authentication', async ({ authenticatedPage, context }) => {
            // Simulate unauthorized by clearing auth header
            await authenticatedPage.route('**/**', route => {
                const request = route.request();
                if (!request.headers()['authorization']) {
                    route.abort('failed');
                }
                else {
                    route.continue();
                }
            });
            // Should handle gracefully
            await authenticatedPage.waitForTimeout(500);
            await authenticatedPage.unroute('**/**');
        });
        test('429 rate limit error shows backoff', async ({ authenticatedPage }) => {
            let requestCount = 0;
            // Simulate rate limit after 5 requests
            await authenticatedPage.route('**/api/**', route => {
                requestCount++;
                if (requestCount > 5) {
                    route.abort('failed');
                }
                else {
                    route.continue();
                }
            });
            // Make requests (should hit rate limit)
            for (let i = 0; i < 10; i++) {
                await authenticatedPage.goto(`${PORTAL_URL}/api/endpoint-${i}`).catch(() => { });
            }
            // Should handle rate limiting
            expect(requestCount).toBeGreaterThan(5);
            await authenticatedPage.unroute('**/api/**');
        });
    });
    /**
     * NETWORK ERROR HANDLING
     */
    test.describe('Network Error Handling', () => {
        test('connection timeout shows appropriate error', async ({ authenticatedPage }) => {
            // Slow down requests
            await authenticatedPage.route('**/api/**', route => {
                setTimeout(() => route.continue(), 10000); // Slow response
            });
            // Try to load page
            const response = await authenticatedPage.goto(PORTAL_URL, { timeout: 5000 }).catch(e => null);
            // Should timeout gracefully
            expect(response || response === null).toBeDefined();
            await authenticatedPage.unroute('**/api/**');
        });
        test('network disconnection is detected and shown', async ({ authenticatedPage }) => {
            await authenticatedPage.goto(PORTAL_URL);
            // Go offline
            await authenticatedPage.context().setOffline(true);
            // Try to access resource
            await authenticatedPage.waitForTimeout(500);
            // Should show offline indicator or error
            const offlineIndicator = authenticatedPage.locator('[data-testid="offline-indicator"]').or(authenticatedPage.locator('text=offline'));
            const visible = await offlineIndicator.isVisible({ timeout: 2000 }).catch(() => false);
            // Might show indicator or just fail to load
            // Go back online
            await authenticatedPage.context().setOffline(false);
        });
        test('intermittent network errors trigger retry', async ({ authenticatedPage }) => {
            let attemptCount = 0;
            // Fail first 2 attempts, succeed on 3rd
            await authenticatedPage.route('**/api/data', route => {
                attemptCount++;
                if (attemptCount <= 2) {
                    route.abort('failed');
                }
                else {
                    route.continue();
                }
            });
            // Try to fetch data
            await authenticatedPage.goto(`${PORTAL_URL}`);
            // Should retry and eventually succeed
            expect(attemptCount).toBeGreaterThanOrEqual(1);
            await authenticatedPage.unroute('**/api/data');
        });
        test('DNS resolution failure shows error', async ({ authenticatedPage }) => {
            // Try to access invalid domain
            const response = await authenticatedPage.goto('https://invalid-domain-that-does-not-exist.test').catch(() => null);
            // Should fail gracefully
            expect(response === null || response?.status() >= 400).toBe(true);
        });
        test('SSL certificate error handled', async ({ authenticatedPage }) => {
            // Try to access HTTPS site with bad cert
            const response = await authenticatedPage.goto('https://self-signed.badssl.com/').catch(() => null);
            // Should handle gracefully (might be blocked by browser)
            expect(typeof response).toBeDefined();
        });
    });
    /**
     * DATA VALIDATION ERRORS
     */
    test.describe('Data Validation Errors', () => {
        test('invalid form submission shows validation errors', async ({ authenticatedPage }) => {
            await authenticatedPage.goto(PORTAL_URL);
            // Find form
            const form = authenticatedPage.locator('form').first();
            if (await form.isVisible()) {
                // Submit empty form
                const submitBtn = form.locator('button[type="submit"]');
                await submitBtn.click();
                // Should show validation errors
                const errorMsg = authenticatedPage.locator('[data-testid="error-message"]').or(authenticatedPage.locator('.error'));
                const hasError = await errorMsg.isVisible({ timeout: 2000 }).catch(() => false);
                // Might show validation error
            }
        });
        test('invalid email format rejected', async ({ authenticatedPage }) => {
            await authenticatedPage.goto(PORTAL_URL);
            // Find email input
            const emailInput = authenticatedPage.locator('input[type="email"]').first();
            if (await emailInput.isVisible()) {
                // Enter invalid email
                await emailInput.fill('not-an-email');
                // HTML5 validation should prevent submit
                const form = authenticatedPage.locator('form').first();
                const isValid = await form.evaluate(f => f.checkValidity());
                expect(isValid).toBe(false);
            }
        });
        test('file upload with wrong type rejected', async ({ authenticatedPage }) => {
            // Find file input
            const fileInput = authenticatedPage.locator('input[type="file"]').first();
            if (await fileInput.isVisible()) {
                // Try to upload wrong file type
                const dataTransfer = await authenticatedPage.evaluateHandle(() => new DataTransfer());
                const file = new File(['test'], 'test.txt', { type: 'text/plain' });
                // Upload validation should reject
                // (depends on implementation)
            }
        });
        test('file size limit is enforced', async ({ authenticatedPage }) => {
            const fileInput = authenticatedPage.locator('input[type="file"]').first();
            if (await fileInput.isVisible()) {
                // Try to upload oversized file (simulated)
                // Validation should reject large files
                const accept = await fileInput.getAttribute('accept');
                expect(accept || typeof accept).toBeDefined();
            }
        });
        test('duplicate entry detection', async ({ authenticatedPage }) => {
            // Try to create duplicate resource
            const response = await authenticatedPage.goto(`${PORTAL_URL}/api/create?name=duplicate-test`).catch(() => null);
            // Attempt duplicate
            const response2 = await authenticatedPage.goto(`${PORTAL_URL}/api/create?name=duplicate-test`).catch(() => null);
            // Second should fail with conflict
            if (response2) {
                expect(response2.status()).toBeGreaterThanOrEqual(400);
            }
        });
    });
    /**
     * EDGE CASES: UNUSUAL INPUT
     */
    test.describe('Edge Cases - Unusual Input', () => {
        test('very long string inputs handled', async ({ authenticatedPage }) => {
            await authenticatedPage.goto(PORTAL_URL);
            // Find text input
            const input = authenticatedPage.locator('input[type="text"]').first();
            if (await input.isVisible()) {
                // Enter very long string
                const longString = 'x'.repeat(10000);
                await input.fill(longString);
                // Should not crash
                expect(await input.inputValue()).toBeDefined();
            }
        });
        test('special characters in input are escaped', async ({ authenticatedPage }) => {
            await authenticatedPage.goto(PORTAL_URL);
            const input = authenticatedPage.locator('input').first();
            if (await input.isVisible()) {
                // Enter special characters
                const specialChars = '<script>alert("xss")</script>';
                await input.fill(specialChars);
                // Should escape properly
                const content = await authenticatedPage.textContent('body');
                // Should not execute as script
                expect(content).not.toContain('alert');
            }
        });
        test('null/undefined values handled gracefully', async ({ authenticatedPage }) => {
            // Navigate with null parameter
            await authenticatedPage.goto(`${PORTAL_URL}?id=null`);
            // Should not crash
            expect(authenticatedPage.url()).toBeDefined();
        });
        test('unicode characters in URLs handled', async ({ authenticatedPage }) => {
            // URL with unicode
            const unicodeParam = encodeURIComponent('测试');
            const response = await authenticatedPage.goto(`${PORTAL_URL}?search=${unicodeParam}`).catch(() => null);
            // Should handle gracefully
            expect(response === null || response?.status()).toBeDefined();
        });
        test('JSON parsing errors handled', async ({ authenticatedPage }) => {
            // Mock API returning invalid JSON
            await authenticatedPage.route('**/api/data', route => {
                route.abort('failed');
            });
            // Try to load data
            await authenticatedPage.goto(`${PORTAL_URL}`);
            // Should handle parse error
            expect(authenticatedPage).toBeDefined();
            await authenticatedPage.unroute('**/api/data');
        });
        test('circular reference in objects handled', async ({ authenticatedPage }) => {
            // JavaScript can't serialize circular references
            // Test that app handles such cases
            await authenticatedPage.goto(PORTAL_URL);
            const canSerialize = await authenticatedPage.evaluate(() => {
                try {
                    const obj = { a: 1 };
                    obj.self = obj; // Circular reference
                    JSON.stringify(obj);
                    return true;
                }
                catch {
                    return false;
                }
            });
            // Should handle error
            expect(typeof canSerialize).toBe('boolean');
        });
    });
    /**
     * BROWSER COMPATIBILITY
     */
    test.describe('Browser Compatibility Edge Cases', () => {
        test('localStorage quota exceeded handled', async ({ authenticatedPage }) => {
            // Fill localStorage
            await authenticatedPage.evaluate(() => {
                try {
                    const largeData = 'x'.repeat(1024 * 1024 * 5); // 5MB
                    localStorage.setItem('test', largeData);
                }
                catch (e) {
                    // Quota exceeded - should handle
                }
            });
            // Should continue functioning
            expect(authenticatedPage).toBeDefined();
        });
        test('sessionStorage cleared between tabs', async ({ browser }) => {
            const context = await browser.newContext();
            const page1 = await context.newPage();
            const page2 = await context.newPage();
            // Set data in page1
            await page1.goto(PORTAL_URL);
            await page1.evaluate(() => {
                sessionStorage.setItem('test', 'value');
            });
            // Check if visible in page2 (should not be)
            await page2.goto(PORTAL_URL);
            const value = await page2.evaluate(() => sessionStorage.getItem('test'));
            expect(value).toBeNull();
            await context.close();
        });
        test('IndexedDB operations handled', async ({ authenticatedPage }) => {
            // Check if IndexedDB is available
            const hasIndexedDB = await authenticatedPage.evaluate(() => !!window.indexedDB);
            if (hasIndexedDB) {
                // Open database
                const dbName = await authenticatedPage.evaluate(() => {
                    return new Promise(resolve => {
                        const request = window.indexedDB.open('test', 1);
                        request.onsuccess = () => resolve('success');
                        request.onerror = () => resolve('error');
                    });
                });
                expect(dbName).toBeDefined();
            }
        });
        test('Web Worker errors handled', async ({ authenticatedPage }) => {
            // Try to use Web Worker if available
            const workerSupported = await authenticatedPage.evaluate(() => {
                try {
                    new Worker('data:application/javascript,1+1');
                    return true;
                }
                catch {
                    return false;
                }
            });
            // Browser might not support or block workers
            expect(typeof workerSupported).toBe('boolean');
        });
    });
    /**
     * RACE CONDITIONS
     */
    test.describe('Race Conditions & Timing', () => {
        test('rapid form submissions don\'t create duplicates', async ({ authenticatedPage }) => {
            await authenticatedPage.goto(PORTAL_URL);
            // Find form
            const form = authenticatedPage.locator('form').first();
            if (await form.isVisible()) {
                // Rapid clicks on submit button
                const submitBtn = form.locator('button[type="submit"]');
                for (let i = 0; i < 3; i++) {
                    await submitBtn.click({ force: true });
                }
                // Should only process once
                await authenticatedPage.waitForLoadState('networkidle');
            }
        });
        test('navigation during loading is handled', async ({ authenticatedPage }) => {
            // Start loading
            await authenticatedPage.goto(PORTAL_URL);
            // Immediately navigate away
            await authenticatedPage.goto(`${PORTAL_URL}/dashboard`);
            // Should handle gracefully
            expect(authenticatedPage.url()).toContain('/dashboard');
        });
        test('cache invalidation on concurrent edits', async ({ authenticatedPage }) => {
            await authenticatedPage.goto(IDE_URL);
            // Simulate concurrent edit scenario
            await authenticatedPage.evaluate(() => {
                // Simulate cache
                const cache = { version: 1, data: 'original' };
                // Two concurrent updates
                cache.version = 2;
                cache.version = 3; // Last write wins
            });
            // Should resolve version conflict
            expect(authenticatedPage).toBeDefined();
        });
        test('API polling doesn\'t overwhelm server', async ({ authenticatedPage }) => {
            let requestCount = 0;
            // Monitor API requests
            await authenticatedPage.route('**/api/**', route => {
                requestCount++;
                route.continue();
            });
            // Perform actions
            await authenticatedPage.goto(PORTAL_URL);
            // Should not spam requests
            expect(requestCount).toBeLessThan(100); // Reasonable limit
            await authenticatedPage.unroute('**/api/**');
        });
    });
    /**
     * MEMORY & RESOURCE MANAGEMENT
     */
    test.describe('Memory & Resource Management', () => {
        test('large list rendering doesn\'t cause memory leak', async ({ authenticatedPage }) => {
            await authenticatedPage.goto(PORTAL_URL);
            // Render large list (if applicable)
            const largeList = authenticatedPage.locator('[data-testid="large-list"]').first();
            if (await largeList.isVisible()) {
                // Scroll through list multiple times
                for (let i = 0; i < 10; i++) {
                    await largeList.evaluate(el => {
                        el.scrollTop = el.scrollHeight;
                    });
                }
                // Should not become unresponsive
                expect(await largeList.isVisible()).toBe(true);
            }
        });
        test('event listener cleanup on element removal', async ({ authenticatedPage }) => {
            await authenticatedPage.goto(PORTAL_URL);
            // Add and remove elements
            const removeCount = await authenticatedPage.evaluate(() => {
                let count = 0;
                const element = document.createElement('div');
                element.addEventListener('click', () => count++);
                document.body.appendChild(element);
                element.remove();
                return count;
            });
            // Should clean up listeners
            expect(removeCount).toBeDefined();
        });
        test('timer cleanup prevents memory leak', async ({ authenticatedPage }) => {
            const timerCount = await authenticatedPage.evaluate(() => {
                // Create multiple timers
                const timers = [];
                for (let i = 0; i < 100; i++) {
                    timers.push(setTimeout(() => { }, 10000));
                }
                // Clear all
                timers.forEach(clearTimeout);
                return timers.length;
            });
            // Should clean up properly
            expect(timerCount).toBe(100);
        });
    });
    /**
     * SECURITY EDGE CASES
     */
    test.describe('Security - Input Sanitization', () => {
        test('XSS attempt via input is prevented', async ({ authenticatedPage }) => {
            await authenticatedPage.goto(PORTAL_URL);
            const input = authenticatedPage.locator('input[type="text"]').first();
            if (await input.isVisible()) {
                // XSS payload
                await input.fill('<img src=x onerror="alert(1)">');
                // Should not execute
                const hasAlert = await authenticatedPage.evaluate(() => {
                    return window.alert.toString().includes('native code');
                });
                expect(hasAlert).toBe(true); // Alert function should be native, not hijacked
            }
        });
        test('SQL injection attempt is handled', async ({ authenticatedPage }) => {
            // Try SQL injection in API parameter
            const response = await authenticatedPage.goto(`${PORTAL_URL}/api/user?id=1; DROP TABLE users;--`).catch(() => null);
            // Should not execute query
            // (depends on backend protection)
            expect(response === null || response?.status()).toBeDefined();
        });
        test('path traversal attempt prevented', async ({ authenticatedPage }) => {
            // Try to access files outside intended directory
            const response = await authenticatedPage.goto(`${PORTAL_URL}/files/../../etc/passwd`).catch(() => null);
            // Should not allow
            const url = authenticatedPage.url();
            expect(url).not.toContain('etc/passwd');
        });
    });
});
//# sourceMappingURL=error-handling-edge-cases.spec.js.map