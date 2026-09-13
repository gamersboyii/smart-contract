# ADR 0010 — Delegate script with inline broadcast call

Status: accepted.

## Context

Voting power requires delegation before the proposal snapshot; holders need a
copy/paste path, and the delegation call must execute AS the holder.

## Decision

Ship `script/Delegate.s.sol` with the `token.delegate` call inline in `run()`
(under `--broadcast` forge submits it from the broadcaster EOA) rather than
behind a helper-contract call, which would silently delegate the intermediary's
zero votes. The only branching logic (DELEGATEE env override vs
self-delegation default) lives in a separately testable `resolveDelegatee`.

## Consequences

- Positive: no silent no-op footgun; env default covered by test.
- Negative: script pattern differs slightly from `Renounce.s.sol` (which can
  safely use a helper because its checks are views); documented in NatSpec.
  Tests avoid parallel-unsafe env sharing: exactly one test touches DELEGATEE.
