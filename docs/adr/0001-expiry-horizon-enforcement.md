# ADR 0001 — Enforce MAX_PACKAGE_EXPIRY at scheduling

Status: accepted.

## Context

`MAX_PACKAGE_EXPIRY` (365 days) was declared with NatSpec promising a scheduling
horizon, but `approvePackage` never checked it (AUDIT M1). Governance could park
a package decades ahead, contradicting the documented control.

## Decision

Enforce `expiresAt <= block.timestamp + MAX_PACKAGE_EXPIRY` for non-zero
`expiresAt` in `approvePackage`, reverting with new `ExpiryHorizonTooLong`.
Zero (no expiry) is unchanged.

## Consequences

- Positive: documented control is now real; far-future surprises impossible.
- Negative: tiers configured with near-365-day delays leave little room for an
  expiry window (use `expiresAt = 0` there). New revert path is additive-only;
  all pre-existing tests pass unchanged.
