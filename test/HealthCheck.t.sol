// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {DAOGovernanceToken} from "../contracts/DAOGovernanceToken.sol";
import {EnterpriseDAO} from "../contracts/EnterpriseDAO.sol";
import {DAOTreasuryExecutionEngine} from "../contracts/DAOTreasuryExecutionEngine.sol";
import {HealthCheck} from "../script/HealthCheck.s.sol";

/// @dev Health-check gate tests: a correct sealed topology passes; every failure
///      mode (broken wiring, wrong guardian, rogue tier, unsealed deployer) reverts
///      with its named error. In particular an unsealed deployment FAILS loudly.
contract HealthCheckTest is Test {
    DAOGovernanceToken internal token;
    TimelockController internal timelock;
    EnterpriseDAO internal governor;
    DAOTreasuryExecutionEngine internal treasury;
    HealthCheck internal health;

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
        health = new HealthCheck();
    }

    function _sealed() internal {
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), address(this));
    }

    function test_Check_PassesOnSealedTopology() public {
        _sealed();
        health.check(timelock, governor, treasury, guardian, address(this));
    }

    function test_Check_RevertsWhen_DeployerStillAdmin() public {
        vm.expectRevert(
            abi.encodeWithSelector(HealthCheck.DeployerStillAdmin.selector, address(timelock), address(this))
        );
        health.check(timelock, governor, treasury, guardian, address(this));
    }

    function test_Check_RevertsWhen_ExecutorNotOpen() public {
        timelock.revokeRole(timelock.EXECUTOR_ROLE(), address(0));
        _sealed();
        vm.expectRevert(abi.encodeWithSelector(HealthCheck.ExecutorRoleNotOpen.selector, address(timelock)));
        health.check(timelock, governor, treasury, guardian, address(this));
    }

    function test_Check_RevertsWhen_WrongGuardian() public {
        _sealed();
        address impostor = makeAddr("impostor");
        vm.expectRevert(abi.encodeWithSelector(HealthCheck.GuardianMismatch.selector, address(treasury), impostor));
        health.check(timelock, governor, treasury, impostor, address(this));
    }
}
