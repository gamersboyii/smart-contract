// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DAOTreasuryExecutionEngine} from "../contracts/DAOTreasuryExecutionEngine.sol";

/// @dev Golden storage-layout test: `executeAfter/expiresAt/tier/executed/cancelled`
///      must share one package slot (6+6+1+1+1 = 15 bytes) and `delay/enabled` one
///      tier slot. Any field reorder breaks this test LOUDLY — that is its purpose
///      (see the WARNING on the Package struct). Mapping base slots below mirror
///      `forge inspect DAOTreasuryExecutionEngine storage-layout`
///      (_roles=0, _paused=1, _status=2, tierConfig=3, _packages=4).
contract TreasuryStorageLayoutTest is Test {
    DAOTreasuryExecutionEngine internal treasury;

    uint256 internal constant PACKAGES_SLOT = 4;
    uint256 internal constant TIER_CONFIG_SLOT = 3;

    function setUp() public {
        treasury = new DAOTreasuryExecutionEngine(address(this), makeAddr("guardian"));
    }

    function test_PackageTimingFlagsShareOneSlot() public {
        bytes32 id = treasury.approvePackage(address(0xBEEF), 0, hex"1234", 1, 0, bytes32(0));
        DAOTreasuryExecutionEngine.Package memory pkg = treasury.getPackage(id);

        bytes32 base = keccak256(abi.encode(id, PACKAGES_SLOT));
        uint256 word = uint256(vm.load(address(treasury), bytes32(uint256(base) + 3)));

        assertEq(uint48(word), pkg.executeAfter, "executeAfter: bytes 0-5");
        assertEq(uint48(word >> 48), pkg.expiresAt, "expiresAt: bytes 6-11");
        assertEq(uint8(word >> 96), pkg.tier, "tier: byte 12");
        assertEq((word >> 104) & 1, pkg.executed ? 1 : 0, "executed: byte 13");
        assertEq((word >> 112) & 1, pkg.cancelled ? 1 : 0, "cancelled: byte 14");
        assertEq(word >> 120, 0, "upper 17 bytes must stay zero (15-byte packing)");
    }

    function test_TierDelayAndEnabledShareOneSlot() public {
        bytes32 base = keccak256(abi.encode(uint256(0), TIER_CONFIG_SLOT));
        uint256 word0 = uint256(vm.load(address(treasury), base));
        uint256 word1 = uint256(vm.load(address(treasury), bytes32(uint256(base) + 1)));

        (uint48 delay, bool enabled, uint256 cap) = treasury.tierConfig(0);
        assertEq(uint48(word0), delay, "delay: bytes 0-5");
        assertEq((word0 >> 48) & 1, enabled ? 1 : 0, "enabled: byte 6");
        assertEq(word0 >> 56, 0, "delay slot upper bytes must stay zero");
        assertEq(word1, cap, "cap: full second slot");
    }
}
