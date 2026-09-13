// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {DAOGovernanceToken} from "../contracts/DAOGovernanceToken.sol";
import {EnterpriseDAO} from "../contracts/EnterpriseDAO.sol";
import {DAOTreasuryExecutionEngine} from "../contracts/DAOTreasuryExecutionEngine.sol";
import {ProposalBuilder} from "../contracts/ProposalBuilder.sol";

contract BuilderPayee {
    uint256 public received;

    receive() external payable {
        received += msg.value;
    }
}

/// @dev P1-2 tests: builder output must equal hand-rolled calldata, and a built
///      payload must survive the real propose -> vote -> queue -> execute path.
contract ProposalBuilderTest is Test {
    DAOGovernanceToken internal token;
    TimelockController internal timelock;
    EnterpriseDAO internal governor;
    DAOTreasuryExecutionEngine internal treasury;
    BuilderPayee internal payee;

    address internal proposer = makeAddr("proposer");
    address internal voter1 = makeAddr("voter1");
    address internal guardian = makeAddr("guardian");

    uint256 internal constant SUPPLY = 1_000_000e18;

    function setUp() public {
        token = new DAOGovernanceToken("B Token", "BLD", address(this), SUPPLY);
        token.transfer(proposer, 400_000e18);
        token.transfer(voter1, 350_000e18);
        vm.prank(proposer);
        token.delegate(proposer);
        vm.prank(voter1);
        token.delegate(voter1);

        address[] memory noProposers = new address[](0);
        address[] memory openExecutors = new address[](1);
        openExecutors[0] = address(0);
        timelock = new TimelockController(1 days, noProposers, openExecutors, address(this));
        treasury = new DAOTreasuryExecutionEngine(address(timelock), guardian);
        governor = new EnterpriseDAO(
            EnterpriseDAO.GovernorConfig({
                name: "Builder DAO",
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
        payee = new BuilderPayee();
        vm.roll(block.number + 1);
    }

    function test_Builder_TreasuryPackageEncoding() public view {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) =
            ProposalBuilder.treasuryPackage(address(treasury), address(payee), 1 ether, "", 0, 0, bytes32(0));
        assertEq(targets[0], address(treasury));
        assertEq(values[0], 0);
        assertEq(
            calldatas[0],
            abi.encodeCall(DAOTreasuryExecutionEngine.approvePackage, (address(payee), 1 ether, "", 0, 0, bytes32(0)))
        );
    }

    function test_Builder_ConfigEncodings() public view {
        (,, bytes[] memory tierCall) = ProposalBuilder.configureTier(address(treasury), 0, 2 days, 100 ether, true);
        assertEq(tierCall[0], abi.encodeCall(DAOTreasuryExecutionEngine.configureTier, (0, 2 days, 100 ether, true)));

        (,, bytes[] memory allowCall) = ProposalBuilder.setTargetAllowed(address(treasury), address(payee), true);
        assertEq(allowCall[0], abi.encodeCall(DAOTreasuryExecutionEngine.setTargetAllowed, (address(payee), true)));

        (,, bytes[] memory floorCall) = ProposalBuilder.setNativeReserveFloor(address(treasury), 2 ether);
        assertEq(floorCall[0], abi.encodeCall(DAOTreasuryExecutionEngine.setNativeReserveFloor, (2 ether)));

        assertEq(ProposalBuilder.descriptionHash("pay 1 ETH"), keccak256(bytes("pay 1 ETH")));
    }

    function test_Builder_EndToEndPayment() public {
        deal(address(treasury), 5 ether);
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) =
            ProposalBuilder.treasuryPackage(address(treasury), address(payee), 1 ether, "", 0, 0, bytes32(0));
        string memory description = "builder: pay 1 ETH";
        bytes32 descriptionHash = ProposalBuilder.descriptionHash(description);

        vm.prank(proposer);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);
        vm.roll(block.number + 2);
        vm.prank(voter1);
        governor.castVote(proposalId, 1);
        vm.roll(block.number + 10);
        governor.queue(targets, values, calldatas, descriptionHash);
        vm.warp(block.timestamp + 1 days + 1);
        governor.execute(targets, values, calldatas, descriptionHash);

        bytes32 packageId = treasury.packageHash(address(payee), 1 ether, "", 0, treasury.nextPackageNonce() - 1);
        vm.warp(block.timestamp + 1 days + 1);
        treasury.executePackage(packageId);
        assertEq(payee.received(), 1 ether, "built payload must pay through the full governance path");
    }
}
