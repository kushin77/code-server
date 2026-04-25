// @file        tests/e2e/support/e2e-targets.ts
// @module      testing/e2e/support
// @description Shared helpers for external E2E target handling
// @governance  GOV-002

import { existsSync } from "fs";
import path from "path";

const QA_SESSION_PATH = path.resolve(process.cwd(), "auth", "qa-session.json");

export function resolveQaSessionState(): string | undefined {
  return existsSync(QA_SESSION_PATH) ? QA_SESSION_PATH : undefined;
}

export async function isUrlReachable(url: string, timeoutMs = 5_000): Promise<boolean> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const response = await fetch(url, {
      method: "GET",
      redirect: "manual",
      signal: controller.signal,
    });
    return response.ok || response.status >= 300;
  } catch {
    return false;
  } finally {
    clearTimeout(timeout);
  }
}