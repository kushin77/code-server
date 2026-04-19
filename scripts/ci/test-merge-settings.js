#!/usr/bin/env node
// @file        scripts/ci/test-merge-settings.js
// @module      ci/test
// @description Unit tests for scripts/lib/merge-settings.js

"use strict";

const { stripJsonComments, deepMerge, applyLockedKeys, clone, LOCKED_KEYS } =
  require("../lib/merge-settings");

let passed = 0;
let failed = 0;

function assert(name, condition, detail = "") {
  if (condition) {
    console.log(`  PASS  ${name}`);
    passed++;
  } else {
    console.error(`  FAIL  ${name}${detail ? ": " + detail : ""}`);
    failed++;
  }
}

function eq(a, b) {
  return JSON.stringify(a) === JSON.stringify(b);
}

// ── stripJsonComments ────────────────────────────────────────────────────────
console.log("\n[stripJsonComments]");
assert(
  "removes line comments",
  stripJsonComments('{"a":1 // comment\n}') === '{"a":1 \n}'
);
assert(
  "removes block comments",
  stripJsonComments('{"a":/* removed */1}') === '{"a":1}'
);
assert(
  "preserves comment chars inside strings",
  stripJsonComments('"http://example.com"') === '"http://example.com"'
);

// ── deepMerge ────────────────────────────────────────────────────────────────
console.log("\n[deepMerge]");
assert(
  "user values win over enterprise for non-locked keys",
  eq(deepMerge({ a: 1 }, { a: 2 }), { a: 2 })
);
assert(
  "enterprise keys not in user are preserved",
  eq(deepMerge({ a: 1, b: 2 }, { a: 9 }), { a: 9, b: 2 })
);
assert(
  "nested objects are merged recursively",
  eq(deepMerge({ x: { a: 1, b: 2 } }, { x: { b: 9 } }), { x: { a: 1, b: 9 } })
);
assert(
  "arrays are replaced not merged",
  eq(deepMerge({ arr: [1, 2] }, { arr: [3] }), { arr: [3] })
);
assert(
  "null value from overlay applied",
  eq(deepMerge({ a: 1 }, { a: null }), { a: null })
);
assert("empty overlay returns clone of base", eq(deepMerge({ a: 1 }, {}), { a: 1 }));
assert("empty base returns clone of overlay", eq(deepMerge({}, { a: 1 }), { a: 1 }));

// ── clone ────────────────────────────────────────────────────────────────────
console.log("\n[clone]");
const orig = { a: [1, 2], b: { c: 3 } };
const cloned = clone(orig);
cloned.a.push(99);
cloned.b.c = 99;
assert("clone isolates arrays", orig.a.length === 2);
assert("clone isolates nested objects", orig.b.c === 3);

// ── applyLockedKeys ──────────────────────────────────────────────────────────
console.log("\n[applyLockedKeys]");
const firstLockedKey = [...LOCKED_KEYS][0];
const enterprise = { [firstLockedKey]: "locked-val", other: "ent" };
const merged = { [firstLockedKey]: "user-val", other: "user" };
const result = applyLockedKeys(merged, enterprise);
assert(
  "locked key from enterprise overwrites user value in merged",
  result[firstLockedKey] === "locked-val"
);
assert("non-locked key is NOT overwritten by enterprise", result.other === "user");

// ── Summary ──────────────────────────────────────────────────────────────────
console.log(`\n${passed + failed} tests: ${passed} passed, ${failed} failed`);
if (failed > 0) {
  process.exit(1);
}
