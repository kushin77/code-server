import fs from "node:fs";
import path from "node:path";
import dns from "node:dns/promises";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { chromium } from "playwright";
import puppeteer from "puppeteer-core";

const execFileAsync = promisify(execFile);

const nowIso = new Date().toISOString();
const cwd = process.cwd();
const outputDir = process.env.VPN_SCAN_OUTPUT_DIR || path.join(cwd, "..", "..", "test-results", "vpn-endpoint-scan", nowIso.replace(/[:.]/g, ""));
const vpnInterface = process.env.VPN_INTERFACE || "wg0";
const configPath = process.env.VPN_SCAN_CONFIG || path.join(cwd, "endpoints.json");
const baseOverride = process.env.VPN_SCAN_BASE_URL || "";

fs.mkdirSync(outputDir, { recursive: true });
fs.mkdirSync(path.join(outputDir, "screenshots"), { recursive: true });
fs.mkdirSync(path.join(outputDir, "playwright-traces"), { recursive: true });

function writeJson(file, data) {
  fs.writeFileSync(path.join(outputDir, file), JSON.stringify(data, null, 2), "utf8");
}

function writeText(file, text) {
  fs.writeFileSync(path.join(outputDir, file), text, "utf8");
}

function logLine(message) {
  const line = `[${new Date().toISOString()}] ${message}`;
  fs.appendFileSync(path.join(outputDir, "scanner.log"), `${line}\n`, "utf8");
  process.stdout.write(`${line}\n`);
}

function isAllowedStatus(status, allowed) {
  return Array.isArray(allowed) && allowed.includes(status);
}

async function requireVpnInterface(iface) {
  try {
    await execFileAsync("ip", ["link", "show", iface]);
  } catch {
    throw new Error(`VPN interface '${iface}' not found`);
  }
}

async function routeForHost(host) {
  const { stdout } = await execFileAsync("ip", ["route", "get", host]);
  return stdout.trim().split("\n")[0];
}

async function ensureRouteViaVpn(host, iface) {
  const route = await routeForHost(host);
  if (!route.includes(` dev ${iface} `)) {
    throw new Error(`Host '${host}' is not routed over ${iface}. Route: ${route}`);
  }
  return route;
}

async function loadConfig() {
  const configRaw = fs.readFileSync(configPath, "utf8");
  const config = JSON.parse(configRaw);
  if (baseOverride) {
    config.baseUrl = baseOverride;
  }
  return config;
}

function endpointUrl(baseUrl, endpointPath) {
  return new URL(endpointPath, baseUrl).toString();
}

function isIpv4(value) {
  return /^\d{1,3}(\.\d{1,3}){3}$/.test(value);
}

async function runPlaywrightScan(config, endpoints) {
  const browser = await chromium.launch({ headless: true, args: ["--no-sandbox"] });
  const context = await browser.newContext({ ignoreHTTPSErrors: true });
  const page = await context.newPage();

  const consoleErrors = [];
  const pageErrors = [];
  const requestFailures = [];

  page.on("console", (msg) => {
    if (["error", "warning"].includes(msg.type())) {
      consoleErrors.push({ type: msg.type(), text: msg.text(), location: msg.location() });
    }
  });
  page.on("pageerror", (err) => {
    pageErrors.push({ message: err.message, stack: err.stack || "" });
  });
  page.on("requestfailed", (req) => {
    requestFailures.push({ url: req.url(), method: req.method(), failure: req.failure()?.errorText || "unknown" });
  });

  const results = [];

  for (const endpoint of endpoints) {
    const url = endpointUrl(config.baseUrl, endpoint.path);
    const tracePath = path.join(outputDir, "playwright-traces", `${endpoint.name}.zip`);
    await context.tracing.start({ screenshots: true, snapshots: true, sources: true });
    const start = Date.now();
    let status = 0;
    let navError = "";

    try {
      const response = await page.goto(url, {
        timeout: config.navigationTimeoutMs,
        waitUntil: "domcontentloaded"
      });
      status = response?.status() || 0;
      await page.screenshot({ path: path.join(outputDir, "screenshots", `playwright-${endpoint.name}.png`), fullPage: true });
    } catch (err) {
      navError = err instanceof Error ? err.message : String(err);
    }

    await context.tracing.stop({ path: tracePath });
    const durationMs = Date.now() - start;

    results.push({
      engine: "playwright",
      endpoint: endpoint.name,
      url,
      status,
      durationMs,
      allowedStatus: endpoint.allowedStatus,
      allowed: isAllowedStatus(status, endpoint.allowedStatus),
      navError,
      tracePath
    });
  }

  await browser.close();
  return {
    results,
    diagnostics: {
      consoleErrors,
      pageErrors,
      requestFailures
    }
  };
}

