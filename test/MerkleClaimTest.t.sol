// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Merkle} from "lib/murky/src/Merkle.sol";
import {MembershipNFT} from "src/MembershipNFT.sol";
import {MerkleClaim} from "src/MerkleClaim.sol";

contract MerkleClaimTest is Test {
    Merkle m = new Merkle();
    MembershipNFT nft;
    MerkleClaim merkleClaim;

    address alice;
    uint256 alicePrivKey;
    address bob;
    uint256 bobPrivKey;
    address charlie;
    uint256 charliePrivKey;
    address david;
    uint256 davidPrivKey;

    address nonClaimant;
    uint256 nonClaimantPrivKey;

    address deployer;
    address relayer;

    mapping(address => bytes32[]) internal s_proofs;
    mapping(address => uint256) internal s_votingPowers;
    mapping(address => uint256) internal s_privKeys;

    function setUp() external {
        deployer = makeAddr("deployer");
        relayer = makeAddr("relayer");

        (alice, alicePrivKey) = makeAddrAndKey("alice");
        (bob, bobPrivKey) = makeAddrAndKey("bob");
        (charlie, charliePrivKey) = makeAddrAndKey("charlie");
        (david, davidPrivKey) = makeAddrAndKey("david");

        bytes32[] memory leaves = new bytes32[](4);

        leaves[0] = keccak256(bytes.concat(keccak256(abi.encode(alice, 10))));
        leaves[1] = keccak256(bytes.concat(keccak256(abi.encode(bob, 20))));
        leaves[2] = keccak256(bytes.concat(keccak256(abi.encode(charlie, 30))));
        leaves[3] = keccak256(bytes.concat(keccak256(abi.encode(david, 40))));

        // Let murky do the heavy lifting
        bytes32 root = m.getRoot(leaves);

        // Save data to mappings for global test access
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

        // 1. Predict MerkleClaim's address
        // The deployer's current nonce is used for MembershipNFT. The nonce + 1 will be used for MerkleClaim.
        address predictedMerkleClaim = vm.computeCreateAddress(deployer, vm.getNonce(deployer) + 1);

        vm.startPrank(deployer);

        // 2. Deploy MembershipNFT using the predicted address
        nft = new MembershipNFT(predictedMerkleClaim, "Membership", "MEM");

        // 3. Deploy MerkleClaim
        merkleClaim = new MerkleClaim(root, address(nft));

        vm.stopPrank();

        // 4. Sanity check: Did the EVM deploy it where we predicted?
        assertEq(address(merkleClaim), predictedMerkleClaim, "Address prediction failed");

        // 5. Wire a placeholder governor so the NFT contract is fully initialized
        vm.prank(deployer);
        nft.setGovernor(makeAddr("placeholderGovernor"));
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

    // Test for Checking the setUp logic works properly
    function test_Setup_WiringIsCorrect() external view {
        // MerkleClaim is the minter on the NFT
        assertEq(nft.getMinter(), address(merkleClaim), "MerkleClaim should be NFT minter");

        // MerkleClaim has the correct NFT address
        assertEq(merkleClaim.getMembershipNFT(), address(nft), "MerkleClaim should know NFT address");

        // Merkle root is non-zero
        assertTrue(merkleClaim.getMerkleRoot() != bytes32(0), "Root should be set");

        // None of the claimants have claimed yet
        assertFalse(merkleClaim.hasClaimed(alice), "Alice should not have claimed");
        assertFalse(merkleClaim.hasClaimed(bob), "Bob should not have claimed");

        // Proofs are non-empty for all claimants
        assertTrue(s_proofs[alice].length > 0, "Alice should have a proof");
    }

    //// HAPPY PATHS TESTS ////

    // End-to-end successful claim by alice.
    function test_Claim_AliceClaimsSuccessfully() external {
        _claimAs(alice);

        assertEq(nft.ownerOf(0), alice, "Alice should own token 0");
        assertEq(nft.getVotingPowerOf(0), 10, "Token 0 should have voting power 10");
        assertEq(nft.getVotes(alice), 10, "Alice should have 10 votes");
        assertTrue(merkleClaim.hasClaimed(alice), "Alice should be marked as claimed");
    }

    // Verify the Claimed(account, votingPower, relayer) event is emitted with the correct values.
    function test_Claim_EmitsClaimedEvent() external {
        uint256 votingPower = s_votingPowers[alice];
        (uint8 v, bytes32 r, bytes32 sigS) = _signClaim(alicePrivKey, alice, votingPower);

        vm.expectEmit(true, true, false, true, address(merkleClaim));
        emit MerkleClaim.Claimed(alice, votingPower, relayer);

        vm.prank(relayer);
        merkleClaim.claim(alice, votingPower, s_proofs[alice], v, r, sigS);
    }

    // Alice claims, then bob claims, then charlie claims. Verify each got their own NFT with the correct voting power.
    function test_Claim_MultipleClaimantsIndependently() external {
        _claimAs(alice);

        assertEq(nft.ownerOf(0), alice, "Alice should own token 0");
        assertEq(nft.getVotingPowerOf(0), 10, "Token 0 should have voting power 10");
        assertEq(nft.getVotes(alice), 10, "Alice should have 10 votes");
        assertTrue(merkleClaim.hasClaimed(alice), "Alice should be marked as claimed");

        _claimAs(bob);

        assertEq(nft.ownerOf(1), bob, "Bob should own token 1");
        assertEq(nft.getVotingPowerOf(1), 20, "Token 1 should have voting power 20");
        assertEq(nft.getVotes(bob), 20, "Bob should have 20 votes");
        assertTrue(merkleClaim.hasClaimed(bob), "Bob should be marked as claimed");

        _claimAs(charlie);

        assertEq(nft.ownerOf(2), charlie, "Charlie should own token 2");
        assertEq(nft.getVotingPowerOf(2), 30, "Token 2 should have voting power 30");
        assertEq(nft.getVotes(charlie), 30, "Charlie should have 30 votes");
        assertTrue(merkleClaim.hasClaimed(charlie), "Charlie should be marked as claimed");

        assertFalse(merkleClaim.hasClaimed(david), "David should not be marked as claimed");
    }

    //// REPLAY PROTECTION TESTS ////

    // Alice claims successfully. Then alice tries to claim again with the same signature and proof.
    function test_Claim_RevertsOnReplay() external {
        // First claim succeeds
        _claimAs(alice);

        // Attempt to replay — even with a freshly-generated signature, the hasClaimed
        // mapping blocks the second attempt. This proves replay protection comes from
        // the mapping, not from signature uniqueness.
        uint256 votingPower = s_votingPowers[alice];
        (uint8 v, bytes32 r, bytes32 sigS) = _signClaim(alicePrivKey, alice, votingPower);

        vm.expectRevert(abi.encodeWithSelector(MerkleClaim.MerkleClaim__AlreadyClaimed.selector, alice));
        vm.prank(relayer);
        merkleClaim.claim(alice, votingPower, s_proofs[alice], v, r, sigS);
    }

    // After alice's claim is blocked from being replayed, bob can still claim.
    function test_Claim_DifferentClaimantsAfterReplayBlocked() external {
        _claimAs(alice); // claim 1

        // Attempt to replay alice's claim — blocked
        uint256 votingPower = s_votingPowers[alice];
        (uint8 v, bytes32 r, bytes32 sigS) = _signClaim(alicePrivKey, alice, votingPower);
        vm.expectRevert(abi.encodeWithSelector(MerkleClaim.MerkleClaim__AlreadyClaimed.selector, alice));
        vm.prank(relayer);
        merkleClaim.claim(alice, votingPower, s_proofs[alice], v, r, sigS);

        // Bob can still claim — alice's block doesn't affect him
        _claimAs(bob);
        assertTrue(merkleClaim.hasClaimed(bob), "Bob should be able to claim");
        assertEq(nft.ownerOf(1), bob, "Bob's NFT should be tokenId 1");
    }

    /// SIGNATURE VALIDATION TESTS ////

    // Wrong signer can't claim
    function test_Claim_Reverts_IfSignerIsWrong() external {
        uint256 votingPower = s_votingPowers[alice];
        // bob signs a message for alice's claim
        (uint8 v, bytes32 r, bytes32 sigS) = _signClaim(bobPrivKey, alice, votingPower);
        vm.expectRevert(abi.encodeWithSelector(MerkleClaim.MerkleClaim__InvalidSignature.selector));
        vm.prank(relayer);
        merkleClaim.claim(alice, votingPower, s_proofs[alice], v, r, sigS);
    }

    // Wrong voting power in signature reverts
    function test_Claim_Reverts_IfWrongVotingPowerInSignature() external {
        uint256 votingPower = s_votingPowers[alice];
        uint256 wrongVotingPower = 99;
        // alice signs a message with a specific voting power
        (uint8 v, bytes32 r, bytes32 sigS) = _signClaim(alicePrivKey, alice, votingPower);
        vm.expectRevert(abi.encodeWithSelector(MerkleClaim.MerkleClaim__InvalidSignature.selector));
        // the claim for alice is using a different voting power
        vm.prank(relayer);
        merkleClaim.claim(alice, wrongVotingPower, s_proofs[alice], v, r, sigS);
    }

    // Wrong account in signed message reverts
    function test_Claim_Reverts_IfWrongAccountInSignMessage() external {
        uint256 votingPower = s_votingPowers[bob];
        // alice signs a message with bob's digest
        bytes32 digestForBob = merkleClaim.getMessageHash(bob, votingPower);
        uint8 v;
        bytes32 r;
        bytes32 s;
        (v, r, s) = vm.sign(alicePrivKey, digestForBob);
        vm.expectRevert(abi.encodeWithSelector(MerkleClaim.MerkleClaim__InvalidSignature.selector));
        vm.prank(relayer);
        merkleClaim.claim(alice, votingPower, s_proofs[alice], v, r, s);
    }

    // Reverts for malleable signatures
    function test_Claim_Reverts_IfSignatureIsMalleable() external {
        // The secp256k1 curve order constant needed to calculate the malleable signature
        uint256 SECP256K1_N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;

        // 1. Get Alice's legitimate signature using our helper
        uint256 votingPower = s_votingPowers[alice];
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(alicePrivKey, alice, votingPower);

        // 2. Compute the malleable equivalent (The "Shadow" Signature)
        // We subtract the original 's' from the curve order (N) and flip the 'v' value.
        bytes32 malleableS = bytes32(SECP256K1_N - uint256(s));
        uint8 malleableV = v == 27 ? 28 : 27;

        // 3. Setup the Revert Expectation
        // Defense-in-depth note: Even if this bypassed OZ's ECDSA check,
        // the transaction would still fail on a replay due to the `s_hasClaimed` mapping.
        // However, we test this to ensure OpenZeppelin's protection is actively working.
        vm.expectRevert(MerkleClaim.MerkleClaim__InvalidSignature.selector);

        // 4. Submit the malleable signature as the relayer
        vm.prank(relayer);
        merkleClaim.claim(alice, votingPower, s_proofs[alice], malleableV, r, malleableS);
    }

    // Reverts if a signature generated for one contract is used on another
    function test_Claim_Reverts_IfSignatureUsedOnDifferentContract() external {
        uint256 votingPower = s_votingPowers[alice];

        // 1. Generate Alice's signature for the ORIGINAL merkleClaim contract
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(alicePrivKey, alice, votingPower);

        // 2. Deploy a SECOND MerkleClaim instance
        // It has the exact same Merkle Root and NFT, but because the deployer's
        // nonce has increased, it will be deployed to a totally different address.
        vm.prank(deployer);
        MerkleClaim merkleClaim2 = new MerkleClaim(merkleClaim.getMerkleRoot(), address(nft));

        // 3. Setup the Revert Expectation
        // We specifically want to ensure it fails because of the signature,
        // not because the second contract isn't the minter for the NFT.
        vm.expectRevert(MerkleClaim.MerkleClaim__InvalidSignature.selector);

        // 4. Try to submit the original signature to the NEW contract
        vm.prank(relayer);
        merkleClaim2.claim(alice, votingPower, s_proofs[alice], v, r, s);
    }
}
