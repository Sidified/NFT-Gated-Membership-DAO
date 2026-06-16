// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Merkle} from "lib/murky/src/Merkle.sol";
import {MembershipNFT} from "src/MembershipNFT.sol";
import {MerkleClaim} from "src/MerkleClaim.sol";
import {MembershipGovernor} from "src/MembershipGovernor.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {Box} from "src/Box.sol";

contract MembershipGovernorTest is Test {
    //// CONTRACTS ////
    Merkle m;
    MembershipNFT nft;
    MerkleClaim merkleClaim;
    TimelockController timelock;
    MembershipGovernor governor;
    Box box;

    //// ACTORS ////
    address deployer;
    address relayer;
    address alice;
    uint256 alicePrivKey;
    address bob;
    uint256 bobPrivKey;
    address charlie;
    uint256 charliePrivKey;
    address david;
    uint256 davidPrivKey;

    //// GOVERNOR SETTINGS ////
    uint256 constant MIN_TIMELOCK_DELAY = 1 hours;
    uint48 constant VOTING_DELAY = 1; // 1 block delay before voting starts
    uint32 constant VOTING_PERIOD = 50; // ~10 minutes

    // UPDATED: Threshold is 1 to strictly enforce "Members Only" proposing
    uint256 constant PROPOSAL_THRESHOLD = 1;

    uint256 constant QUORUM_PERCENTAGE = 4; // 4% of total voting power

    //// STATE CACHE ////
    mapping(address => bytes32[]) internal s_proofs;
    mapping(address => uint256) internal s_votingPowers;
    mapping(address => uint256) internal s_privKeys;

    function setUp() external {
        m = new Merkle();
        deployer = makeAddr("deployer");
        relayer = makeAddr("relayer");

        // STEP 1: Create the claimants and build the Merkle tree
        (alice, alicePrivKey) = makeAddrAndKey("alice");
        (bob, bobPrivKey) = makeAddrAndKey("bob");
        (charlie, charliePrivKey) = makeAddrAndKey("charlie");
        (david, davidPrivKey) = makeAddrAndKey("david");

        bytes32[] memory leaves = new bytes32[](4);
        leaves[0] = keccak256(bytes.concat(keccak256(abi.encode(alice, 10))));
        leaves[1] = keccak256(bytes.concat(keccak256(abi.encode(bob, 20))));
        leaves[2] = keccak256(bytes.concat(keccak256(abi.encode(charlie, 30))));
        leaves[3] = keccak256(bytes.concat(keccak256(abi.encode(david, 40))));

        bytes32 root = m.getRoot(leaves);

        s_proofs[alice] = m.getProof(leaves, 0);
        s_votingPowers[alice] = 10;
        s_privKeys[alice] = alicePrivKey;

        s_proofs[bob] = m.getProof(leaves, 1);
        s_votingPowers[bob] = 20;
        s_privKeys[bob] = bobPrivKey;

        s_proofs[charlie] = m.getProof(leaves, 2);
        s_votingPowers[charlie] = 30;
        s_privKeys[charlie] = charliePrivKey;

        s_proofs[david] = m.getProof(leaves, 3);
        s_votingPowers[david] = 40;
        s_privKeys[david] = davidPrivKey;

        // ALL DEPLOYMENTS EXECUTED BY DEPLOYER
        vm.startPrank(deployer);

        // STEP 2: Deploy the Timelock first
        address[] memory emptyArr = new address[](0);
        timelock = new TimelockController(MIN_TIMELOCK_DELAY, emptyArr, emptyArr, deployer);

        // STEP 3: Compute predicted MerkleClaim address
        address predictedMerkleClaim = vm.computeCreateAddress(deployer, vm.getNonce(deployer) + 1);

        // STEP 4: Deploy MembershipNFT and MerkleClaim
        nft = new MembershipNFT(predictedMerkleClaim, "Membership", "MEM");
        merkleClaim = new MerkleClaim(root, address(nft));
        assertEq(address(merkleClaim), predictedMerkleClaim, "Address prediction failed");

        // STEP 5: Deploy MembershipGovernor
        governor = new MembershipGovernor(
            address(nft), timelock, VOTING_DELAY, VOTING_PERIOD, PROPOSAL_THRESHOLD, QUORUM_PERCENTAGE
        );

        // STEP 6: Wire MembershipNFT's governor
        nft.setGovernor(address(governor));

        // STEP 7: Configure Timelock roles
        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();

        timelock.grantRole(proposerRole, address(governor));
        timelock.grantRole(executorRole, address(0)); // address(0) means anyone can execute

        // STEP 8: Deploy Box and transfer ownership to Timelock
        box = new Box(deployer);
        box.transferOwnership(address(timelock));

        vm.stopPrank();

        // STEP 9: Have claimants claim their NFTs
        _claimAs(alice);
        _claimAs(bob);
        _claimAs(charlie);
        _claimAs(david);

        // STEP 10: Advance block so voting checkpoints are solid
        vm.roll(block.number + 1);
    }

    //// HELPER FUNCTIONS ////

    function _signClaim(uint256 privateKey, address account, uint256 votingPower)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        bytes32 digest = merkleClaim.getMessageHash(account, votingPower);
        (v, r, s) = vm.sign(privateKey, digest);
    }

    function _claimAs(address claimant) internal {
        uint256 votingPower = s_votingPowers[claimant];
        uint256 privKey = s_privKeys[claimant];
        bytes32[] memory proof = s_proofs[claimant];

        (uint8 v, bytes32 r, bytes32 sigS) = _signClaim(privKey, claimant, votingPower);

        vm.prank(relayer);
        merkleClaim.claim(claimant, votingPower, proof, v, r, sigS);
    }

    function _buildBoxProposal(uint256 valueToStore)
        internal
        view
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description)
    {
        targets = new address[](1);
        targets[0] = address(box);

        values = new uint256[](1);
        values[0] = 0;

        calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(Box.store.selector, valueToStore);

        description = string(abi.encodePacked("Set box value to ", vm.toString(valueToStore)));
    }

    function _propose(uint256 valueToStore, address proposer) internal returns (uint256 proposalId) {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _buildBoxProposal(valueToStore);

        vm.prank(proposer);
        proposalId = governor.propose(targets, values, calldatas, description);
    }

    // Generic Vote Helper
    function _voteForOrAgainst(uint256 proposalId, address voter, uint8 support) internal {
        vm.prank(voter);
        governor.castVote(proposalId, support);
    }

    // Semantic Vote Helpers (Eliminates magic numbers)
    function _voteAgainst(uint256 proposalId, address voter) internal {
        _voteForOrAgainst(proposalId, voter, 0);
    }

    function _voteFor(uint256 proposalId, address voter) internal {
        _voteForOrAgainst(proposalId, voter, 1);
    }

    function _voteAbstain(uint256 proposalId, address voter) internal {
        _voteForOrAgainst(proposalId, voter, 2);
    }

    // Quick lifecycle helpers
    function _advanceToActive() internal {
        vm.roll(block.number + VOTING_DELAY + 1);
    }

    function _advancePastVoting() internal {
        vm.roll(block.number + VOTING_PERIOD + 1);
    }

    function _queueProposal(uint256 valueToStore) internal {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _buildBoxProposal(valueToStore);
        governor.queue(targets, values, calldatas, keccak256(bytes(description)));
    }

    function _executeProposal(uint256 valueToStore) internal {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _buildBoxProposal(valueToStore);
        governor.execute(targets, values, calldatas, keccak256(bytes(description)));
    }

    function _advancePastTimelockDelay() internal {
        vm.warp(block.timestamp + MIN_TIMELOCK_DELAY + 1);
    }

    //// TESTS ////

    function test_Setup_AllContractsWiredCorrectly() external view {
        assertEq(nft.getMinter(), address(merkleClaim), "NFT Minter is wrong");
        assertEq(nft.getGovernor(), address(governor), "NFT Governor is wrong");
        assertEq(merkleClaim.getMembershipNFT(), address(nft), "MerkleClaim NFT address is wrong");

        assertTrue(timelock.hasRole(timelock.PROPOSER_ROLE(), address(governor)), "Governor lacks PROPOSER_ROLE");
        assertTrue(timelock.hasRole(timelock.EXECUTOR_ROLE(), address(0)), "Any address lacks EXECUTOR_ROLE");

        assertEq(box.owner(), address(timelock), "Timelock does not own Box");

        assertEq(nft.getVotes(alice), 10, "Alice votes mismatch");
        assertEq(nft.getVotes(bob), 20, "Bob votes mismatch");
        assertEq(nft.getVotes(charlie), 30, "Charlie votes mismatch");
        assertEq(nft.getVotes(david), 40, "David votes mismatch");
    }

    function test_Setup_ClaimantsCanQueryHistoricalVotes() external view {
        uint256 snapshotBlock = block.number - 1;

        assertEq(nft.getPastVotes(alice, snapshotBlock), 10, "Alice historical checkpoint mismatch");
        assertEq(nft.getPastVotes(bob, snapshotBlock), 20, "Bob historical checkpoint mismatch");
    }

    //// PROPOSAL CREATION TESTS ////

    function test_Propose_MemberCanCreateProposal() external {
        uint256 proposalId = _propose(42, alice);

        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IGovernor.ProposalState.Pending),
            "Proposal state should be Pending"
        );

        assertEq(governor.proposalProposer(proposalId), alice, "Proposal proposer should be Alice");
    }

    function test_Propose_NonMemberCannotCreateProposal() external {
        address nonMember = makeAddr("nonMember");

        // Strictly verify the custom OpenZeppelin error with exact parameters
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor.GovernorInsufficientProposerVotes.selector, nonMember, 0, PROPOSAL_THRESHOLD
            )
        );
        _propose(42, nonMember);
    }

    function test_Propose_VotingDelayElapsesBeforeActive() external {
        uint256 proposalId = _propose(42, alice);

        // Still Pending immediately after proposing
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Pending));

        // Advance past the voting delay
        vm.roll(block.number + VOTING_DELAY + 1);

        // Now Active and ready for votes
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Active));
    }

    //// VOTING MECHANICS TESTS ////

    function test_Vote_VotingPowerReflectsHistoricalCheckpoint() external {
        uint256 proposalId = _propose(42, alice);

        // Advance past voting delay
        vm.roll(block.number + VOTING_DELAY + 1);

        _voteFor(proposalId, alice);

        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = governor.proposalVotes(proposalId);

        // Alice has 10 voting power checkpointed at the snapshot block
        assertEq(forVotes, 10, "For votes should match Alice's voting power");
        assertEq(againstVotes, 0, "Against votes should be 0");
        assertEq(abstainVotes, 0, "Abstain votes should be 0");
    }

    function test_Vote_CannotVoteTwice() external {
        uint256 proposalId = _propose(42, alice);

        vm.roll(block.number + VOTING_DELAY + 1);

        // First vote succeeds
        _voteFor(proposalId, alice);

        // Second vote must strictly revert with the exact OZ selector
        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorAlreadyCastVote.selector, alice));
        _voteFor(proposalId, alice);
    }

    function test_Vote_RecordVoteHookFires() external {
        uint256 proposalId = _propose(42, alice);

        vm.roll(block.number + VOTING_DELAY + 1);

        uint256 aliceTokenId = nft.tokenIdOf(alice);

        // Pre-condition: NFT votes cast should be 0
        assertEq(nft.getVotesCastOf(aliceTokenId), 0, "Initial votesCast should be 0");

        // Act: Alice votes
        _voteFor(proposalId, alice);

        // Post-condition: The custom hook in MembershipGovernor fired and updated the NFT
        assertEq(nft.getVotesCastOf(aliceTokenId), 1, "recordVote hook failed to increment votesCast");
    }

    function test_Vote_CannotVoteOutsideActiveWindow() external {
        uint256 proposalId = _propose(42, alice);

        // Voting BEFORE active (still in voting delay window -> State is Pending)
        // We use bare expectRevert here as matching complex OZ state bitmaps is pragmatic overkill for this bound
        vm.expectRevert();
        _voteFor(proposalId, alice);

        // Advance past voting period entirely -> State becomes Defeated or Succeeded
        vm.roll(block.number + VOTING_DELAY + VOTING_PERIOD + 2);

        // Voting AFTER period ends
        vm.expectRevert();
        _voteFor(proposalId, alice);
    }

    function test_Vote_NonMemberVoteDoesNotRevertButHasZeroWeight() external {
        uint256 proposalId = _propose(42, alice);
        _advanceToActive();

        address nonMember = makeAddr("nonMember");

        // Act: Non-member attempts to vote. Because of the `if (tokenId != 0)` defensive guard,
        // this call should succeed silently instead of violently crashing.
        _voteFor(proposalId, nonMember);

        // Assert: The vote registered exactly 0 weight, proving they had no influence
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = governor.proposalVotes(proposalId);
        assertEq(forVotes, 0, "Non-member vote should carry 0 weight");
        assertEq(againstVotes, 0, "Against votes should be 0");
        assertEq(abstainVotes, 0, "Abstain votes should be 0");
    }

    function test_Vote_MultipleVotersAccumulate() external {
        uint256 proposalId = _propose(42, alice);
        _advanceToActive();

        // Act: Alice (10) and Bob (20) vote For
        _voteFor(proposalId, alice);
        _voteFor(proposalId, bob);

        // Assert: Their weights perfectly combine
        (, uint256 forVotes,) = governor.proposalVotes(proposalId);
        assertEq(forVotes, 30, "Combined votes should be 30 (Alice 10 + Bob 20)");
    }

    //// PROPOSAL LIFECYCLE TESTS ////

    function test_Lifecycle_SuccessfulProposalReachesSucceeded() external {
        uint256 proposalId = _propose(42, alice);

        _advanceToActive();
        _voteFor(proposalId, alice); // Alice has 10 votes, meets quorum

        _advancePastVoting();

        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IGovernor.ProposalState.Succeeded),
            "Proposal should be Succeeded"
        );
    }

    function test_Lifecycle_DefeatedProposalShowsDefeated() external {
        uint256 proposalId = _propose(42, alice);

        _advanceToActive();
        _voteFor(proposalId, alice); // 10 For
        _voteAgainst(proposalId, bob); // 20 Against
        _voteAgainst(proposalId, david); // 40 Against

        _advancePastVoting();

        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IGovernor.ProposalState.Defeated),
            "Proposal should be Defeated"
        );
    }

    function test_Lifecycle_QuorumFailureShowsDefeated() external {
        uint256 proposalId = _propose(42, alice);
        _advanceToActive();

        // No one votes!
        // Quorum requires 4 votes.
        _advancePastVoting();

        // Assert: Fails quorum requirement and goes to Defeated.
        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IGovernor.ProposalState.Defeated),
            "Proposal should fail due to lack of quorum"
        );
    }

    function test_Lifecycle_FullProposalCanExecuteAndModifiesBox() external {
        uint256 valueToStore = 42;
        uint256 proposalId = _propose(valueToStore, alice);

        _advanceToActive();
        _voteFor(proposalId, alice);
        _voteFor(proposalId, bob); // Total 30 votes For

        _advancePastVoting();
        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IGovernor.ProposalState.Succeeded),
            "Proposal should be Succeeded"
        );

        _queueProposal(valueToStore);
        assertEq(
            uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Queued), "Proposal should be Queued"
        );

        _advancePastTimelockDelay();

        _executeProposal(valueToStore);
        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IGovernor.ProposalState.Executed),
            "Proposal should be Executed"
        );

        // The ultimate assertion: the DAO has successfully acted upon an external contract!
        assertEq(box.getValue(), valueToStore, "Box value should have been updated by governance");
    }
}