async function runPuppeteerScan(config, endpoints) {
  const chromiumPath = chromium.executablePath();
  const browser = await puppeteer.launch({
    executablePath: chromiumPath,
    headless: true,
    args: ["--no-sandbox", "--disable-setuid-sandbox"]
  });

  const page = await browser.newPage();
  await page.setBypassCSP(true);

  const consoleErrors = [];
  const pageErrors = [];
  const requestFailures = [];

  page.on("console", (msg) => {
    const type = msg.type();
    if (type === "error" || type === "warning") {
      consoleErrors.push({ type, text: msg.text() });
    }
  });
  page.on("pageerror", (err) => {
    pageErrors.push({ message: err.message, stack: err.stack || "" });
  });
  page.on("requestfailed", (req) => {
    requestFailures.push({ url: req.url(), method: req.method(), errorText: req.failure()?.errorText || "unknown" });
  });

  const results = [];

  for (const endpoint of endpoints) {
    const url = endpointUrl(config.baseUrl, endpoint.path);
    const start = Date.now();
    let status = 0;
    let navError = "";

    try {
      const response = await page.goto(url, {
        timeout: config.navigationTimeoutMs,
        waitUntil: "domcontentloaded"
      });
      status = response?.status() || 0;
      await page.screenshot({ path: path.join(outputDir, "screenshots", `puppeteer-${endpoint.name}.png`), fullPage: true });
    } catch (err) {
      navError = err instanceof Error ? err.message : String(err);
    }

    const durationMs = Date.now() - start;

    results.push({
      engine: "puppeteer",
      endpoint: endpoint.name,
      url,
      status,
      durationMs,
      allowedStatus: endpoint.allowedStatus,
      allowed: isAllowedStatus(status, endpoint.allowedStatus),
      navError
    });
  }

  await browser.close();
  return {
    results,
    diagnostics: {
      consoleErrors,
      pageErrors,
      requestFailures
    }
  };
}

function collectOpportunities(allResults, diagnostics, slowThresholdMs) {
  const opportunities = [];

  for (const result of allResults) {
    if (!result.allowed) {
      opportunities.push({
        severity: "high",
        type: "unexpected_status",
        endpoint: result.endpoint,
        engine: result.engine,
        detail: `Status ${result.status} not in allowed list ${JSON.stringify(result.allowedStatus)}`
      });
    }
    if (result.durationMs > slowThresholdMs) {
      opportunities.push({
        severity: "medium",
        type: "latency",
        endpoint: result.endpoint,
        engine: result.engine,
        detail: `Response time ${result.durationMs}ms exceeds threshold ${slowThresholdMs}ms`
      });
    }
    if (result.navError) {
      opportunities.push({
        severity: "high",
        type: "navigation_error",
        endpoint: result.endpoint,
        engine: result.engine,
        detail: result.navError
      });
    }
  }

  for (const [engine, diag] of Object.entries(diagnostics)) {
    if (diag.consoleErrors.length > 0) {
      opportunities.push({
        severity: "medium",
        type: "console_errors",
        engine,
        detail: `${diag.consoleErrors.length} browser console warning/error events observed`
      });
    }
    if (diag.pageErrors.length > 0) {
      opportunities.push({
        severity: "high",
        type: "page_errors",
        engine,
        detail: `${diag.pageErrors.length} uncaught page errors observed`
      });
    }
    if (diag.requestFailures.length > 0) {
      opportunities.push({
        severity: "medium",
        type: "request_failures",
        engine,
        detail: `${diag.requestFailures.length} failed browser requests observed`
      });
    }
  }

  return opportunities;
}

