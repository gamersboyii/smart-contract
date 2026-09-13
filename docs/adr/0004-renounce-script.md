# ADR 0004 — Wiring-verified renounce script

Status: accepted.

## Context

The deployer retains the timelock `DEFAULT_ADMIN_ROLE` after `Deploy.s.sol`,
with renunciation as a printed manual step (AUDIT M3) — a forgotten step means
single-key governance capture.

## Decision

Keep renunciation manual (so misconfiguration stays correctable) but ship
`script/Renounce.s.sol`, which re-asserts the full wiring (governor
proposer/canceller, open executor, treasury-governance binding, governor-timelock
binding, caller-is-admin) and reverts loudly on any mismatch before renouncing.
Re-running after sealing reverts with `AdminNotHeld`, doubling as a sealed-state
proof.

## Consequences

- Positive: the footgun becomes a checklist with a machine-enforced gate.
- Negative: still relies on the operator running it; mitigated by
  `docs/DEPLOYMENT.md` ordering (fund only after sealing) and RUNBOOK checks.
