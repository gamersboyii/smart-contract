// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {DAOTreasuryExecutionEngine} from "../contracts/DAOTreasuryExecutionEngine.sol";
import {DAOReadHub} from "../contracts/DAOReadHub.sol";
import {EnterpriseDAO} from "../contracts/EnterpriseDAO.sol";

contract RegistryMint is ERC20 {
    constructor() ERC20("Registry", "REG") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @dev P1-4 tests: governance-curated registry (ACL, events, enumeration),
///      spendable math, and hub portfolio parity. Registration is informational:
///      unregistered tokens still deposit and move exactly the same.
contract TreasuryAssetRegistryTest is Test {
    DAOTreasuryExecutionEngine internal treasury;
    RegistryMint internal tokenA;
    RegistryMint internal tokenB;

    address internal guardian = makeAddr("guardian");
    address internal rando = makeAddr("rando");

    function setUp() public {
        treasury = new DAOTreasuryExecutionEngine(address(this), guardian);
        tokenA = new RegistryMint();
        tokenB = new RegistryMint();
    }

    function test_RegisterAsset_EmitsAndEnumerates() public {
        vm.expectEmit(true, false, false, true, address(treasury));
        emit DAOTreasuryExecutionEngine.AssetRegistered(address(tokenA));
        treasury.registerAsset(address(tokenA));
        assertTrue(treasury.isAssetRegistered(address(tokenA)));

        treasury.registerAsset(address(tokenB));
        address[] memory assets = treasury.registeredAssets();
        assertEq(assets.length, 2);

        vm.expectRevert(
            abi.encodeWithSelector(DAOTreasuryExecutionEngine.AssetAlreadyRegistered.selector, address(tokenA))
        );
        treasury.registerAsset(address(tokenA));

        vm.expectRevert(abi.encodeWithSelector(DAOTreasuryExecutionEngine.InvalidTarget.selector));
        treasury.registerAsset(address(0));
    }

    function test_Registry_GovernanceOnly() public {
        bytes32 role = treasury.GOVERNANCE_ROLE();
        vm.prank(rando);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, rando, role));
        treasury.registerAsset(address(tokenA));
        vm.prank(rando);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, rando, role));
        treasury.deregisterAsset(address(tokenA));
    }

    function test_DeregisterAsset_RemovesAndEmits() public {
        treasury.registerAsset(address(tokenA));
        treasury.registerAsset(address(tokenB));
        vm.expectEmit(true, false, false, true, address(treasury));
        emit DAOTreasuryExecutionEngine.AssetDeregistered(address(tokenA));
        treasury.deregisterAsset(address(tokenA));
        assertFalse(treasury.isAssetRegistered(address(tokenA)));
        address[] memory assets = treasury.registeredAssets();
        assertEq(assets.length, 1);
        assertEq(assets[0], address(tokenB));

        vm.expectRevert(abi.encodeWithSelector(DAOTreasuryExecutionEngine.AssetNotRegistered.selector, address(tokenA)));
        treasury.deregisterAsset(address(tokenA));
    }

    function test_SpendableERC20_HeadroomMath() public {
        tokenA.mint(address(treasury), 1_000e18);
        treasury.setERC20ReserveFloor(IERC20(address(tokenA)), 400e18);
        assertEq(treasury.spendableERC20(IERC20(address(tokenA))), 600e18);

        treasury.setERC20ReserveFloor(IERC20(address(tokenA)), 2_000e18);
        assertEq(treasury.spendableERC20(IERC20(address(tokenA))), 0, "floor above balance clamps to zero");

        assertEq(treasury.spendableERC20(IERC20(address(tokenB))), 0, "zero balance, zero floor");
    }

    function test_UnregisteredToken_StillDeposits() public {
        tokenB.mint(address(this), 100e18);
        tokenB.approve(address(treasury), 100e18);
        treasury.depositERC20(IERC20(address(tokenB)), 100e18);
        assertEq(tokenB.balanceOf(address(treasury)), 100e18, "registry gates nothing on custody");
    }

    function test_Portfolio_MatchesRegistry() public {
        tokenA.mint(address(treasury), 1_000e18);
        tokenB.mint(address(treasury), 50e18);
        treasury.registerAsset(address(tokenA));
        treasury.registerAsset(address(tokenB));
        treasury.setERC20ReserveFloor(IERC20(address(tokenA)), 400e18);

        DAOReadHub hub = new DAOReadHub(EnterpriseDAO(payable(address(0))), treasury);
        DAOReadHub.AssetPosition[] memory positions = hub.treasuryPortfolio();
        assertEq(positions.length, 2);
        assertEq(positions[0].token, address(tokenA));
        assertEq(positions[0].balance, 1_000e18);
        assertEq(positions[0].floor, 400e18);
        assertEq(positions[0].spendable, 600e18);
        assertEq(positions[1].spendable, 50e18);
    }

    function testFuzz_Spendable_ClampedAtZero(uint256 balance, uint256 floor) public {
        balance = bound(balance, 0, 1_000_000e18);
        floor = bound(floor, 0, 1_000_000e18);
        tokenA.mint(address(treasury), balance);
        treasury.setERC20ReserveFloor(IERC20(address(tokenA)), floor);
        uint256 expected = balance > floor ? balance - floor : 0;
        assertEq(treasury.spendableERC20(IERC20(address(tokenA))), expected);
    }
}