function buildDebugLog(diagnostics) {
  const lines = [];
  for (const [engine, diag] of Object.entries(diagnostics)) {
    lines.push(`=== ${engine.toUpperCase()} ===`);

    lines.push(`Console errors/warnings: ${diag.consoleErrors.length}`);
    for (const item of diag.consoleErrors) {
      lines.push(`  - [${item.type}] ${item.text}`);
    }

    lines.push(`Page errors: ${diag.pageErrors.length}`);
    for (const item of diag.pageErrors) {
      lines.push(`  - ${item.message}`);
    }

    lines.push(`Request failures: ${diag.requestFailures.length}`);
    for (const item of diag.requestFailures) {
      lines.push(`  - ${item.method} ${item.url} (${item.failure || item.errorText || "unknown"})`);
    }

    lines.push("");
  }
  return lines.join("\n");
}

(async function main() {
  try {
    const config = await loadConfig();
    const endpointList = Array.isArray(config.endpoints) ? config.endpoints : [];
    if (!config.baseUrl || endpointList.length === 0) {
      throw new Error("Configuration must include baseUrl and at least one endpoint");
    }

    const baseHost = new URL(config.baseUrl).hostname;

    logLine(`Starting enterprise VPN endpoint scan against ${config.baseUrl}`);
    await requireVpnInterface(vpnInterface);

    const resolvedIps = isIpv4(baseHost) ? [baseHost] : await dns.resolve4(baseHost);
    const routeEvidence = [];

    for (const ip of resolvedIps) {
      const route = await ensureRouteViaVpn(ip, vpnInterface);
      routeEvidence.push({ host: baseHost, ip, route, viaInterface: vpnInterface });
    }

    logLine(`VPN route verification complete for ${baseHost} (${resolvedIps.join(", ")})`);

    const pw = await runPlaywrightScan(config, endpointList);
    const pp = await runPuppeteerScan(config, endpointList);

    const diagnostics = {
      playwright: pw.diagnostics,
      puppeteer: pp.diagnostics
    };

    const allResults = [...pw.results, ...pp.results];
    const opportunities = collectOpportunities(allResults, diagnostics, config.slowThresholdMs || 2000);
    const hardFailures = opportunities.filter((o) => o.severity === "high").length;

    const summary = {
      status: hardFailures === 0 ? "pass" : "fail",
      startedAt: nowIso,
      finishedAt: new Date().toISOString(),
      vpn: {
        interface: vpnInterface,
        verified: true,
        routeEvidence
      },
      target: {
        baseUrl: config.baseUrl,
        endpointCount: endpointList.length
      },
      results: allResults,
      diagnosticsSummary: {
        playwright: {
          consoleErrors: diagnostics.playwright.consoleErrors.length,
          pageErrors: diagnostics.playwright.pageErrors.length,
          requestFailures: diagnostics.playwright.requestFailures.length
        },
        puppeteer: {
          consoleErrors: diagnostics.puppeteer.consoleErrors.length,
          pageErrors: diagnostics.puppeteer.pageErrors.length,
          requestFailures: diagnostics.puppeteer.requestFailures.length
        }
      },
      opportunities
    };

    writeJson("summary.json", summary);
    writeJson("diagnostics.playwright.json", diagnostics.playwright);
    writeJson("diagnostics.puppeteer.json", diagnostics.puppeteer);
    writeText("debug-errors.log", buildDebugLog(diagnostics));

    const recommendations = opportunities
      .map((o, index) => `${index + 1}. [${o.severity}] ${o.type} :: ${o.engine || "n/a"} :: ${o.endpoint || "n/a"} :: ${o.detail}`)
      .join("\n");
    writeText("opportunities.txt", recommendations || "No optimization opportunities detected in this run.");

    logLine(`Scan complete: status=${summary.status} opportunities=${opportunities.length}`);

    if (summary.status !== "pass") {
      process.exit(1);
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    writeJson("summary.json", {
      status: "fail",
      startedAt: nowIso,
      finishedAt: new Date().toISOString(),
      error: message,
      vpn: {
        interface: vpnInterface,
        verified: false
      }
    });
    writeText("debug-errors.log", `Fatal scanner error: ${message}\n`);
    process.stderr.write(`Scanner failed: ${message}\n`);
    process.exit(1);
  }
})();
