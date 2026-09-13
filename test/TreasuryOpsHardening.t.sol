// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DAOTreasuryExecutionEngine} from "../contracts/DAOTreasuryExecutionEngine.sol";

contract OpsTarget {
    function poke() external {}
}

/// @dev QW-1 + QW-3 regression tests: expiry-horizon bound (M1), cancelled-predecessor
///      guard (L1), distinct not-expired error, and permissionless stuck-package cleanup.
contract TreasuryOpsHardeningTest is Test {
    DAOTreasuryExecutionEngine internal treasury;
    OpsTarget internal target;

    address internal guardian = makeAddr("guardian");
    address internal rando = makeAddr("rando");

    function setUp() public {
        treasury = new DAOTreasuryExecutionEngine(address(this), guardian);
        target = new OpsTarget();
    }

    function test_ExpiryHorizon_RevertsWhen_BeyondMaxExpiry() public {
        uint48 tooFar = uint48(block.timestamp + uint256(treasury.MAX_PACKAGE_EXPIRY()) + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                DAOTreasuryExecutionEngine.ExpiryHorizonTooLong.selector,
                tooFar,
                uint48(block.timestamp + uint256(treasury.MAX_PACKAGE_EXPIRY()))
            )
        );
        treasury.approvePackage(address(target), 0, "", 0, tooFar, bytes32(0));
    }

    function test_ExpiryHorizon_AcceptsBoundary() public {
        uint48 atMax = uint48(block.timestamp + uint256(treasury.MAX_PACKAGE_EXPIRY()));
        // TIER_LOW delay is 1 day, so now+365d is safely after executeAfter.
        bytes32 id = treasury.approvePackage(address(target), 0, "", 0, atMax, bytes32(0));
        assertTrue(treasury.packageExists(id));
    }

    function test_PredecessorCancelled_RevertsWhen_SchedulingOnCancelled() public {
        bytes32 pred = treasury.approvePackage(address(target), 0, "", 0, 0, bytes32(0));
        treasury.cancelPackage(pred);
        vm.expectRevert(abi.encodeWithSelector(DAOTreasuryExecutionEngine.PredecessorCancelled.selector, pred));
        treasury.approvePackage(address(target), 0, "", 0, 0, pred);
    }

    function test_CloseStuckPackage_ClosesSuccessorOfCancelledPredecessor() public {
        bytes32 pred = treasury.approvePackage(address(target), 0, "", 0, 0, bytes32(0));
        bytes32 succ = treasury.approvePackage(address(target), 0, "", 0, 0, pred);
        treasury.cancelPackage(pred);

        // Successor can never execute now.
        vm.warp(block.timestamp + 2 days);
        vm.expectRevert(abi.encodeWithSelector(DAOTreasuryExecutionEngine.PredecessorNotExecuted.selector, succ, pred));
        treasury.executePackage(succ);

        // Anyone (not just governance) can finalize it as cancelled.
        vm.expectEmit(true, true, false, true, address(treasury));
        emit DAOTreasuryExecutionEngine.PackageCancelled(succ, rando);
        vm.prank(rando);
        treasury.closeStuckPackage(succ);
        assertTrue(treasury.getPackage(succ).cancelled);
    }

    function test_CloseStuckPackage_RevertsWhen_PredecessorNotCancelled() public {
        bytes32 pred = treasury.approvePackage(address(target), 0, "", 0, 0, bytes32(0));
        bytes32 succ = treasury.approvePackage(address(target), 0, "", 0, 0, pred);
        vm.expectRevert(abi.encodeWithSelector(DAOTreasuryExecutionEngine.PredecessorNotExecuted.selector, succ, pred));
        treasury.closeStuckPackage(succ);
    }

    function test_CloseStuckPackage_RevertsWhen_NoPredecessor() public {
        bytes32 id = treasury.approvePackage(address(target), 0, "", 0, 0, bytes32(0));
        vm.expectRevert(
            abi.encodeWithSelector(DAOTreasuryExecutionEngine.PredecessorNotExecuted.selector, id, bytes32(0))
        );
        treasury.closeStuckPackage(id);
    }

    function test_CloseExpiredPackage_RevertsWhen_NotExpired() public {
        uint48 expiresAt = uint48(block.timestamp + 10 days);
        bytes32 id = treasury.approvePackage(address(target), 0, "", 0, expiresAt, bytes32(0));
        vm.expectRevert(abi.encodeWithSelector(DAOTreasuryExecutionEngine.PackageNotExpired.selector, id, expiresAt));
        treasury.closeExpiredPackage(id);
    }

    function test_CloseExpiredPackage_Emits_PackageExpired() public {
        uint48 expiresAt = uint48(block.timestamp + 10 days);
        bytes32 id = treasury.approvePackage(address(target), 0, "", 0, expiresAt, bytes32(0));
        vm.warp(uint256(expiresAt) + 1);
        vm.expectEmit(true, false, false, true, address(treasury));
        emit DAOTreasuryExecutionEngine.PackageExpired(id);
        treasury.closeExpiredPackage(id);
        assertTrue(treasury.getPackage(id).cancelled);
    }

    function testFuzz_ExpiryHorizon_Bound(uint48 offset) public {
        offset = uint48(bound(offset, 1, 400 days));
        uint48 expiresAt = uint48(block.timestamp + offset);
        if (uint256(expiresAt) > block.timestamp + uint256(treasury.MAX_PACKAGE_EXPIRY())) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    DAOTreasuryExecutionEngine.ExpiryHorizonTooLong.selector,
                    expiresAt,
                    uint48(block.timestamp + uint256(treasury.MAX_PACKAGE_EXPIRY()))
                )
            );
            treasury.approvePackage(address(target), 0, "", 0, expiresAt, bytes32(0));
        } else if (expiresAt > uint48(block.timestamp + 1 days)) {
            // Past the TIER_LOW executeAfter: schedules fine.
            bytes32 id = treasury.approvePackage(address(target), 0, "", 0, expiresAt, bytes32(0));
            assertTrue(treasury.packageExists(id));
        }
    }
}
