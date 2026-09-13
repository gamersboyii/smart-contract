// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {EnterpriseDAO} from "../contracts/EnterpriseDAO.sol";
import {DAOTreasuryExecutionEngine} from "../contracts/DAOTreasuryExecutionEngine.sol";

/// @title Renounce
/// @notice Final self-sovereignty step: verify wiring, then renounce the deployer's
///         temporary `DEFAULT_ADMIN_ROLE` on the timelock.
///
///         Required environment variables:
///         - TIMELOCK_ADDRESS   the deployed TimelockController
///         - GOVERNOR_ADDRESS   the deployed EnterpriseDAO
///         - TREASURY_ADDRESS   the deployed DAOTreasuryExecutionEngine
///
///         Run with the deployer key (the current timelock admin):
///         `forge script script/Renounce.s.sol --rpc-url <url> --broadcast`
///
///         The script FAILS LOUDLY if any wiring assumption is broken, so a
///         misconfigured DAO can never be sealed by accident. Safe to re-run:
///         it reverts with `AdminNotHeld` once self-sovereignty is reached.
contract Renounce is Script {
    error AdminNotHeld(address timelock, address account);
    error GovernorMissingRole(address governor, bytes32 role);
    error ExecutorRoleNotOpen(address timelock);
    error TreasuryGovernanceMismatch(address treasury, address timelock);
    error GovernorTimelockMismatch(address governor, address timelock);
    error RenounceFailed(address timelock, address account);

    function run() external {
        TimelockController timelock = TimelockController(payable(vm.envAddress("TIMELOCK_ADDRESS")));
        EnterpriseDAO governor = EnterpriseDAO(payable(vm.envAddress("GOVERNOR_ADDRESS")));
        DAOTreasuryExecutionEngine treasury = DAOTreasuryExecutionEngine(payable(vm.envAddress("TREASURY_ADDRESS")));

        verifyWiring(timelock, governor, treasury);

        vm.startBroadcast();
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), msg.sender);
        vm.stopBroadcast();

        if (timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), msg.sender)) {
            revert RenounceFailed(address(timelock), msg.sender);
        }
        console2.log("Self-sovereign: deployer admin renounced on", address(timelock));
    }

    /// @notice Post-deployment invariant check. Reverts unless governance is fully wired
    ///         and the caller still holds the temporary admin role.
    function verifyWiring(TimelockController timelock, EnterpriseDAO governor, DAOTreasuryExecutionEngine treasury)
        public
        view
    {
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
        if (governor.timelock() != address(timelock)) {
            revert GovernorTimelockMismatch(address(governor), address(timelock));
        }
        if (!timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), msg.sender)) {
            revert AdminNotHeld(address(timelock), msg.sender);
        }
    }
}
