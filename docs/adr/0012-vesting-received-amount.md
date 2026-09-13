# ADR 0012 — Vesting records actually-received tokens

Status: accepted.

## Context

`create()` recorded the requested amount while pulling via `transferFrom`, so
fee-on-transfer tokens created insolvent schedules (phantom allocations that
late claims could never pay).

## Decision

Measure the balance delta around `safeTransferFrom` and record `received`;
revert if zero arrived. Standard tokens are unaffected (delta equals amount);
fee tokens now vest exactly what arrived. Pinned by a 5%-fee-token test that
also documents the second-order effect (claims themselves pay the fee).

## Consequences

- Positive: closes the insolvency class for a two-call cost (~5k gas).
- Negative: the emitted `totalAmount` may differ from the requested amount for
  fee tokens — indexers must read the event, not the input (documented in
  `docs/INTEGRATION.md` vesting lifecycle).
