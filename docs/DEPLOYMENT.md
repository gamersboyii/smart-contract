# Deployment and verification

Never rely on chain-configuration assumptions: every parameter below is explicit,
and both scripts fail loudly instead of shipping misconfiguration.

## 0. Upgradeability: none, by design

Contracts are immutable once deployed: no proxies, no `delegatecall`, no admin
upgrade keys (verified: none exist in `contracts/`). Bug fixes, parameter
changes beyond governance-controlled bounds, and feature additions require
deploying a new instance and migrating through the normal governance path —
propose, vote, queue, then execute migration packages from the old treasury to
the new one (`executePackages` with predecessor ordering streams assets
across). There is deliberately no shortcut: upgradeability would reintroduce
the god-key this architecture exists to eliminate. Price this migration cost
into incident planning.

## Pipeline (required order — funding before sealing is a defect)

```
Deploy.s.sol  ->  Renounce.s.sol  ->  HealthCheck.s.sol  ->  fund
```

`HealthCheck.s.sol` hard-fails (`DeployerStillAdmin`) on an unsealed
deployment, so a sealed-then-verified order is machine-enforced: the pipeline
cannot report healthy until renunciation is on-chain. Renouncing stays a
separate transaction (not auto-sealed inside deploy) so misconfiguration
remains correctable — but skipping it is loud, never silent.

## 1. Deploy

```bash
export INITIAL_RECIPIENT=0x...   # bootstrap multisig (receives full supply)
export GUARDIAN_ADDRESS=0x...    # emergency multisig (pause + quarantine-cancel only)
forge script script/Deploy.s.sol --rpc-url <url> --broadcast
```

Optional overrides: `TOKEN_NAME`, `TOKEN_SYMBOL`, `INITIAL_SUPPLY`,
`TIMELOCK_MIN_DELAY`, `GOV_VOTING_DELAY`, `GOV_VOTING_PERIOD`,
`GOV_QUORUM_MIN_BPS`, `GOV_QUORUM_MAX_BPS`, `GOV_THRESHOLD` (defaults in
`script/Deploy.s.sol`). Record the printed addresses; the deterministic
expectations are: quorum thresholds at `initialSupply/4` and
`initialSupply*9/10`, threshold bounds at `0.1x`/`4x`, tiers at
1/3/7/14 days with 250/100/25/5 ETH caps.

## 2. Verify (before funding)

- [ ] Timelock: Governor holds `PROPOSER_ROLE` + `CANCELLER_ROLE`, `address(0)`
      holds `EXECUTOR_ROLE`, min delay as configured.
- [ ] Treasury: `GOVERNANCE_ROLE` is exactly the timelock, `GUARDIAN_ROLE` is the
      multisig, Governor has NO direct role (only via timelock).
- [ ] Governor: `token()`, `timelock()`, voting delay/period, threshold, quorum
      ramp endpoints match the deployment inputs.
- [ ] Token: total supply minted once to `INITIAL_RECIPIENT`, no mint path.
- [ ] Guardian is a multisig, not an EOA; no deployer EOA retains any role
      except the temporary timelock admin (removed next).

## 3. Seal (self-sovereignty)

```bash
TIMELOCK_ADDRESS=<t> GOVERNOR_ADDRESS=<g> TREASURY_ADDRESS=<tr> \
  forge script script/Renounce.s.sol --rpc-url <url> --broadcast
```

The script re-runs the wiring checks above and reverts on any mismatch, then
renounces the deployer admin. Re-running afterwards reverts with `AdminNotHeld`
(proof of sealed state). Testnet first; verify the sealed state with
`cast call $TIMELOCK "hasRole(bytes32,address)" $ADMIN_ROLE $DEPLOYER`
expecting `false`.

## 4. Fund

Only after sealing: move assets per policy, set the destination allowlist and
reserve floors through governance proposals (never by direct admin action —
none exists).

## 5. Recommended hardening profile (capture resistance)

Tier caps bound loss *per package*, not cumulatively — N packages in one
proposal drain N×cap, and the Low tier moves 250 ETH after a 1-day quarantine.
Before funding each of the following through governance proposals:

- Enable the destination allowlist (`setTargetAllowlistEnabled(true)`) with
  exactly the known payee/utility contracts listed. This is the single highest
  value containment boundary under full governance capture.
- Set `nativeReserveFloor` to the treasury's must-never-spend balance.
- Route any payment above the Low cap through the High/Critical tiers (smaller
  caps, longer detection windows).
- Confirm `DAOReadHub.isSelfSovereign(deployer)` returns true from the
  frontend integration (banner `false` as unsealed).
