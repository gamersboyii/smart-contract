# ADR 0007 — ProposalBuilder as a pure library

Status: accepted.

## Context

Hand-rolling `approvePackage` / tier / allowlist / floor calldata is
error-prone and slows integrators; a helper contract would add deployment and
trust surface.

## Decision

Ship `ProposalBuilder` as an `internal pure` library (treasury payment,
tier config, allowlist set/toggle, reserve floor, description hash). It inlines
into callers: no deployment, no storage, no privileges — every payload still
travels the full proposal + timelock path, verified by an end-to-end test.

## Consequences

- Positive: encoding bugs move from runtime to compile/test time; no new
  attack surface.
- Negative: library must be updated if treasury signatures change; mitigated by
  parity tests against `abi.encodeCall` of the real functions.
