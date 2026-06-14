// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IMembershipNFT} from "./interfaces/IMembershipNFT.sol";

/**
 * @title MerkleClaim
 * @notice Allows verified users to claim a Membership NFT via a Merkle proof and EIP-712 signature.
 * @dev Implements OpenZeppelin's EIP712 and MerkleProof libraries. Enforces a strict one-claim-per-address
 * policy and utilizes a relayer-friendly architecture where the claimant signs consent off-chain.
 */
contract MerkleClaim is EIP712 {
    //// ERRORS ////
    error MerkleClaim__InvalidVotingPower();
    error MerkleClaim__AlreadyClaimed(address account);
    error MerkleClaim__InvalidSignature();
    error MerkleClaim__InvalidMerkleProof();

    //// STATE VARIABLES ////
    IMembershipNFT private immutable i_membershipNFT;
    bytes32 private immutable i_merkleRoot;
    mapping(address claimant => bool) private s_hasClaimed;

    // EIP-712 specific: inherited from OZ's EIP712 base contract
    bytes32 private constant CLAIM_TYPEHASH = keccak256("Claim(address account,uint256 votingPower)");

    //// EVENTS ////

    /**
     * @notice Emitted when a user successfully claims their Membership NFT.
     * @param account The address of the user receiving the NFT.
     * @param votingPower The amount of voting power assigned to the NFT.
     * @param relayer The address that submitted the transaction (pays the gas).
     */
    event Claimed(address indexed account, uint256 votingPower, address indexed relayer);

    //// CONSTRUCTOR ////

    /**
     * @notice Initializes the claim contract with the Merkle root and NFT contract address.
     * @param merkleRoot The root of the Merkle tree containing eligible claimants.
     * @param membershipNFT The address of the deployed MembershipNFT contract.
     */
    constructor(bytes32 merkleRoot, address membershipNFT) EIP712("NFT Gated Membership DAO", "1") {
        i_merkleRoot = merkleRoot;
        i_membershipNFT = IMembershipNFT(membershipNFT);
    }

    //// EXTERNAL FUNCTIONS ////

    /**
     * @notice Claims a Membership NFT for a verified account. Can be called by anyone (relayer).
     * @dev Follows CEI pattern. Reverts if already claimed, if signature is invalid, or if proof fails.
     * @param account The address of the eligible claimant.
     * @param votingPower The assigned voting power for the claimant.
     * @param merkleProof The array of sibling hashes to prove the leaf exists in the tree.
     * @param v The recovery byte of the EIP-712 signature.
     * @param r Half of the ECDSA signature pair.
     * @param s Half of the ECDSA signature pair.
     */
    function claim(address account, uint256 votingPower, bytes32[] calldata merkleProof, uint8 v, bytes32 r, bytes32 s)
        external
    {
        // CEI: Checks (cheapest first) -> Effects -> Interactions
        // Order matters for both gas efficiency (fail fast) and reentrancy safety.
        if (votingPower == 0) revert MerkleClaim__InvalidVotingPower();
        if (s_hasClaimed[account]) revert MerkleClaim__AlreadyClaimed(account);
        if (!_verifySignature(account, votingPower, v, r, s)) revert MerkleClaim__InvalidSignature();

        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(account, votingPower))));
        if (!MerkleProof.verify(merkleProof, i_merkleRoot, leaf)) revert MerkleClaim__InvalidMerkleProof();

        s_hasClaimed[account] = true;
        emit Claimed(account, votingPower, msg.sender);

        i_membershipNFT.mint(account, votingPower);
    }

    //// INTERNAL HELPER FUNCTIONS ////

    /**
     * @notice Computes the EIP-712 digest for a claim.
     */
    function _computeDigest(address account, uint256 votingPower) internal view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(CLAIM_TYPEHASH, account, votingPower)));
    }

    /**
     * @notice Verifies that an EIP-712 signature was created by the target account.
     */
    function _verifySignature(address account, uint256 votingPower, uint8 v, bytes32 r, bytes32 s)
        internal
        view
        returns (bool)
    {
        bytes32 digest = _computeDigest(account, votingPower);

        (address recovered, ECDSA.RecoverError err,) = ECDSA.tryRecover(digest, v, r, s);

        if (err != ECDSA.RecoverError.NoError) {
            return false;
        }

        return recovered == account;
    }

    //// VIEW FUNCTIONS ////

    /**
     * @notice Generates the EIP-712 digest that a user must sign off-chain.
     */
    function getMessageHash(address account, uint256 votingPower) public view returns (bytes32) {
        return _computeDigest(account, votingPower);
    }

    /**
     * @notice Returns the immutable Merkle root used for verifying claims.
     */
    function getMerkleRoot() public view returns (bytes32) {
        return i_merkleRoot;
    }

    /**
     * @notice Returns the address of the MembershipNFT contract.
     */
    function getMembershipNFT() public view returns (address) {
        return address(i_membershipNFT);
    }

    /**
     * @notice Checks if an account has already successfully claimed their NFT.
     */
    function hasClaimed(address account) public view returns (bool) {
        return s_hasClaimed[account];
    }
}
