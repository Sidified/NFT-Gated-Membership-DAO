// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Merkle} from "lib/murky/src/Merkle.sol";
import {MembershipNFT} from "src/MembershipNFT.sol";
import {MerkleClaim} from "src/MerkleClaim.sol";
import {Handler} from "./Handler.sol";

contract Invariants is Test {
    //// REFERENCES ////
    Merkle m;
    MembershipNFT nft;
    MerkleClaim merkleClaim;
    Handler handler;

    address deployer;
    address governor; // placeholder governor for recordVote authorization

    //// CLAIMANT DATA ////
    address[4] claimants;
    uint256[4] privKeys;
    uint256[4] votingPowers;
    bytes32[][4] proofs;

    function setUp() external {
        m = new Merkle();
        deployer = makeAddr("deployer");
        governor = makeAddr("placeholderGovernor");

        // Initialize claimants and keys
        (claimants[0], privKeys[0]) = makeAddrAndKey("alice");
        (claimants[1], privKeys[1]) = makeAddrAndKey("bob");
        (claimants[2], privKeys[2]) = makeAddrAndKey("charlie");
        (claimants[3], privKeys[3]) = makeAddrAndKey("david");

        votingPowers[0] = 10;
        votingPowers[1] = 20;
        votingPowers[2] = 30;
        votingPowers[3] = 40;

        // Build Merkle Tree
        bytes32[] memory leaves = new bytes32[](4);
        leaves[0] = keccak256(bytes.concat(keccak256(abi.encode(claimants[0], votingPowers[0]))));
        leaves[1] = keccak256(bytes.concat(keccak256(abi.encode(claimants[1], votingPowers[1]))));
        leaves[2] = keccak256(bytes.concat(keccak256(abi.encode(claimants[2], votingPowers[2]))));
        leaves[3] = keccak256(bytes.concat(keccak256(abi.encode(claimants[3], votingPowers[3]))));

        bytes32 root = m.getRoot(leaves);

        proofs[0] = m.getProof(leaves, 0);
        proofs[1] = m.getProof(leaves, 1);
        proofs[2] = m.getProof(leaves, 2);
        proofs[3] = m.getProof(leaves, 3);

        // Deploy System
        address predictedMerkleClaim = vm.computeCreateAddress(deployer, vm.getNonce(deployer) + 1);

        vm.startPrank(deployer);
        nft = new MembershipNFT(predictedMerkleClaim, "Membership", "MEM");
        merkleClaim = new MerkleClaim(root, address(nft));
        nft.setGovernor(governor);
        vm.stopPrank();

        // Construct Handler
        handler = new Handler(nft, merkleClaim, governor, claimants, privKeys, votingPowers, proofs);

        // Tell Foundry to restrict fuzzing ONLY to the handler contract
        targetContract(address(handler));
    }

    //// INVARIANTS ////

    function invariant_SupplyMatchesClaimedCount() external view {
        // The NFT's totalSupply should equal the number of accounts we've successfully claimed
        // We need to use s_tokenCounter - 1 instead (since counter starts at 1 and increments after each mint).
        // This math is safe because s_tokenCounter only ever increments.
        uint256 nftSupply = nft.getTokenCounter() - 1;
        assertEq(nftSupply, handler.ghost_claimedCount(), "Supply-Claim Consistency violated");
    }

    function invariant_OneNFTPerAddress() external view {
        // For each known claimant, balance must be exactly 0 or 1.
        for (uint256 i = 0; i < 4; i++) {
            address claimant = claimants[i];
            assertLe(nft.balanceOf(claimant), 1, "One NFT per address violated");
        }
    }

    function invariant_VotesCastMatchesExpected() external view {
        // For each token that's been minted, ghost expected votes should perfectly match actual votes cast
        for (uint256 i = 0; i < 4; i++) {
            address claimant = claimants[i];
            if (!handler.ghost_hasClaimed(claimant)) continue;

            uint256 tokenId = nft.tokenIdOf(claimant);
            assertEq(
                nft.getVotesCastOf(tokenId),
                handler.ghost_expectedVotesCast(tokenId),
                "Votes cast monotonicity/equality violated"
            );
        }
    }

    function invariant_HasClaimedIsMonotonic() external view {
        // If a claimant has claimed in our ghost state, the actual contract MUST reflect that.
        // This ensures the hasClaimed status never accidentally flips back to false.
        for (uint256 i = 0; i < 4; i++) {
            address claimant = claimants[i];
            if (handler.ghost_hasClaimed(claimant)) {
                assertTrue(merkleClaim.hasClaimed(claimant), "hasClaimed monotonicity violated");
            }
        }
    }
}
