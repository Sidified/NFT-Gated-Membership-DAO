// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Merkle} from "lib/murky/src/Merkle.sol";
import {MembershipNFT} from "src/MembershipNFT.sol";
import {MerkleClaim} from "src/MerkleClaim.sol";
import {MembershipGovernor} from "src/MembershipGovernor.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
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
    uint256 constant PROPOSAL_THRESHOLD = 0; // any member can propose
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
        // Deployer nonce has incremented once due to Timelock. NFT is next, MerkleClaim is after (+1).
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
        // Deployer currently holds DEFAULT_ADMIN_ROLE on the timelock
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

    //// TESTS ////

    function test_Setup_AllContractsWiredCorrectly() external view {
        assertEq(nft.getMinter(), address(merkleClaim), "NFT Minter is wrong");
        assertEq(nft.getGovernor(), address(governor), "NFT Governor is wrong");
        assertEq(merkleClaim.getMembershipNFT(), address(nft), "MerkleClaim NFT address is wrong");

        assertTrue(timelock.hasRole(timelock.PROPOSER_ROLE(), address(governor)), "Governor lacks PROPOSER_ROLE");
        assertTrue(timelock.hasRole(timelock.EXECUTOR_ROLE(), address(0)), "Any address lacks EXECUTOR_ROLE");

        assertEq(box.owner(), address(timelock), "Timelock does not own Box");

        // Verify all claimants successfully minted and have voting power
        assertEq(nft.getVotes(alice), 10, "Alice votes mismatch");
        assertEq(nft.getVotes(bob), 20, "Bob votes mismatch");
        assertEq(nft.getVotes(charlie), 30, "Charlie votes mismatch");
        assertEq(nft.getVotes(david), 40, "David votes mismatch");
    }

    function test_Setup_ClaimantsCanQueryHistoricalVotes() external view {
        // Because we rolled to block.number + 1 in setUp, the snapshot at block.number - 1
        // should accurately reflect the voting power recorded during the claim phase.
        uint256 snapshotBlock = block.number - 1;

        assertEq(nft.getPastVotes(alice, snapshotBlock), 10, "Alice historical checkpoint mismatch");
        assertEq(nft.getPastVotes(bob, snapshotBlock), 20, "Bob historical checkpoint mismatch");
    }
}