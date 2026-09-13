# ADR 0006 — Standalone vesting with funder-held revocation

Status: accepted.

## Context

The toolkit had no token-distribution primitive; every DAO needs team/investor
vesting with frontend-readable claimability.

## Decision

Ship `DAOStreamVesting` as a standalone contract: linear release with cliff,
`claim`/`claimable`/`vested` views plus `VestingCreated/VestedClaimed/
VestingRevoked` events. No roles, no governance coupling — each schedule's
trust boundary is funder <-> beneficiary, and the revoker is the funding
`msg.sender` (multisig or treasury batch), never a global admin. Revocation
returns only the unvested portion; vested tokens stay claimable. A DAO funds a
schedule from the treasury via an approve-then-create batch (documented in
`docs/INTEGRATION.md`).

## Consequences

- Positive: existing treasury/governor storage untouched; zero new global
  trust; revocation cannot claw back vested pay.
- Negative: treasury funding takes two packages (approve + create) instead of
  one; mitigated by atomic `executePackages` with predecessor ordering.
