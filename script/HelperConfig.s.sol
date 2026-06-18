// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        bytes32 merkleRoot;
        uint256 timelockMinDelay;
        uint48 votingDelay;
        uint32 votingPeriod;
        uint256 proposalThreshold;
        uint256 quorumPercentage;
    }

    NetworkConfig private activeConfig;

    constructor() {
        if (block.chainid == 11155111) {
            activeConfig = getSepoliaConfig();
        } else {
            activeConfig = getLocalConfig();
        }
    }

    function getActiveConfig() external view returns (NetworkConfig memory) {
        return activeConfig;
    }

    function getSepoliaConfig() internal pure returns (NetworkConfig memory) {
        return NetworkConfig({
            merkleRoot: 0x87103e673fa76d1dc759138b80f11019d1fd238ecd6ecfd178ca871099c5f81f,
            timelockMinDelay: 1 hours,
            votingDelay: 1,
            votingPeriod: 50,
            proposalThreshold: 1,
            quorumPercentage: 4
        });
    }

    function getLocalConfig() internal pure returns (NetworkConfig memory) {
        return NetworkConfig({
            merkleRoot: bytes32(0), // PLACEHOLDER
            timelockMinDelay: 1 hours,
            votingDelay: 1,
            votingPeriod: 50,
            proposalThreshold: 1,
            quorumPercentage: 4
        });
    }
}
