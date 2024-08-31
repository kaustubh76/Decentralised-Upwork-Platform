/ SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/WorkSubmission.sol";
import "../src/UserManagement.sol";
import "../src/JobPosting.sol";
import "../src/ProposalManagement.sol";

contract WorkSubmissionTest is Test {
    WorkSubmission workSubmission;
    UserManagement userManagement;
    JobPosting jobPosting;
    ProposalManagement proposalManagement;

    address owner = address(1);
    address client = address(2);
    address freelancer = address(3);
    address otherUser = address(4);

    uint256 jobId ;
    uint256 proposalId;

    function setUp() public {
        vm.startPrank(owner);
        userManagement = new UserManagement();
        jobPosting = new JobPosting(address(userManagement), address(0));
        proposalManagement = new ProposalManagement(address(userManagement), address(jobPosting));
        workSubmission = new WorkSubmission(address(userManagement), address(jobPosting), address(proposalManagement));
        vm.stopPrank();

        //users
        vm.prank(client);
        userManagement.registerUser(true);
        vm.prank(freelancer);
        userManagement.registerUser(true);

        // Create a job as a client
        vm.startPrank(client);
        jobId = jobPosting.createJob("jobipfs", 1 ether,block.timestamp + 7 days);
        vm.stopPrank();

        // Submit a proposal as a freelancer
        vm.startPrank(freelancer);
        proposalId = proposalManagement.submitProposal(jobId,"proposalipfs", 1 ether,block.timestamp + 5 days);
        vm.stopPrank();

        // Accept the proposal and hire the freelancer as the client
        vm.prank(client);
        jobPosting.hireFreelancer(jobId, freelancer);
    }

    function testSubmitWork() public {
        vm.prank(freelancer);
        workSubmission.submitWork(jobId, "workipfs", "commentipfs");

        (uint256 id, uint256 submittedJobId, address submitter, string memory workIPFSHash, 
         string memory commentIPFSHash, WorkSubmission.SubmissionStatus status, uint256 submittedAt) = workSubmission.jobSubmissions(jobId, 0);

        assertEq(id, 1);
        assertEq(submittedJobId, jobId);
        assertEq(submitter, freelancer);
        assertEq(workIPFSHash, "workipfs");
        assertEq(commentIPFSHash, "commentipfs");
        assertEq(uint(status), uint(WorkSubmission.SubmissionStatus.Pending));
        assertEq(submittedAt, block.timestamp);
    }

    function testUpdateSubmission() public {
        vm.startPrank(freelancer);
        workSubmission.submitWork(jobId, "workipfs", "commentipfs");
        workSubmission.updateSubmission(jobId, 1, "newworkipfs", "newcommentipfs");
        vm.stopPrank();

        (,,,string memory workIPFSHash, string memory commentIPFSHash, WorkSubmission.SubmissionStatus status,) = workSubmission.jobSubmissions(jobId, 0);

        assertEq(workIPFSHash, "newworkipfs");
        assertEq(commentIPFSHash, "newcommentipfs");
        assertEq(uint(status), uint(WorkSubmission.SubmissionStatus.Revised));
    }

    function testApproveSubmission() public {
        vm.prank(freelancer);
        workSubmission.submitWork(jobId, "workipfs", "commentipfs");

        vm.prank(client);
        workSubmission.approveSubmission(jobId, 1);

        (,,,,, WorkSubmission.SubmissionStatus status,) = workSubmission.jobSubmissions(jobId, 0);
        assertEq(uint(status), uint(WorkSubmission.SubmissionStatus.Approved));

        JobPosting.Job memory job = jobPosting.getJob(jobId);
        assertEq(uint(job.status), uint(JobPosting.JobStatus.Completed));
    }

    function testRejectSubmission() public {
        vm.prank(freelancer);
        workSubmission.submitWork(jobId, "workipfs", "commentipfs");

        vm.prank(client);
        workSubmission.rejectSubmission(jobId, 1, "feedbackipfs");

        (,,,, string memory commentIPFSHash, WorkSubmission.SubmissionStatus status,) = workSubmission.jobSubmissions(jobId, 0);
        assertEq(uint(status), uint(WorkSubmission.SubmissionStatus.Rejected));
        assertEq(commentIPFSHash, "feedbackipfs");
    }

    function testGetJobSubmissions() public {
        vm.prank(freelancer);
        workSubmission.submitWork(jobId, "workipfs1", "commentipfs1");
        vm.prank(freelancer);
        workSubmission.submitWork(jobId, "workipfs2", "commentipfs2");

        vm.prank(client);
        WorkSubmission.Submission[] memory submissions = workSubmission.getJobSubmissions(jobId);

        assertEq(submissions.length, 2);
        assertEq(submissions[0].workIPFSHash, "workipfs1");
        assertEq(submissions[1].workIPFSHash, "workipfs2");
    }

    function testOnlyJobFreelancerCanSubmit() public {
        vm.prank(otherUser);
        vm.expectRevert("Only the hired freelancer can perform this action");
        workSubmission.submitWork(jobId, "workipfs", "commentipfs");
    }

    function testOnlyJobClientCanApprove() public {
        vm.prank(freelancer);
        workSubmission.submitWork(jobId, "workipfs", "commentipfs");

        vm.prank(otherUser);
        vm.expectRevert("Only the job client can perform this action");
        workSubmission.approveSubmission(jobId, 1);
    }

    function testPauseAndUnpause() public {
        vm.prank(owner);
        workSubmission.pause();

        vm.prank(freelancer);
        vm.expectRevert("Pausable: paused");
        workSubmission.submitWork(jobId, "workipfs", "commentipfs");

        vm.prank(owner);
        workSubmission.unpause();

        vm.prank(freelancer);
        workSubmission.submitWork(jobId, "workipfs", "commentipfs");
        // Check if submission was successful after unpausing
        (uint256 id,,,,,,) = workSubmission.jobSubmissions(jobId, 0);
        assertEq(id, 1);
    }

    function testOnlyOwnerCanPauseAndUnpause() public {
        vm.prank(otherUser);
        vm.expectRevert("Ownable: caller is not the owner");
        workSubmission.pause();

        vm.prank(otherUser);
        vm.expectRevert("Ownable: caller is not the owner");
        workSubmission.unpause();
    }
}