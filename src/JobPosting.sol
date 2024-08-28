// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./UserManagement.sol";

contract JobPosting is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using Counters for Counters.Counter;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant JOB_MANAGER_ROLE = keccak256("JOB_MANAGER_ROLE");

    struct Job {
        uint256 id;
        address client;
        string ipfsHash;
        uint256 budget;
        uint256 deadline;
        address hiredFreelancer;
        bool isCompleted;
        bool isCancelled;
        JobStatus status;
        uint256 createdAt;
        uint256 completedAt;
    }

    enum JobStatus { Posted, InProgress, Completed, Cancelled, Disputed }

    UserManagement public userManagement;
    IERC20 public paymentToken;
    Counters.Counter private _jobIdCounter;
    mapping(uint256 => Job) public jobs;
    mapping(uint256 => mapping(address => bool)) public jobProposals;

    uint256 public constant MAX_JOB_DURATION = 365 days;
    uint256 public constant MIN_JOB_BUDGET = 1e18; // 1 token

    event JobCreated(uint256 indexed jobId, address indexed client, uint256 budget, uint256 deadline);
    event ProposalSubmitted(uint256 indexed jobId, address indexed freelancer);
    event FreelancerHired(uint256 indexed jobId, address indexed freelancer);
    event JobCompleted(uint256 indexed jobId);
    event JobCancelled(uint256 indexed jobId);
    event JobDisputed(uint256 indexed jobId);
    event DisputeResolved(uint256 indexed jobId, address winner);

    constructor(address _userManagementAddress, address _paymentTokenAddress) {
        userManagement = UserManagement(_userManagementAddress);
        paymentToken = IERC20(_paymentTokenAddress);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(ADMIN_ROLE, msg.sender);
        _setupRole(JOB_MANAGER_ROLE, msg.sender);
    }

    modifier onlyClient(uint256 _jobId) {
        require(jobs[_jobId].client == msg.sender, "Only job client can perform this action");
        _;
    }

    modifier onlyActiveJob(uint256 _jobId) {
        require(jobs[_jobId].status == JobStatus.Posted || jobs[_jobId].status == JobStatus.InProgress, "Job is not active");
        _;
    }

    modifier jobExists(uint256 _jobId) {
        require(_jobId < _jobIdCounter.current(), "Job does not exist");
        _;
    }

    function createJob(string memory _ipfsHash, uint256 _budget, uint256 _deadline) external nonReentrant whenNotPaused {
        require(userManagement.users(msg.sender).userAddress != address(0), "User not registered");
        require(!userManagement.users(msg.sender).isFreelancer, "Freelancers cannot create jobs");
        require(_deadline > block.timestamp, "Deadline must be in the future");
        require(_deadline <= block.timestamp + MAX_JOB_DURATION, "Job duration exceeds maximum allowed");
        require(_budget >= MIN_JOB_BUDGET, "Job budget is below minimum allowed");

        uint256 jobId = _jobIdCounter.current();
        jobs[jobId] = Job({
            id: jobId,
            client: msg.sender,
            ipfsHash: _ipfsHash,
            budget: _budget,
            deadline: _deadline,
            hiredFreelancer: address(0),
            isCompleted: false,
            isCancelled: false,
            status: JobStatus.Posted,
            createdAt: block.timestamp,
            completedAt: 0
        });
        _jobIdCounter.increment();

        paymentToken.safeTransferFrom(msg.sender, address(this), _budget);

        emit JobCreated(jobId, msg.sender, _budget, _deadline);
    }

    function submitProposal(uint256 _jobId) external nonReentrant whenNotPaused jobExists(_jobId) {
        require(userManagement.users(msg.sender).isFreelancer, "Only freelancers can submit proposals");
        require(jobs[_jobId].status == JobStatus.Posted, "Job is not open for proposals");
        require(!jobProposals[_jobId][msg.sender], "Proposal already submitted");
        require(block.timestamp < jobs[_jobId].deadline, "Job deadline has passed");

        jobProposals[_jobId][msg.sender] = true;
        emit ProposalSubmitted(_jobId, msg.sender);
    }

    function hireFreelancer(uint256 _jobId, address _freelancer) external nonReentrant whenNotPaused onlyClient(_jobId) onlyActiveJob(_jobId) {
        require(jobs[_jobId].hiredFreelancer == address(0), "Freelancer already hired");
        require(userManagement.users(_freelancer).isFreelancer, "Hired address must be a freelancer");
        require(jobProposals[_jobId][_freelancer], "Freelancer has not submitted a proposal");
        require(block.timestamp < jobs[_jobId].deadline, "Job deadline has passed");

        jobs[_jobId].hiredFreelancer = _freelancer;
        jobs[_jobId].status = JobStatus.InProgress;
        emit FreelancerHired(_jobId, _freelancer);
    }

    function completeJob(uint256 _jobId) external nonReentrant whenNotPaused onlyClient(_jobId) onlyActiveJob(_jobId) {
        require(jobs[_jobId].hiredFreelancer != address(0), "No freelancer hired for this job");
        require(block.timestamp <= jobs[_jobId].deadline, "Job deadline has passed");

        jobs[_jobId].isCompleted = true;
        jobs[_jobId].status = JobStatus.Completed;
        jobs[_jobId].completedAt = block.timestamp;

        address freelancer = jobs[_jobId].hiredFreelancer;
        uint256 payment = jobs[_jobId].budget;

        paymentToken.safeTransfer(freelancer, payment);
        userManagement.completeJob(freelancer, payment);

        emit JobCompleted(_jobId);
    }

    function cancelJob(uint256 _jobId) external nonReentrant whenNotPaused onlyClient(_jobId) onlyActiveJob(_jobId) {
        require(jobs[_jobId].hiredFreelancer == address(0), "Cannot cancel job after hiring freelancer");

        jobs[_jobId].isCancelled = true;
        jobs[_jobId].status = JobStatus.Cancelled;

        paymentToken.safeTransfer(jobs[_jobId].client, jobs[_jobId].budget);

        emit JobCancelled(_jobId);
    }

    function initiateDispute(uint256 _jobId) external nonReentrant whenNotPaused onlyActiveJob(_jobId) {
        require(msg.sender == jobs[_jobId].client || msg.sender == jobs[_jobId].hiredFreelancer, "Only client or hired freelancer can initiate dispute");
        
        jobs[_jobId].status = JobStatus.Disputed;
        emit JobDisputed(_jobId);
    }

    function resolveDispute(uint256 _jobId, address _winner) external onlyRole(JOB_MANAGER_ROLE) {
        require(jobs[_jobId].status == JobStatus.Disputed, "Job is not in disputed state");
        require(_winner == jobs[_jobId].client || _winner == jobs[_jobId].hiredFreelancer, "Invalid winner address");

        if (_winner == jobs[_jobId].hiredFreelancer) {
            paymentToken.safeTransfer(jobs[_jobId].hiredFreelancer, jobs[_jobId].budget);
            userManagement.completeJob(jobs[_jobId].hiredFreelancer, jobs[_jobId].budget);
        } else {
            paymentToken.safeTransfer(jobs[_jobId].client, jobs[_jobId].budget);
        }

        jobs[_jobId].isCompleted = true;
        jobs[_jobId].status = JobStatus.Completed;
        jobs[_jobId].completedAt = block.timestamp;

        emit DisputeResolved(_jobId, _winner);
    }

    function getJob(uint256 _jobId) external view returns (Job memory) {
        require(_jobId < _jobIdCounter.current(), "Job does not exist");
        return jobs[_jobId];
    }

    function getJobProposals(uint256 _jobId) external view returns (address[] memory) {
        require(_jobId < _jobIdCounter.current(), "Job does not exist");
        uint256 proposalCount = 0;
        for (uint256 i = 0; i < _jobIdCounter.current(); i++) {
            if (jobProposals[_jobId][address(uint160(i))]) {
                proposalCount++;
            }
        }
        address[] memory proposals = new address[](proposalCount);
        uint256 index = 0;
        for (uint256 i = 0; i < _jobIdCounter.current(); i++) {
            if (jobProposals[_jobId][address(uint160(i))]) {
                proposals[index] = address(uint160(i));
                index++;
            }
        }
        return proposals;
    }

    function extendJobDeadline(uint256 _jobId, uint256 _newDeadline) external onlyClient(_jobId) onlyActiveJob(_jobId) {
        require(_newDeadline > jobs[_jobId].deadline, "New deadline must be later than current deadline");
        require(_newDeadline <= block.timestamp + MAX_JOB_DURATION, "New deadline exceeds maximum allowed job duration");
        jobs[_jobId].deadline = _newDeadline;
    }

    function increaseBudget(uint256 _jobId, uint256 _additionalBudget) external nonReentrant onlyClient(_jobId) onlyActiveJob(_jobId) {
        require(_additionalBudget > 0, "Additional budget must be greater than zero");
        paymentToken.safeTransferFrom(msg.sender, address(this), _additionalBudget);
        jobs[_jobId].budget += _additionalBudget;
    }

    function getActiveJobCount() external view returns (uint256) {
        uint256 activeCount = 0;
        for (uint256 i = 0; i < _jobIdCounter.current(); i++) {
            if (jobs[i].status == JobStatus.Posted || jobs[i].status == JobStatus.InProgress) {
                activeCount++;
            }
        }
        return activeCount;
    }

    function pauseContract() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpauseContract() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }
}