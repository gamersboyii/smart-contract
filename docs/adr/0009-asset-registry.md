# ADR 0009 — Informational asset registry on the treasury

Status: accepted.

## Context

Portfolio views need a bounded, governance-curated asset set; scanning all
deposits is unreliable and unbounded loops over open-ended sets are fragile.

## Decision

Add a minimal treasury registry: `registerAsset` / `deregisterAsset`
(governance-only, swap-and-pop), `registeredAssets`, `spendableERC20`, plus
`AssetRegistered` / `AssetDeregistered` events and a one-RPC
`DAOReadHub.treasuryPortfolio`. Registration is explicitly informational —
deposits and packages involving unregistered tokens behave identically
(pinned by test). State is appended, never reordered: safe without
upgradeability concerns since nothing is proxied.

## Consequences

- Positive: bounded portfolio queries, per-token floor headroom on-chain as a
  view, indexer-friendly events.
- Negative: registry curation is a governance chore; mitigated by keeping it
  optional (empty registry changes nothing) and documenting the non-enforcement
  semantics next to the ERC20 floors.
