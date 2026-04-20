Blocker update for #919:

- Repo scan found no session fingerprint or replay contract/runbook to implement against.
- There is no fingerprint field in the session model or API, no replay endpoint, and no drift-report schema yet.
- I cannot safely add or close the fingerprinting/replay flow without a source-of-truth schema and replay policy.
- Next step is to define the fingerprint manifest contract and replay/drift validation rules.