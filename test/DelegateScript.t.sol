// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DAOGovernanceToken} from "../contracts/DAOGovernanceToken.sol";
import {Delegate} from "../script/Delegate.s.sol";

/// @dev P1-5: the delegate script's env resolution plus the exact delegation
///      mechanism it broadcasts (holder calls `token.delegate` directly, which is
///      what `--broadcast` submits from the broadcaster EOA).
contract DelegateScriptTest is Test {
    DAOGovernanceToken internal token;
    Delegate internal delegateScript;

    address internal holder = makeAddr("holder");
    address internal delegatee = makeAddr("delegatee");

    function setUp() public {
        token = new DAOGovernanceToken("T", "T", holder, 1_000_000e18);
        delegateScript = new Delegate();
    }

    function test_ResolveDelegatee_ReturnsEnvOverride() public {
        // NOTE: the only test in the suite that touches the DELEGATEE env var —
        // forge runs tests in parallel threads and OS env is process-global, so two
        // writers would race. Every other test here is env-free by design.
        vm.setEnv("DELEGATEE", vm.toString(delegatee));
        assertEq(delegateScript.resolveDelegatee(holder), delegatee);
    }

    function test_Delegation_SelfDelegationActivatesPower() public {
        // Env-free: exercises the same call `--broadcast` submits from the holder EOA
        // (self-delegation is what the script resolves when DELEGATEE is unset).
        assertEq(token.getVotes(holder), 0, "no power before delegation");
        vm.prank(holder);
        token.delegate(holder);
        assertEq(token.getVotes(holder), 1_000_000e18, "self-delegation must activate power");
    }

    function test_Delegation_RedelegatesPower() public {
        assertEq(token.getVotes(holder), 0, "no power before delegation");
        vm.prank(holder);
        token.delegate(holder);
        vm.prank(holder);
        token.delegate(delegatee);
        assertEq(token.getVotes(holder), 0);
        assertEq(token.getVotes(delegatee), 1_000_000e18, "power must follow the delegation");
    }
}
