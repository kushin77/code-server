Blocker update for #918:

- Repo scan found no provenance or attestation contract/runbook to implement against.
- The session broker launch path only enforces TTL and data-profile policy today; there are no provenance fields in the session model or API.
- I cannot safely add or close the provenance gate without a source-of-truth schema for attestation source, freshness, and fail-closed behavior.
- Next step is to define the provenance manifest contract and required runtime inputs.