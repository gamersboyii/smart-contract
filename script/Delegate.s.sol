// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {DAOGovernanceToken} from "../contracts/DAOGovernanceToken.sol";

/// @title Delegate
/// @notice Activate voting power by delegating (self-delegation by default).
///
///         Required environment variables:
///         - TOKEN_ADDRESS   the deployed DAOGovernanceToken
///
///         Optional:
///         - DELEGATEE       address to delegate to (defaults to the broadcaster,
///                           i.e. self-delegation)
///
///         Run with the holder's key:
///         `forge script script/Delegate.s.sol --rpc-url <url> --broadcast`
///
///         The `token.delegate` call below MUST execute as the holder: under
///         `--broadcast` forge submits it from the broadcaster EOA, which is why
///         it lives inline in `run()` rather than in a helper contract call (an
///         intermediary contract would delegate its own zero votes instead).
///         Delegation must precede the proposal snapshot to count for that vote.
///         Safe to re-run: re-delegating to the same address is a no-op checkpoint.
contract Delegate is Script {
    function run() external {
        DAOGovernanceToken token = DAOGovernanceToken(vm.envAddress("TOKEN_ADDRESS"));
        address delegatee = resolveDelegatee(msg.sender);

        vm.startBroadcast();
        token.delegate(delegatee);
        vm.stopBroadcast();

        console2.log("delegated to:", delegatee);
        console2.log("voting power:", token.getVotes(delegatee));
    }

    /// @notice Resolve the DELEGATEE env override, defaulting to `fallbackAddr`.
    /// @dev Split out so tests can drive the only branching logic in this script.
    function resolveDelegatee(address fallbackAddr) public view returns (address) {
        return vm.envOr("DELEGATEE", fallbackAddr);
    }
}
