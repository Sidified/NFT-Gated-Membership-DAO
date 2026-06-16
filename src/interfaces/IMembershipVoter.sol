// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @notice Interface for contracts that need to read voting identity
 *         and record voting activity on the MembershipNFT.
 * @dev Segregated from IMembershipNFT (which is for minting-side dependencies).
 *      This interface is consumed by GovernorContract; mint is intentionally
 *      excluded to enforce the Principle of Least Knowledge.
 */
interface IMembershipVoter {
    function recordVote(uint256 tokenId) external;
    function tokenIdOf(address account) external view returns (uint256);
}
