// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {MembershipNFT} from "src/MembershipNFT.sol";
import {MerkleClaim} from "src/MerkleClaim.sol";
import {MembershipGovernor} from "src/MembershipGovernor.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {Box} from "src/Box.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployMembershipDAO is Script {
    function run()
        external
        returns (
            MembershipNFT nft,
            MerkleClaim merkleClaim,
            TimelockController timelock,
            MembershipGovernor governor,
            Box box
        )
    {
        // 1. Load configuration based on current chain
        HelperConfig config = new HelperConfig();
        HelperConfig.NetworkConfig memory cfg = config.getActiveConfig();

        // Use msg.sender as the deployer context during broadcast
        address deployer = msg.sender;
        console.log("Starting deployment with deployer:", deployer);

        vm.startBroadcast();

        // STEP 1: Deploy Timelock
        address[] memory emptyArr = new address[](0);
        // deployer gets the DEFAULT_ADMIN_ROLE initially so we can grant roles later
        timelock = new TimelockController(cfg.timelockMinDelay, emptyArr, emptyArr, deployer);
        console.log("Timelock deployed at:", address(timelock));

        // STEP 2: Compute predicted MerkleClaim address
        // deployer nonce has incremented once due to Timelock. NFT is next, MerkleClaim is after (+1).
        uint64 currentNonce = vm.getNonce(deployer);
        address predictedMerkleClaim = vm.computeCreateAddress(deployer, currentNonce + 1);

        // STEP 3: Deploy MembershipNFT
        nft = new MembershipNFT(predictedMerkleClaim, "Membership", "MEM");
        console.log("MembershipNFT deployed at:", address(nft));

        // STEP 4: Deploy MerkleClaim
        merkleClaim = new MerkleClaim(cfg.merkleRoot, address(nft));
        require(address(merkleClaim) == predictedMerkleClaim, "Address prediction mismatch!");
        console.log("MerkleClaim deployed at:", address(merkleClaim));

        // STEP 5: Deploy MembershipGovernor
        governor = new MembershipGovernor(
            address(nft), timelock, cfg.votingDelay, cfg.votingPeriod, cfg.proposalThreshold, cfg.quorumPercentage
        );
        console.log("MembershipGovernor deployed at:", address(governor));

        // STEP 6: Wire MembershipNFT.setGovernor
        nft.setGovernor(address(governor));
        console.log("Governor wired into MembershipNFT.");

        // STEP 7: Configure Timelock roles
        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();

        timelock.grantRole(proposerRole, address(governor));
        timelock.grantRole(executorRole, address(0)); // address(0) = anyone can execute
        console.log("Timelock roles successfully configured.");

        // STEP 8: Deploy Box with Timelock as owner
        // Clean optimization: Passing Timelock directly as the initial owner!
        box = new Box(address(timelock));
        console.log("Box deployed and owned by Timelock at:", address(box));

        vm.stopBroadcast();

        return (nft, merkleClaim, timelock, governor, box);
    }
}
