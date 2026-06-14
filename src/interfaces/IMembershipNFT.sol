// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IMembershipNFT {
    function mint(address to, uint256 votingPower) external;
}
