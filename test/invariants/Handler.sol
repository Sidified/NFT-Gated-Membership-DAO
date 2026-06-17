// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Merkle} from "lib/murky/src/Merkle.sol";
import {MembershipNFT} from "src/MembershipNFT.sol";
import {MerkleClaim} from "src/MerkleClaim.sol";

contract Handler is Test {
    //// REFERENCES ////
    MembershipNFT nft;
    MerkleClaim merkleClaim;
    address governor; // we need to prank as the governor for recordVote

    //// CLAIMANT DATA ////
    address[4] claimants;
    uint256[4] privKeys;
    uint256[4] votingPowers;
    bytes32[][4] proofs;

    //// GHOST STATE ////
    mapping(address => bool) public ghost_hasClaimed;
    uint256 public ghost_claimedCount;
    // UPDATED: Renamed to reflect exact equality testing rather than loose monotonicity
    mapping(uint256 => uint256) public ghost_expectedVotesCast;

    //// CONSTRUCTOR ////
    constructor(
        MembershipNFT _nft,
        MerkleClaim _merkleClaim,
        address _governor,
        address[4] memory _claimants,
        uint256[4] memory _privKeys,
        uint256[4] memory _votingPowers,
        bytes32[][4] memory _proofs
    ) {
        nft = _nft;
        merkleClaim = _merkleClaim;
        governor = _governor;
        claimants = _claimants;
        privKeys = _privKeys;
        votingPowers = _votingPowers;
        proofs = _proofs;
    }

    //// HELPER ////
    function _signClaim(uint256 privateKey, address account, uint256 votingPower)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        bytes32 digest = merkleClaim.getMessageHash(account, votingPower);
        (v, r, s) = vm.sign(privateKey, digest);
    }

    //// HANDLER ACTIONS ////

    function claim(uint256 seed) external {
        uint256 index = bound(seed, 0, 3);
        address claimant = claimants[index];

        // Pre-condition: only attempt claim if they haven't already.
        // This prevents expected reverts from failing the fuzz run.
        if (ghost_hasClaimed[claimant]) return;

        uint256 votingPower = votingPowers[index];
        uint256 privKey = privKeys[index];
        bytes32[] memory proof = proofs[index];

        (uint8 v, bytes32 r, bytes32 sigS) = _signClaim(privKey, claimant, votingPower);

        // Action: The handler acts as the relayer submitting the claim
        merkleClaim.claim(claimant, votingPower, proof, v, r, sigS);

        // Update ghost state tracking
        ghost_hasClaimed[claimant] = true;
        ghost_claimedCount++;
    }

    function recordVote(uint256 seed) external {
        uint256 index = bound(seed, 0, 3);
        address claimant = claimants[index];

        // Pre-condition: cannot vote if they haven't claimed an NFT
        if (!ghost_hasClaimed[claimant]) return;

        uint256 tokenId = nft.tokenIdOf(claimant);

        // Action: Governor is the only one authorized to record votes
        vm.prank(governor);
        nft.recordVote(tokenId);

        // Update ghost state tracking
        ghost_expectedVotesCast[tokenId]++;
    }

    function attemptDoubleClaim(uint256 seed) external {
        uint256 index = bound(seed, 0, 3);
        address claimant = claimants[index];

        // Pre-condition: They must have ALREADY claimed for this to be a double-claim attempt
        if (!ghost_hasClaimed[claimant]) return;

        uint256 votingPower = votingPowers[index];
        uint256 privKey = privKeys[index];
        bytes32[] memory proof = proofs[index];

        (uint8 v, bytes32 r, bytes32 sigS) = _signClaim(privKey, claimant, votingPower);

        // Action: Using try/catch as instructed. If it succeeds anomalously,
        // the system-level invariants (e.g., Supply-Claim Consistency) will fail.
        try merkleClaim.claim(claimant, votingPower, proof, v, r, sigS) {
        // Should not succeed
        }
            catch {
            // Expected revert path: do nothing, let the fuzzer continue
        }
    }
}
