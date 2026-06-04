// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title TreasuryToken
 * @notice The DAO-governed treasury asset. Total supply is minted at deployment
 *         to a specified recipient (typically the TimelockController). No further
 *         minting, burning, or admin capability exists.
 * @dev Intentionally minimal. Any treasury expansion or burn capability would
 *      introduce an admin role inconsistent with the DAO's governance model.
 */
contract TreasuryToken is ERC20 {
    constructor(uint256 initialSupply, address initialHolder) ERC20("Treasury Token", "TRES") {
        _mint(initialHolder, initialSupply);
    }
}
