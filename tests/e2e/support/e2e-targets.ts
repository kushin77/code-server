// @file        tests/e2e/support/e2e-targets.ts
// @module      testing/e2e/support
// @description Shared helpers for external E2E target handling
// @governance  GOV-002

import { existsSync } from "fs";
import http from "http";
import https from "https";
import path from "path";

const QA_SESSION_PATH = path.resolve(process.cwd(), "auth", "qa-session.json");

export function resolveQaSessionState(): string | undefined {
  return existsSync(QA_SESSION_PATH) ? QA_SESSION_PATH : undefined;
}

export async function isUrlReachable(url: string, timeoutMs = 5_000): Promise<boolean> {
  const parsedUrl = new URL(url);
  const requestModule = parsedUrl.protocol === "http:" ? http : https;
  const ignoreSsl = process.env.IGNORE_SSL === "1";

  return await new Promise((resolve) => {
    const request = requestModule.request(
      {
        method: "GET",
        hostname: parsedUrl.hostname,
        port: parsedUrl.port || undefined,
        path: `${parsedUrl.pathname}${parsedUrl.search}`,
        rejectUnauthorized: parsedUrl.protocol === "https:" ? !ignoreSsl : undefined,
      },
      (response) => {
        response.resume();
        resolve(response.statusCode !== undefined && response.statusCode > 0);
      }
    );

    request.setTimeout(timeoutMs, () => {
      request.destroy();
      resolve(false);
    });

    request.on("error", () => resolve(false));
    request.end();
  });
}