# ADR 0013 — Seal pipeline: renounce stays manual, health is gated

Status: accepted.

## Context

Auto-renouncing inside `Deploy.s.sol` would remove the misconfiguration
correction window; leaving it purely manual left single-key capture skippable.

## Decision

Keep renunciation a separate transaction (`Renounce.s.sol` unchanged), but make
skipping it loud: `docs/DEPLOYMENT.md` defines a required pipeline
(deploy → renounce → health-check → fund), new view-only
`script/HealthCheck.s.sol` hard-fails with `DeployerStillAdmin` on unsealed
topologies, and `DAOReadHub.isSelfSovereign(deployer)` lets frontends banner
unsealed deployments. `Deploy.s.sol` itself is untouched — it correctly leaves
the temporary admin in place.

## Consequences

- Positive: unsealed deployments fail verification instead of passing silently;
  the correction window survives.
- Negative: one more script to run; mitigated by the single pipeline section
  operators follow top to bottom.
