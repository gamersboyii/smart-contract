# ADR 0003 — Permissionless stuck-package closure

Status: accepted.

## Context

A successor whose predecessor is cancelled can never execute; with
`expiresAt = 0` it was removable only by governance cancellation (AUDIT L3).
Scheduling on a cancelled predecessor compounded the problem (AUDIT L1).

## Decision

Two-sided fix: (1) `approvePackage` reverts with `PredecessorCancelled` when
the predecessor is already cancelled; (2) new permissionless
`closeStuckPackage` finalizes an already-stuck successor as cancelled
(requires an existing, cancelled predecessor, else `PredecessorNotExecuted`).
It emits the existing `PackageCancelled` event with the closer as caller.

## Consequences

- Positive: no new role, no escape hatch — anyone can clean state; finality
  invariant (executed/cancelled mutually exclusive, never executable after)
  preserved and fuzz-covered.
- Negative: one more entry point to reason about; mitigated by reusing existing
  errors/events and the same finality checks as `closeExpiredPackage`.
