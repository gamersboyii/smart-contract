// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {DAOGovernanceToken} from "../contracts/DAOGovernanceToken.sol";
import {EnterpriseDAO} from "../contracts/EnterpriseDAO.sol";
import {DAOTreasuryExecutionEngine} from "../contracts/DAOTreasuryExecutionEngine.sol";
import {DAOReadHub} from "../contracts/DAOReadHub.sol";

contract HubTarget {
    uint256 public flag;

    function setFlag(uint256 v) external {
        flag = v;
    }
}

/// @dev QW-2 parity tests: every ReadHub view must match the underlying contract state
///      across the full package lifecycle (pending/ready/executed/expired/predecessor/
///      paused/reserve) and the proposal lifecycle.
contract DAOReadHubTest is Test {
    DAOGovernanceToken internal token;
    TimelockController internal timelock;
    EnterpriseDAO internal governor;
    DAOTreasuryExecutionEngine internal treasury;
    DAOReadHub internal hub;
    HubTarget internal target;

    address internal proposer = makeAddr("proposer");
    address internal voter1 = makeAddr("voter1");
    address internal voter2 = makeAddr("voter2");
    address internal guardian = makeAddr("guardian");

    uint256 internal constant SUPPLY = 1_000_000e18;

    address[] internal pTargets;
    uint256[] internal pValues;
    bytes[] internal pCalldatas;
    bytes32 internal pDescriptionHash;

    function setUp() public {
        token = new DAOGovernanceToken("Hub Token", "HUB", address(this), SUPPLY);
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
        timelock = new TimelockController(1 days, noProposers, openExecutors, address(this));

        treasury = new DAOTreasuryExecutionEngine(address(timelock), guardian);
        governor = new EnterpriseDAO(
            EnterpriseDAO.GovernorConfig({
                name: "Hub DAO",
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
        target = new HubTarget();
        vm.roll(block.number + 1);
    }

    function _propose() internal returns (uint256 proposalId) {
        pTargets = new address[](1);
        pValues = new uint256[](1);
        pCalldatas = new bytes[](1);
        pTargets[0] = address(target);
        pValues[0] = 0;
        pCalldatas[0] = abi.encodeCall(HubTarget.setFlag, (7));
        pDescriptionHash = keccak256(bytes("hub proposal"));
        vm.prank(proposer);
        return governor.propose(pTargets, pValues, pCalldatas, "hub proposal");
    }

    function test_ProposalCard_MatchesGovernorState() public {
        uint256 id = _propose();
        DAOReadHub.ProposalCard memory card = hub.proposalCard(id, voter1);
        assertEq(card.snapshot, governor.proposalSnapshot(id));
        assertEq(card.deadline, governor.proposalDeadline(id));
        assertEq(uint256(card.state), uint256(governor.state(id)));
        assertEq(card.quorumRequired, 0, "pending snapshot is in the future: no quorum yet");

        vm.roll(block.number + 2);
        vm.prank(voter1);
        governor.castVote(id, 1);
        card = hub.proposalCard(id, voter1);
        assertEq(card.forVotes, 350_000e18);
        assertTrue(card.hasVoted);
        assertEq(card.accountWeight, 350_000e18, "snapshot weight must match delegation");
        assertGt(card.quorumRequired, 0, "active proposal must report quorum");
        assertEq(card.quorumRequired, governor.quorum(card.snapshot));
    }

    function test_PackageStatus_TransitionsNotReadyToReadyToFinalized() public {
        vm.prank(address(timelock));
        bytes32 id =
            treasury.approvePackage(address(target), 0, abi.encodeCall(HubTarget.setFlag, (1)), 0, 0, bytes32(0));

        DAOReadHub.PackageStatus memory before = hub.packageStatus(id);
        assertEq(before.blockedReason, hub.NOT_READY());
        assertFalse(before.executable);
        assertGt(before.secondsToReady, 0);

        vm.warp(block.timestamp + 1 days + 1);
        DAOReadHub.PackageStatus memory ready = hub.packageStatus(id);
        assertEq(ready.blockedReason, hub.READY());
        assertTrue(ready.executable);
        assertEq(ready.secondsToReady, 0);

        treasury.executePackage(id);
        DAOReadHub.PackageStatus memory done = hub.packageStatus(id);
        assertEq(done.blockedReason, hub.FINALIZED());
        assertFalse(done.executable);
        assertTrue(done.executed);
    }

    function test_PackageStatus_ReportsExpired() public {
        uint48 expiresAt = uint48(block.timestamp + 10 days);
        vm.prank(address(timelock));
        bytes32 id = treasury.approvePackage(address(target), 0, "", 0, expiresAt, bytes32(0));
        vm.warp(uint256(expiresAt) + 1);
        DAOReadHub.PackageStatus memory s = hub.packageStatus(id);
        assertEq(s.blockedReason, hub.EXPIRED());
        assertFalse(s.executable);
    }

    function test_PackageStatus_ReportsPredecessor() public {
        vm.prank(address(timelock));
        bytes32 first = treasury.approvePackage(address(target), 0, "", 0, 0, bytes32(0));
        vm.prank(address(timelock));
        bytes32 second = treasury.approvePackage(address(target), 0, "", 0, 0, first);
        vm.warp(block.timestamp + 2 days);
        DAOReadHub.PackageStatus memory s = hub.packageStatus(second);
        assertEq(s.blockedReason, hub.PREDECESSOR());
        assertFalse(s.executable);
        assertFalse(s.predecessorExecuted);
    }

    function test_PackageStatus_ReportsPausedAndReserve() public {
        deal(address(treasury), 5 ether);
        vm.prank(address(timelock));
        bytes32 id = treasury.approvePackage(address(target), 1 ether, "", 0, 0, bytes32(0));
        vm.warp(block.timestamp + 2 days);

        vm.prank(guardian);
        treasury.pause();
        assertEq(hub.packageStatus(id).blockedReason, hub.PAUSED());

        vm.prank(address(timelock));
        treasury.unpause();

        vm.prank(address(timelock));
        treasury.setNativeReserveFloor(5 ether);
        DAOReadHub.PackageStatus memory s = hub.packageStatus(id);
        assertEq(s.blockedReason, hub.RESERVE(), "spending below the floor must be flagged");
        assertFalse(s.executable);
    }

    function test_TreasurySnapshot_SpendableMath() public {
        deal(address(treasury), 5 ether);
        vm.prank(address(timelock));
        treasury.setNativeReserveFloor(2 ether);
        DAOReadHub.TreasurySnapshot memory s = hub.treasurySnapshot();
        assertEq(s.ethBalance, 5 ether);
        assertEq(s.nativeFloor, 2 ether);
        assertEq(s.spendable, 3 ether);
        assertFalse(s.paused);
        assertEq(s.nextNonce, treasury.nextPackageNonce());
    }

    function test_TimelockMinDelay_MatchesTimelock() public {
        assertEq(hub.timelockMinDelay(), timelock.getMinDelay());
    }

    function test_IsSelfSovereign_TracksRenounce() public {
        // Test contract deployed the timelock, so it starts as temporary admin.
        assertFalse(hub.isSelfSovereign(address(this)), "unsealed deployment must banner false");
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), address(this));
        assertTrue(hub.isSelfSovereign(address(this)), "sealed deployment must report true");
    }

    function testFuzz_PackageStatus_MirrorsGetPackage(uint8 tier, uint256 flag) public {
        tier = uint8(bound(tier, 0, 3));
        (,, uint256 cap) = treasury.tierConfig(tier);
        vm.assume(cap > 0);
        vm.prank(address(timelock));
        bytes32 id =
            treasury.approvePackage(address(target), 0, abi.encodeCall(HubTarget.setFlag, (flag)), tier, 0, bytes32(0));
        DAOTreasuryExecutionEngine.Package memory pkg = treasury.getPackage(id);
        DAOReadHub.PackageStatus memory s = hub.packageStatus(id);
        assertEq(s.target, pkg.target);
        assertEq(s.tier, pkg.tier);
        assertEq(s.executeAfter, pkg.executeAfter);
        assertEq(s.predecessor, pkg.predecessor);
    }

    function test_SchedulePreview_MatchesApproval() public {
        bytes memory data = abi.encodeCall(HubTarget.setFlag, (9));
        DAOReadHub.SchedulePreview memory preview = hub.schedulePreview(address(target), 0, data, 0);
        assertTrue(preview.withinCap);
        assertTrue(preview.targetAllowed);

        vm.prank(address(timelock));
        bytes32 id = treasury.approvePackage(address(target), 0, data, 0, 0, bytes32(0));
        assertEq(preview.previewId, id, "preview must commit to the approval id");
        assertEq(preview.executeAfter, treasury.getPackage(id).executeAfter);
    }

    function test_SchedulePreview_FlagsCapBreachAndBadTier() public {
        DAOReadHub.SchedulePreview memory over = hub.schedulePreview(address(target), 251 ether, "", 0);
        assertFalse(over.withinCap, "above the 250 ETH low-tier cap");
        assertEq(over.tierCap, 250 ether);

        vm.expectRevert(abi.encodeWithSelector(DAOTreasuryExecutionEngine.InvalidTier.selector, 4));
        hub.schedulePreview(address(target), 0, "", 4);
    }

    function test_TimelockStatus_PendingReadyDone() public {
        uint256 proposalId = _propose();
        DAOReadHub.TimelockStatus memory unscheduled =
            hub.timelockStatus(pTargets, pValues, pCalldatas, pDescriptionHash);
        assertFalse(unscheduled.pending);
        assertFalse(unscheduled.ready);
        assertEq(unscheduled.eta, 0);

        vm.roll(block.number + 2);
        vm.prank(voter1);
        governor.castVote(proposalId, 1);
        vm.roll(block.number + 10);
        governor.queue(pTargets, pValues, pCalldatas, pDescriptionHash);

        DAOReadHub.TimelockStatus memory queued = hub.timelockStatus(pTargets, pValues, pCalldatas, pDescriptionHash);
        assertTrue(queued.pending);
        assertFalse(queued.ready);
        assertGt(queued.eta, block.timestamp);

        vm.warp(block.timestamp + 1 days + 1);
        DAOReadHub.TimelockStatus memory ready = hub.timelockStatus(pTargets, pValues, pCalldatas, pDescriptionHash);
        assertTrue(ready.ready);

        governor.execute(pTargets, pValues, pCalldatas, pDescriptionHash);
        DAOReadHub.TimelockStatus memory done = hub.timelockStatus(pTargets, pValues, pCalldatas, pDescriptionHash);
        assertTrue(done.done);
    }
}
