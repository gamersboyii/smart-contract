// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EnterpriseDAO} from "./EnterpriseDAO.sol";
import {DAOTreasuryExecutionEngine} from "./DAOTreasuryExecutionEngine.sol";

/// @title DAOReadHub
/// @notice Stateless read-only aggregator for governance and treasury frontends.
/// @dev No storage, no roles, no fund movement. Every function is `view` and mirrors
///      the state checks of the underlying contracts so a UI can render proposal and
///      package cards in one RPC instead of reconstructing state from many calls.
///      Readiness here is descriptive, not a dry-run guarantee: the target call itself
///      may still revert at execution time.
contract DAOReadHub {
    EnterpriseDAO public immutable governor;
    DAOTreasuryExecutionEngine public immutable treasury;

    uint8 public constant READY = 0;
    uint8 public constant FINALIZED = 1;
    uint8 public constant NOT_READY = 2;
    uint8 public constant EXPIRED = 3;
    uint8 public constant PREDECESSOR = 4;
    uint8 public constant PAUSED = 5;
    uint8 public constant RESERVE = 6;

    /// @notice One-RPC governance card for a proposal plus a voter's position at snapshot.
    struct ProposalCard {
        uint256 snapshot;
        uint256 deadline;
        IGovernor.ProposalState state;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        uint256 quorumRequired;
        uint256 accountWeight;
        bool hasVoted;
        bool needsQueuing;
    }

    /// @notice One-RPC execution card for a treasury package.
    /// @dev `blockedReason` is one of the READY/FINALIZED/NOT_READY/EXPIRED/PREDECESSOR/
    ///      PAUSED/RESERVE constants. `secondsToReady` is 0 unless blocked on the delay.
    struct PackageStatus {
        address target;
        uint256 value;
        uint8 tier;
        uint48 executeAfter;
        uint48 expiresAt;
        bytes32 predecessor;
        bool executed;
        bool cancelled;
        bool predecessorExecuted;
        bool predecessorCancelled;
        bool executable;
        uint8 blockedReason;
        uint48 secondsToReady;
    }

    /// @notice One-RPC treasury balance overview.
    struct TreasurySnapshot {
        uint256 ethBalance;
        uint256 nativeFloor;
        uint256 spendable;
        bool paused;
        uint256 nextNonce;
        bool allowlistEnabled;
    }

    /// @notice Dry-run preview of a treasury scheduling call (no state change).
    /// @dev `previewId` commits to the CURRENT nonce and is exact only if no package
    ///      is scheduled first; `executeAfter` assumes approval in this block.
    struct SchedulePreview {
        bytes32 previewId;
        uint48 executeAfter;
        bool withinCap;
        bool targetAllowed;
        uint256 tierCap;
    }

    /// @notice Timelock operation state for a governor proposal's payload.
    struct TimelockStatus {
        bytes32 operationId;
        bool pending;
        bool ready;
        bool done;
        uint256 eta;
    }

    /// @notice One-RPC portfolio row per registered asset: balance, floor, headroom.
    struct AssetPosition {
        address token;
        uint256 balance;
        uint256 floor;
        uint256 spendable;
    }

    constructor(EnterpriseDAO governor_, DAOTreasuryExecutionEngine treasury_) {
        governor = governor_;
        treasury = treasury_;
    }

    /// @notice Governance card: votes, quorum, state, and the account's snapshot weight.
    /// @dev `quorumRequired`/`accountWeight` read historical checkpoints at `snapshot`;
    ///      while the proposal is still Pending (snapshot in the future) both report 0.
    function proposalCard(uint256 proposalId, address account) external view returns (ProposalCard memory card) {
        uint256 snapshot = governor.proposalSnapshot(proposalId);
        card.snapshot = snapshot;
        card.deadline = governor.proposalDeadline(proposalId);
        card.state = governor.state(proposalId);
        (card.againstVotes, card.forVotes, card.abstainVotes) = governor.proposalVotes(proposalId);
        card.hasVoted = governor.hasVoted(proposalId, account);
        card.needsQueuing = governor.proposalNeedsQueuing(proposalId);
        if (governor.clock() > snapshot) {
            card.quorumRequired = governor.quorum(snapshot);
            card.accountWeight = governor.getVotes(account, snapshot);
        }
    }

    /// @notice Execution card: mirrors `_executePackage` checks plus pause state.
    function packageStatus(bytes32 packageId) external view returns (PackageStatus memory s) {
        DAOTreasuryExecutionEngine.Package memory pkg = treasury.getPackage(packageId);
        s.target = pkg.target;
        s.value = pkg.value;
        s.tier = pkg.tier;
        s.executeAfter = pkg.executeAfter;
        s.expiresAt = pkg.expiresAt;
        s.predecessor = pkg.predecessor;
        s.executed = pkg.executed;
        s.cancelled = pkg.cancelled;

        if (pkg.predecessor != bytes32(0)) {
            (s.predecessorExecuted, s.predecessorCancelled) = _predecessorState(pkg.predecessor);
        }

        s.blockedReason = _blockedReason(pkg, s.predecessorExecuted);
        s.executable = s.blockedReason == READY;
        if (s.blockedReason == NOT_READY) {
            s.secondsToReady = pkg.executeAfter - uint48(block.timestamp);
        }
    }

    /// @notice Treasury overview: balances, reserve floor, spendable headroom, pause state.
    function treasurySnapshot() external view returns (TreasurySnapshot memory s) {
        uint256 balance = address(treasury).balance;
        uint256 floor = treasury.nativeReserveFloor();
        s.ethBalance = balance;
        s.nativeFloor = floor;
        s.spendable = balance > floor ? balance - floor : 0;
        s.paused = treasury.paused();
        s.nextNonce = treasury.nextPackageNonce();
        s.allowlistEnabled = treasury.targetAllowlistEnabled();
    }

    /// @notice One-RPC portfolio over every registered asset: balance, floor, headroom.
    /// @dev Unbounded loop over a governance-curated list; view-only, so worst case is
    ///      an expensive RPC call, never a state-transition DoS.
    function treasuryPortfolio() external view returns (AssetPosition[] memory positions) {
        address[] memory assets = treasury.registeredAssets();
        positions = new AssetPosition[](assets.length);
        for (uint256 i = 0; i < assets.length; ++i) {
            uint256 balance = IERC20(assets[i]).balanceOf(address(treasury));
            uint256 floor = treasury.erc20ReserveFloors(IERC20(assets[i]));
            positions[i] = AssetPosition({
                token: assets[i], balance: balance, floor: floor, spendable: balance > floor ? balance - floor : 0
            });
        }
    }

    /// @notice Timelock queue delay backing governance execution.
    function timelockMinDelay() external view returns (uint256) {
        return TimelockController(payable(governor.timelock())).getMinDelay();
    }

    /// @notice Whether the deployment is sealed: `deployer` holds no timelock admin.
    /// @dev Frontends should banner `false` as unsealed (single-key capture risk)
    ///      and refuse "healthy" status until `Renounce.s.sol` has been run.
    function isSelfSovereign(address deployer) external view returns (bool) {
        TimelockController timelock = TimelockController(payable(governor.timelock()));
        return !timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);
    }

    /// @notice Preview of `approvePackage(target, value, data, tier, ...)`: the package id
    ///         that scheduling now would produce, the quarantine estimate, and whether the
    ///         tier cap and destination allowlist currently admit the call.
    /// @dev Reverts with the treasury's own `InvalidTier` for unknown tiers, mirroring
    ///      scheduling enforcement so tooling sees identical errors.
    function schedulePreview(address target, uint256 value, bytes calldata data, uint8 tier)
        external
        view
        returns (SchedulePreview memory p)
    {
        if (tier > treasury.MAX_TIER()) revert DAOTreasuryExecutionEngine.InvalidTier(tier);
        (uint48 delay, bool enabled, uint256 cap) = treasury.tierConfig(tier);
        p.previewId = treasury.packageHash(target, value, data, tier, treasury.nextPackageNonce());
        p.executeAfter = uint48(block.timestamp + delay);
        p.tierCap = cap;
        p.withinCap = enabled && value <= cap;
        p.targetAllowed = !treasury.targetAllowlistEnabled() || treasury.targetAllowlist(target);
    }

    /// @notice Timelock state for a proposal payload: operation id, pending/ready/done
    ///         flags, and scheduled ETA (0 while unscheduled).
    /// @dev Recomputes the exact operation id the governor queued
    ///      (`hashOperationBatch(targets, values, calldatas, 0, bytes20(governor) ^
    ///      descriptionHash)`), so keepers can poll readiness without indexing events.
    function timelockStatus(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas,
        bytes32 descriptionHash
    ) external view returns (TimelockStatus memory s) {
        TimelockController timelock = TimelockController(payable(governor.timelock()));
        s.operationId = timelock.hashOperationBatch(
            targets, values, calldatas, bytes32(0), bytes32(bytes20(address(governor))) ^ descriptionHash
        );
        s.pending = timelock.isOperationPending(s.operationId);
        s.ready = timelock.isOperationReady(s.operationId);
        s.done = timelock.isOperationDone(s.operationId);
        s.eta = timelock.getTimestamp(s.operationId);
    }

    function _predecessorState(bytes32 predecessor) internal view returns (bool executed, bool cancelled) {
        if (!treasury.packageExists(predecessor)) return (false, false);
        DAOTreasuryExecutionEngine.Package memory pred = treasury.getPackage(predecessor);
        return (pred.executed, pred.cancelled);
    }

    function _blockedReason(DAOTreasuryExecutionEngine.Package memory pkg, bool predecessorExecuted)
        internal
        view
        returns (uint8)
    {
        if (pkg.executed || pkg.cancelled) return FINALIZED;
        if (treasury.paused()) return PAUSED;
        if (block.timestamp < pkg.executeAfter) return NOT_READY;
        if (pkg.expiresAt != 0 && block.timestamp >= pkg.expiresAt) return EXPIRED;
        if (pkg.predecessor != bytes32(0) && !predecessorExecuted) return PREDECESSOR;
        if (pkg.value > 0) {
            uint256 balance = address(treasury).balance;
            uint256 floor = treasury.nativeReserveFloor();
            if (balance < pkg.value || balance - pkg.value < floor) return RESERVE;
        }
        return READY;
    }
}
