// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {EnterpriseDAO} from "../contracts/EnterpriseDAO.sol";
import {DAOTreasuryExecutionEngine} from "../contracts/DAOTreasuryExecutionEngine.sol";

/// @title HealthCheck
/// @notice One-command post-deploy verification: roles, tiers, floors, allowlist,
///         and sealed state. View-only — safe to run anytime, against any RPC.
///
///         Required environment variables:
///         - TIMELOCK_ADDRESS, GOVERNOR_ADDRESS, TREASURY_ADDRESS
///         - GUARDIAN_ADDRESS   expected guardian multisig
///         - DEPLOYER_ADDRESS   original deployer (must NO LONGER hold admin)
///
///         `forge script script/HealthCheck.s.sol --rpc-url <url>`
///
///         Any failure reverts with a named error. Notably `DeployerStillAdmin`
///         makes an unsealed deployment impossible to mistake for a healthy one:
///         run this after `Renounce.s.sol` and before funding (see DEPLOYMENT.md).
contract HealthCheck is Script {
    error GovernorMissingRole(address governor, bytes32 role);
    error ExecutorRoleNotOpen(address timelock);
    error TreasuryGovernanceMismatch(address treasury, address timelock);
    error GuardianMismatch(address treasury, address expected);
    error TierOutOfBounds(uint8 tier, uint48 delay);
    error DeployerStillAdmin(address timelock, address deployer);

    function run() external view {
        TimelockController timelock = TimelockController(payable(vm.envAddress("TIMELOCK_ADDRESS")));
        EnterpriseDAO governor = EnterpriseDAO(payable(vm.envAddress("GOVERNOR_ADDRESS")));
        DAOTreasuryExecutionEngine treasury = DAOTreasuryExecutionEngine(payable(vm.envAddress("TREASURY_ADDRESS")));
        address guardian = vm.envAddress("GUARDIAN_ADDRESS");
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");

        check(timelock, governor, treasury, guardian, deployer);

        console2.log("timelock min delay:", timelock.getMinDelay());
        console2.log("native reserve floor:", treasury.nativeReserveFloor());
        console2.log("allowlist enabled:", treasury.targetAllowlistEnabled());
        console2.log("next package nonce:", treasury.nextPackageNonce());
        console2.log("HEALTHY: all post-deployment checks passed");
    }

    /// @notice All checks. Split out so tests can drive every failure mode directly.
    function check(
        TimelockController timelock,
        EnterpriseDAO governor,
        DAOTreasuryExecutionEngine treasury,
        address guardian,
        address deployer
    ) public view {
        if (!timelock.hasRole(timelock.PROPOSER_ROLE(), address(governor))) {
            revert GovernorMissingRole(address(governor), timelock.PROPOSER_ROLE());
        }
        if (!timelock.hasRole(timelock.CANCELLER_ROLE(), address(governor))) {
            revert GovernorMissingRole(address(governor), timelock.CANCELLER_ROLE());
        }
        if (!timelock.hasRole(timelock.EXECUTOR_ROLE(), address(0))) {
            revert ExecutorRoleNotOpen(address(timelock));
        }
        if (!treasury.hasRole(treasury.GOVERNANCE_ROLE(), address(timelock))) {
            revert TreasuryGovernanceMismatch(address(treasury), address(timelock));
        }
        if (!treasury.hasRole(treasury.GUARDIAN_ROLE(), guardian)) {
            revert GuardianMismatch(address(treasury), guardian);
        }
        for (uint8 tier = 0; tier <= treasury.MAX_TIER(); ++tier) {
            (uint48 delay,,) = treasury.tierConfig(tier);
            if (delay > treasury.MAX_TIER_DELAY()) revert TierOutOfBounds(tier, delay);
        }
        if (timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), deployer)) {
            revert DeployerStillAdmin(address(timelock), deployer);
        }
    }
}
