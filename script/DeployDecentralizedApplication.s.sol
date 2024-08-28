// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/UserManagement.sol";
import "../src/JobPosting.sol";
import "../src/ProposalManagement.sol";
import "../src/WorkSubmission.sol";

contract DeployWeb3Upwork is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        UserManagement userManagement = new UserManagement();
        console.log("UserManagement deployed to:", address(userManagement));

        JobPosting jobPosting = new JobPosting(address(userManagement));
        console.log("JobPosting deployed to:", address(jobPosting));

        ProposalManagement proposalManagement = new ProposalManagement(address(userManagement), address(jobPosting));
        console.log("ProposalManagement deployed to:", address(proposalManagement));

        WorkSubmission workSubmission = new WorkSubmission(address(userManagement), address(jobPosting), address(proposalManagement));
        console.log("WorkSubmission deployed to:", address(workSubmission));

        jobPosting.setProposalManagement(address(proposalManagement));
        jobPosting.setWorkSubmission(address(workSubmission));

        proposalManagement.setWorkSubmission(address(workSubmission));

        console.log("Post-deployment configuration completed");

        vm.stopBroadcast();
    }
}