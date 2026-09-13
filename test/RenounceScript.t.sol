// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {DAOGovernanceToken} from "../contracts/DAOGovernanceToken.sol";
import {EnterpriseDAO} from "../contracts/EnterpriseDAO.sol";
import {DAOTreasuryExecutionEngine} from "../contracts/DAOTreasuryExecutionEngine.sol";
import {Renounce} from "../script/Renounce.s.sol";

/// @dev QW-4: the renounce gate must pass on correct wiring, refuse on broken wiring,
///      and leave the timelock self-sovereign afterwards.
contract RenounceScriptTest is Test {
    DAOGovernanceToken internal token;
    TimelockController internal timelock;
    EnterpriseDAO internal governor;
    DAOTreasuryExecutionEngine internal treasury;
    Renounce internal renounce;

    address internal multisig = makeAddr("multisig");
    address internal guardian = makeAddr("guardian");

    function setUp() public {
        token = new DAOGovernanceToken("T", "T", multisig, 100_000_000e18);
        address[] memory noProposers = new address[](0);
        address[] memory openExecutors = new address[](1);
        openExecutors[0] = address(0);
        timelock = new TimelockController(2 days, noProposers, openExecutors, address(this));
        treasury = new DAOTreasuryExecutionEngine(address(timelock), guardian);
        governor = new EnterpriseDAO(
            EnterpriseDAO.GovernorConfig({
                name: "Enterprise DAO",
                token: IVotes(address(token)),
                timelock: timelock,
                votingDelayBlocks: 7200,
                votingPeriodBlocks: 30240,
                proposalThreshold: 250_000e18,
                quorumMinBps: 400,
                quorumMaxBps: 1000,
                quorumLowSupplyThreshold: 100_000_000e18 / 4,
                quorumHighSupplyThreshold: (100_000_000e18 * 9) / 10,
                minProposalThreshold: 250_000e18 / 10,
                maxProposalThreshold: 250_000e18 * 4
            })
        );
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        renounce = new Renounce();
    }

    function test_VerifyWiring_PassesOnCorrectTopology() public view {
        renounce.verifyWiring(timelock, governor, treasury);
    }

    function test_VerifyWiring_RevertsWhen_ExecutorNotOpen() public {
        timelock.revokeRole(timelock.EXECUTOR_ROLE(), address(0));
        vm.expectRevert(abi.encodeWithSelector(Renounce.ExecutorRoleNotOpen.selector, address(timelock)));
        renounce.verifyWiring(timelock, governor, treasury);
    }

    function test_VerifyWiring_RevertsWhen_CallerNotAdmin() public {
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), address(this));
        vm.expectRevert(abi.encodeWithSelector(Renounce.AdminNotHeld.selector, address(timelock), address(this)));
        renounce.verifyWiring(timelock, governor, treasury);
    }

    function test_Renounce_LeavesTimelockSelfSovereign() public {
        renounce.verifyWiring(timelock, governor, treasury);
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), address(this));
        assertFalse(timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), address(this)));
        assertTrue(timelock.hasRole(timelock.PROPOSER_ROLE(), address(governor)));
        assertTrue(treasury.hasRole(treasury.GOVERNANCE_ROLE(), address(timelock)));
    }
}
