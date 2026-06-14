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
}
