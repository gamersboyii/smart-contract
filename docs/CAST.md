# Cast cookbook — live-chain operations

All commands assume the deployed addresses are exported. Nothing here needs a
custom script; every step is one `cast` call. Time-delayed steps (vote windows,
timelock delay, tier quarantine) are separate commands because no single
transaction can cross them — see `test/Examples.t.sol` for the same flows
executed in-process with `warp`.

```bash
export TOKEN=<token> GOVERNOR=<governor> TIMELOCK=<timelock>
export TREASURY=<treasury> HUB=<readhub> RPC=<rpc-url>
```

## Delegation

```bash
# Self-delegate to activate voting power (do this before any proposal snapshot)
cast send $TOKEN "delegate(address)" $USER --rpc-url $RPC

# ...or via the script (DELEGATEE unset means self-delegation), holder's key:
TOKEN_ADDRESS=$TOKEN forge script script/Delegate.s.sol --rpc-url $RPC --broadcast
DELEGATEE=$OTHER TOKEN_ADDRESS=$TOKEN forge script script/Delegate.s.sol --rpc-url $RPC --broadcast

# Check snapshot voting power for an account at block N
cast call $TOKEN "getPastVotes(address,uint256)(uint256)" $USER $N --rpc-url $RPC
```

## Proposal lifecycle

```bash
# Propose is easiest from a funded thick client; minimal single-target example:
cast send $GOVERNOR "propose(address[],uint256[],bytes[],string)(uint256)" \
  "[$TREASURY]" "[0]" "[$(cast calldata 'approvePackage(address,uint256,bytes,uint8,uint48,bytes32)' $PAYEE 1000000000000000000 0x 0 0 0x0000000000000000000000000000000000000000000000000000000000000000)]" \
  "pay 1 ETH" --rpc-url $RPC

# Vote (0 = against, 1 = for, 2 = abstain)
cast send $GOVERNOR "castVote(uint256,uint8)" $PROPOSAL_ID 1 --rpc-url $RPC

# One-RPC status card (state, votes, quorum, your snapshot weight)
cast call $HUB "proposalCard(uint256,address)" $PROPOSAL_ID $USER --rpc-url $RPC

# Queue after the vote passes (needs the exact targets/values/calldatas + description)
cast send $GOVERNOR "queue(address[],uint256[],bytes[],bytes32)" \
  "[$TREASURY]" "[0]" "[$CALLDATA]" $DESCRIPTION_HASH --rpc-url $RPC

# Execute after the timelock delay (anyone can call; permissionless liveness)
cast send $GOVERNOR "execute(address[],uint256[],bytes[],bytes32)" \
  "[$TREASURY]" "[0]" "[$CALLDATA]" $DESCRIPTION_HASH --rpc-url $RPC
```

## Treasury packages

```bash
# Readiness card: executable flag, blocked reason, seconds-to-ready, predecessor state
cast call $HUB "packageStatus(bytes32)" $PACKAGE_ID --rpc-url $RPC

# Execute a ready package (permissionless; reverts before executeAfter/expiry loudly)
cast send $TREASURY "executePackage(bytes32)" $PACKAGE_ID --rpc-url $RPC

# Batch several ready packages atomically (whole batch rolls back on any failure)
cast send $TREASURY "executePackages(bytes32[])" "[$ID1,$ID2]" --rpc-url $RPC

# Finalize an expired package (anyone) or a predecessor-stuck package (anyone)
cast send $TREASURY "closeExpiredPackage(bytes32)" $PACKAGE_ID --rpc-url $RPC
cast send $TREASURY "closeStuckPackage(bytes32)" $PACKAGE_ID --rpc-url $RPC

# Treasury overview: balances, reserve floor, spendable headroom, pause state
cast call $HUB "treasurySnapshot()" --rpc-url $RPC

# Portfolio over registered assets (balance / floor / spendable per token)
cast call $HUB "treasuryPortfolio()" --rpc-url $RPC

# Scheduling dry-run: expected package id, quarantine ETA, cap/allowlist admission
cast call $HUB "schedulePreview(address,uint256,bytes,uint8)" $PAYEE 1000000000000000000 0x 0 --rpc-url $RPC

# Timelock operation state for a proposal payload (poll for readiness)
cast call $HUB "timelockStatus(address[],uint256[],bytes[],bytes32)" \
  "[$TREASURY]" "[0]" "[$CALLDATA]" $DESCRIPTION_HASH --rpc-url $RPC
```

## Vesting

```bash
export VESTING=<vesting> PAYOUT_TOKEN=<erc20>

# Create a schedule (pulls tokens via your allowance; approve first)
cast send $PAYOUT_TOKEN "approve(address,uint256)" $VESTING $AMOUNT --rpc-url $RPC
cast send $VESTING "create(address,address,uint256,uint48,uint48,uint48,bool)" \
  $BENEFICIARY $PAYOUT_TOKEN $AMOUNT $START $CLIFF $DURATION true --rpc-url $RPC

# Claimable now / release to beneficiary (permissionless poke)
cast call $VESTING "claimable(uint256)" $SCHEDULE_ID --rpc-url $RPC
cast send $VESTING "claim(uint256)" $SCHEDULE_ID --rpc-url $RPC

# Revoke (funder only; unvested returns, vested stays claimable)
cast send $VESTING "revoke(uint256)" $SCHEDULE_ID --rpc-url $RPC
```

## Emergency (guardian multisig)

```bash
# Halt execution + deposits. Unpause is governance-only (full proposal path).
cast send $TREASURY "pause()" --rpc-url $RPC

# Cancel a package during its quarantine window only (before executeAfter)
cast send $TREASURY "cancelPackage(bytes32)" $PACKAGE_ID --rpc-url $RPC
```

## Self-sovereignty (deployer, once)

```bash
TIMELOCK_ADDRESS=$TIMELOCK GOVERNOR_ADDRESS=$GOVERNOR TREASURY_ADDRESS=$TREASURY \
  forge script script/Renounce.s.sol --rpc-url $RPC --broadcast
```
