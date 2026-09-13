# ADR 0008 — Timelock and schedule views on the ReadHub

Status: accepted.

## Context

Keepers and UIs could not answer "when is this proposal executable?" or "what
would scheduling this package produce?" without indexing events and
reimplementing id math.

## Decision

Extend `DAOReadHub` (still view-only, no storage/roles) with `schedulePreview`
(package-id commitment against the current nonce, quarantine estimate, cap and
allowlist admission; treasury-identical `InvalidTier` on bad tiers) and
`timelockStatus` (exact operation id via `hashOperationBatch(..., 0,
bytes20(governor) ^ descriptionHash)`, pending/ready/done flags, ETA).

## Consequences

- Positive: polling keepers need no event pipeline; preview ids are exact when
  no package interleaves (documented best-effort caveat).
- Negative: preview staleness under nonce contention; callers scheduling
  back-to-back must re-preview (documented in NatSpec).
