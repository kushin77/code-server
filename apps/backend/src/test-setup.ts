import { vi } from "vitest";

// Alias jest to vi for backward compatibility with jest-style test files
(globalThis as Record<string, unknown>).jest = vi;
