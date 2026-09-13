# ADR 0005 — Examples as runnable tests plus a cast cookbook

Status: accepted.

## Context

Single-transaction `forge script` examples cannot cross the timelock delay and
tier quarantine, so literal scripts would either be pseudo-code or require a
live deployment with manual waiting.

## Decision

Deliver Flows A–C as executable tests (`test/Examples.t.sol`, warping past the
delays with identical API calls) plus `docs/CAST.md` phased live-chain commands
for real deployments. Both use only real repository APIs.

## Consequences

- Positive: examples are CI-verified on every run; operators get copy/paste
  live commands. No fake functionality.
- Negative: tests are not deploy scripts; mitigated by the cookbook mapping
  each test phase to its live command.
