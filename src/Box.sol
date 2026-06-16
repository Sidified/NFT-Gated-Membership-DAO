// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract Box is Ownable {
    uint256 private s_value;

    event ValueStored(uint256 newValue);

    constructor(address initialOwner) Ownable(initialOwner) {}

    function store(uint256 newValue) external onlyOwner {
        s_value = newValue;
        emit ValueStored(newValue);
    }

    function getValue() external view returns (uint256) {
        return s_value;
    }
}
