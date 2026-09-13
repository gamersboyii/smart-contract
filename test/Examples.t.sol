// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {DAOGovernanceToken} from "../contracts/DAOGovernanceToken.sol";
import {EnterpriseDAO} from "../contracts/EnterpriseDAO.sol";
import {DAOTreasuryExecutionEngine} from "../contracts/DAOTreasuryExecutionEngine.sol";
import {DAOReadHub} from "../contracts/DAOReadHub.sol";

contract ExamplePayee {
    uint256 public received;

    receive() external payable {
        received += msg.value;
    }
}

/// @dev QW-6 end-to-end adoption examples. Each flow uses only real repository APIs and
///      warps past the timelock + tier delays that a live operator would wait out
///      (see docs/CAST.md for the equivalent live-chain commands).
///      Flow A: fund -> propose -> vote -> queue -> timelock-execute -> package-execute.
///      Flow B: governance configuration change through the same path.
///      Flow C: token distribution -> delegation -> voting-power verification.
contract ExamplesTest is Test {
    DAOGovernanceToken internal token;
    TimelockController internal timelock;
    EnterpriseDAO internal governor;
    DAOTreasuryExecutionEngine internal treasury;
    DAOReadHub internal hub;

    address internal proposer = makeAddr("proposer");
    address internal voter1 = makeAddr("voter1");
    address internal voter2 = makeAddr("voter2");
    address internal guardian = makeAddr("guardian");

    uint256 internal constant SUPPLY = 1_000_000e18;

    function setUp() public {
        token = new DAOGovernanceToken("Example Token", "EX", address(this), SUPPLY);
        token.transfer(proposer, 400_000e18);
        token.transfer(voter1, 350_000e18);
        token.transfer(voter2, 250_000e18);
        vm.prank(proposer);
        token.delegate(proposer);
        vm.prank(voter1);
        token.delegate(voter1);
        vm.prank(voter2);
        token.delegate(voter2);

        address[] memory noProposers = new address[](0);
        address[] memory openExecutors = new address[](1);
        openExecutors[0] = address(0);
        timelock = new TimelockController(2 days, noProposers, openExecutors, address(this));
        treasury = new DAOTreasuryExecutionEngine(address(timelock), guardian);
        governor = new EnterpriseDAO(
            EnterpriseDAO.GovernorConfig({
                name: "Example DAO",
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
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        hub = new DAOReadHub(governor, treasury);
        vm.roll(block.number + 1);
    }

    function _passProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) internal returns (uint256 proposalId) {
        bytes32 descriptionHash = keccak256(bytes(description));
        vm.prank(proposer);
        proposalId = governor.propose(targets, values, calldatas, description);
        vm.roll(block.number + 2);
        vm.prank(voter1);
        governor.castVote(proposalId, 1);
        vm.roll(block.number + 10);
        governor.queue(targets, values, calldatas, descriptionHash);
        vm.warp(block.timestamp + 2 days + 1);
        governor.execute(targets, values, calldatas, descriptionHash);
    }

    /// @dev Flow A — treasury payment: fund, govern a package, execute it, payee paid.
    function test_ExampleA_TreasuryPayment() public {
        ExamplePayee payee = new ExamplePayee();
        deal(address(treasury), 10 ether);
        console2.log("treasury funded:", address(treasury).balance);

        bytes memory schedule =
            abi.encodeCall(DAOTreasuryExecutionEngine.approvePackage, (address(payee), 1 ether, "", 0, 0, bytes32(0)));
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        (targets[0], values[0], calldatas[0]) = (address(treasury), 0, schedule);

        _passProposal(targets, values, calldatas, "example A: pay 1 ETH");
        bytes32 packageId = treasury.packageHash(address(payee), 1 ether, "", 0, treasury.nextPackageNonce() - 1);
        assertEq(uint256(hub.packageStatus(packageId).blockedReason), hub.NOT_READY());

        vm.warp(block.timestamp + 1 days + 1);
        assertTrue(hub.packageStatus(packageId).executable, "package card must show ready");
        treasury.executePackage(packageId);
        assertEq(payee.received(), 1 ether, "payee must receive the governed payment");
        console2.log("payee received:", payee.received());
    }

    /// @dev Flow B — governance configuration: raise the native reserve floor by proposal.
    function test_ExampleB_ReserveFloorChange() public {
        bytes memory schedule = abi.encodeCall(DAOTreasuryExecutionEngine.setNativeReserveFloor, (2 ether));
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        (targets[0], values[0], calldatas[0]) = (address(treasury), 0, schedule);

        _passProposal(targets, values, calldatas, "example B: 2 ETH reserve floor");
        assertEq(treasury.nativeReserveFloor(), 2 ether);
        assertEq(hub.treasurySnapshot().nativeFloor, 2 ether, "read hub must reflect the new floor");
        console2.log("reserve floor:", treasury.nativeReserveFloor());
    }

    /// @dev Flow C — token distribution: allocate, delegate, verify snapshot voting power.
    function test_ExampleC_TokenDistribution() public {
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");
        DAOGovernanceToken dist = new DAOGovernanceToken("Dist Token", "DIST", address(this), SUPPLY);
        dist.transfer(alice, 300_000e18);
        dist.transfer(bob, 200_000e18);
        vm.prank(alice);
        dist.delegate(alice);
        vm.prank(bob);
        dist.delegate(bob);
        vm.roll(block.number + 1);

        assertEq(dist.getVotes(alice), 300_000e18, "delegation must create voting power");
        assertEq(dist.getVotes(bob), 200_000e18);
        assertEq(dist.balanceOf(address(this)), 500_000e18, "remainder stays with distributor");
        console2.log("alice votes:", dist.getVotes(alice));
    }
}
