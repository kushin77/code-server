# Status update for #908

The public session route is now wired to its own handler at `/s/:sessionId` in `apps/session-broker/src/index.ts`, and the destroy endpoint has been restored to a normal termination path instead of absorbing public-link traffic.

Validation:
- `npm exec --prefix apps/session-broker -- vitest run src/session-public-route.spec.ts src/session-provenance.spec.ts src/session-deletion.spec.ts src/session-metrics.spec.ts` passed
- `npm exec --prefix apps/session-broker -- tsc -p apps/session-broker/tsconfig.json --noEmit` passed
- `get_errors` is clean for `apps/session-broker/src/index.ts` and the related session-broker helper files

Remaining blocker:
- live end-to-end verification against the deployed `dev.kushnir.cloud` surface still needs to be executed before closing #908.
