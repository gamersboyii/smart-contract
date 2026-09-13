// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {DAOTreasuryExecutionEngine} from "../contracts/DAOTreasuryExecutionEngine.sol";
import {EnterpriseDAO} from "../contracts/EnterpriseDAO.sol";
import {DAOGovernanceToken} from "../contracts/DAOGovernanceToken.sol";

/// @dev Formal checks in Halmos convention (`check_` prefix): ignored by forge
///      (only `test*` runs), executed symbolically by halmos when available:
///      `halmos --contract FormalChecks`. Each check states exactly one property
///      over symbolic inputs; `vm.assume` bounds the domain. This file must keep
///      compiling under `forge build` — that is its CI gate until halmos is wired.
contract FormalChecks is Test {
    DAOTreasuryExecutionEngine internal treasury;
    EnterpriseDAO internal governor;
    DAOGovernanceToken internal token;

    function setUp() public {
        token = new DAOGovernanceToken("F", "F", address(this), 1_000_000e18);
        address[] memory noProposers = new address[](0);
        address[] memory openExecutors = new address[](1);
        openExecutors[0] = address(0);
        TimelockController timelock = new TimelockController(1 days, noProposers, openExecutors, address(this));
        treasury = new DAOTreasuryExecutionEngine(address(timelock), makeAddr("guardian"));
        governor = new EnterpriseDAO(
            EnterpriseDAO.GovernorConfig({
                name: "F",
                token: IVotes(address(token)),
                timelock: timelock,
                votingDelayBlocks: 1,
                votingPeriodBlocks: 5,
                proposalThreshold: 100e18,
                quorumMinBps: 400,
                quorumMaxBps: 1000,
                quorumLowSupplyThreshold: 500_000e18,
                quorumHighSupplyThreshold: 2_000_000e18,
                minProposalThreshold: 1e18,
                maxProposalThreshold: 1_000_000e18
            })
        );
    }

    /// @dev Approval either succeeds with the committed id or reverts on exactly one
    ///      documented gate (tier / cap / allowlist is open / expiry window).
    function check_ApprovePackage_IdCommitment(address target, uint96 valueSeed, uint8 tier) public {
        vm.assume(target != address(0));
        tier = uint8(bound(tier, 0, 3));
        (,, uint256 cap) = treasury.tierConfig(tier); // order: (delay, enabled, cap)
        uint256 value = bound(valueSeed, 0, cap);
        uint256 nonceBefore = treasury.nextPackageNonce();
        bytes memory data = hex"1234";
        try treasury.approvePackage(target, value, data, tier, 0, bytes32(0)) returns (bytes32 id) {
            assert(id == treasury.packageHash(target, value, data, tier, nonceBefore));
        } catch {
            assertTrue(value > cap);
        }
    }

    /// @dev Quorum fraction is clamped and hits both endpoints exactly, for any supply.
    function check_QuorumFraction_Clamped(uint256 supply) public view {
        uint256 f = governor.quorumFractionAtSupply(supply);
        assert(f >= governor.dynamicQuorumMinBps() && f <= governor.dynamicQuorumMaxBps());
        if (supply <= governor.quorumLowSupplyThreshold()) assert(f == governor.dynamicQuorumMinBps());
        if (supply >= governor.quorumHighSupplyThreshold()) assert(f == governor.dynamicQuorumMaxBps());
    }

    /// @dev An expired package can never execute: warp past expiry, execution reverts,
    ///      and the package stays finalizable by anyone.
    function check_ExpiredPackage_NeverExecutes(uint8 tier) public {
        tier = uint8(bound(tier, 0, 3));
        treasury.configureTier(tier, 1 days, type(uint256).max, true);
        uint48 expiresAt = uint48(block.timestamp + 10 days);
        bytes32 id = treasury.approvePackage(makeAddr("t"), 0, "", tier, expiresAt, bytes32(0));
        vm.warp(uint256(expiresAt) + 1);
        try treasury.executePackage(id) {
            assert(false);
        } catch {
            assert(!treasury.getPackage(id).executed);
        }
        treasury.closeExpiredPackage(id);
        assert(treasury.getPackage(id).cancelled);
    }
}
