# ADR 0011 — Storage packing with a golden layout test

Status: accepted.

## Context

`Package.expiresAt` occupied a near-empty slot and `TierConfig` spanned three
slots. Packing saves ~20k gas per approval but field order becomes
load-bearing.

## Decision

Reorder to `Package{…, executeAfter, expiresAt, tier, executed, cancelled, …}`
(15 bytes, one slot) and `TierConfig{delay, enabled, maxNativeValue}` (two
slots), and pin the layout with `test/TreasuryStorageLayout.t.sol`, which
decodes raw `vm.load` slots and fails loudly on any reorder. Safe only because
nothing is proxied (see SECURITY.md upgradeability statement); all
`tierConfig(...)` destructuring sites (contracts, tests, scripts) updated to
the new member order.

## Consequences

- Positive: one fewer cold SSTORE per approval; layout drift is now a test
  failure, not a silent regression.
- Negative: the golden test hardcodes mapping slots (tierConfig=3,
  _packages=4) — appending state is fine, reordering state requires updating
  the test (intended friction).
