# ADR 0002 — DAOReadHub as a stateless view aggregator

Status: accepted.

## Context

Frontends needed ~10 RPCs across four contracts to render one proposal or
package card, inviting inconsistent off-chain reimplementations of readiness
logic.

## Decision

Ship `DAOReadHub` as a separate stateless contract (immutable governor +
treasury pointers, zero storage, no roles, view-only) rather than adding views
to the core contracts. It mirrors `_executePackage` checks descriptively and
derives token/timelock handles from the governor to minimize misconfiguration.

## Consequences

- Positive: one RPC per card; core contract storage and attack surface
  untouched; hub can be redeployed/extended without touching governance.
- Negative: readiness is descriptive, not a dry-run guarantee (target may still
  revert); documented in NatSpec. A stale hub pointing at old contracts is
  possible — deployments must record the hub address alongside the stack.
