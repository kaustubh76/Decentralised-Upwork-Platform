/ SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Escrow.sol";
import "../src/JobPosting.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MTK") {
        _mint(msg.sender, 1000000 * 10**18);
    }
}

contract EscrowTest is Test {
    Escrow public escrow;
    JobPosting public jobPosting;
    MockERC20 public paymentToken;

    address public admin = address(1);
    address public client = address(2);
    address public freelancer = address(3);
    address public escrowManager = address(4);

    uint256 public constant INITIAL_BALANCE = 1000 * 10**18;
    uint256 public constant JOB_ID = 1;
    uint256 public constant ESCROW_AMOUNT = 100 * 10**18;

    event FundsDeposited(uint256 indexed jobId, uint256 amount);
    event FundsReleased(uint256 indexed jobId, address indexed freelancer, uint256 amount);
    event FundsRefunded(uint256 indexed jobId, address indexed client, uint256 amount);
    event DisputeInitiated(uint256 indexed jobId);
    event DisputeResolved(uint256 indexed jobId, address winner, uint256 amount);

    function setUp() public {
        vm.startPrank(admin);
        paymentToken = new MockERC20();
        jobPosting = new JobPosting(address(paymentToken), address(0) );
        escrow = new Escrow(address(paymentToken), address(jobPosting));

        escrow.grantRole(escrow.ESCROW_MANAGER_ROLE(), escrowManager);
        vm.stopPrank();

        paymentToken.transfer(client, INITIAL_BALANCE);
        vm.prank(client);
        paymentToken.approve(address(escrow), type(uint256).max);
    }

    function testInitialBalance() public {
        assertEq(paymentToken.balanceOf(client), INITIAL_BALANCE);
    }

    function testCreateEscrow() public {
        vm.prank(escrowManager);
        escrow.createEscrow(JOB_ID, client, freelancer, ESCROW_AMOUNT);

        (uint256 balance, bool isReleased, address escrowClient, address escrowFreelancer, Escrow.EscrowStatus status, , ) = escrow.escrows(JOB_ID);

        assertEq(balance, ESCROW_AMOUNT);
        assertFalse(isReleased);
        assertEq(escrowClient, client);
        assertEq(escrowFreelancer, freelancer);
        assertEq(uint(status), uint(Escrow.EscrowStatus.Active));
    }

    function testCreateEscrowEmitsEvent() public {
        vm.prank(escrowManager);
        vm.expectEmit(true, false, false, true);
        emit FundsDeposited(JOB_ID, ESCROW_AMOUNT);
        escrow.createEscrow(JOB_ID, client, freelancer, ESCROW_AMOUNT);
    }

    function testCreateEscrowFailsForExistingJob() public {
        vm.startPrank(escrowManager);
        escrow.createEscrow(JOB_ID, client, freelancer, ESCROW_AMOUNT);
        
        vm.expectRevert("Escrow already exists for this job");
        escrow.createEscrow(JOB_ID, client, freelancer, ESCROW_AMOUNT);
        vm.stopPrank();
    }

    function testReleaseFunds() public {
        vm.prank(escrowManager);
        escrow.createEscrow(JOB_ID, client, freelancer, ESCROW_AMOUNT);

        vm.prank(client);
        escrow.releaseFunds(JOB_ID);

        (uint256 balance, bool isReleased, , , Escrow.EscrowStatus status, , ) = escrow.escrows(JOB_ID);

        assertEq(balance, 0);
        assertTrue(isReleased);
        assertEq(uint(status), uint(Escrow.EscrowStatus.Released));
        assertEq(paymentToken.balanceOf(freelancer), ESCROW_AMOUNT);
    }

    function testReleaseFundsEmitsEvent() public {
        vm.prank(escrowManager);
        escrow.createEscrow(JOB_ID, client, freelancer, ESCROW_AMOUNT);

        vm.prank(client);
        vm.expectEmit(true, true, false, true);
        emit FundsReleased(JOB_ID, freelancer, ESCROW_AMOUNT);
        escrow.releaseFunds(JOB_ID);
    }

    function testReleaseFundsFailsForNonClient() public {
        vm.prank(escrowManager);
        escrow.createEscrow(JOB_ID, client, freelancer, ESCROW_AMOUNT);

        vm.prank(freelancer);
        vm.expectRevert("Only client can release funds");
        escrow.releaseFunds(JOB_ID);
    }

    function testRefundClient() public {
        vm.prank(escrowManager);
        escrow.createEscrow(JOB_ID, client, freelancer, ESCROW_AMOUNT);

        vm.prank(escrowManager);
        escrow.refundClient(JOB_ID);

        (uint256 balance, , , , Escrow.EscrowStatus status, , ) = escrow.escrows(JOB_ID);

        assertEq(balance, 0);
        assertEq(uint(status), uint(Escrow.EscrowStatus.Refunded));
        assertEq(paymentToken.balanceOf(client), INITIAL_BALANCE);
    }

    function testRefundClientEmitsEvent() public {
        vm.prank(escrowManager);
        escrow.createEscrow(JOB_ID, client, freelancer, ESCROW_AMOUNT);

        vm.prank(escrowManager);
        vm.expectEmit(true, true, false, true);
        emit FundsRefunded(JOB_ID, client, ESCROW_AMOUNT);
        escrow.refundClient(JOB_ID);
    }

    function testInitiateDispute() public {
        vm.prank(escrowManager);
        escrow.createEscrow(JOB_ID, client, freelancer, ESCROW_AMOUNT);

        vm.prank(client);
        escrow.initiateDispute(JOB_ID);

        (, , , , Escrow.EscrowStatus status, , ) = escrow.escrows(JOB_ID);
        assertEq(uint(status), uint(Escrow.EscrowStatus.Disputed));
    }

    function testInitiateDisputeEmitsEvent() public {
        vm.prank(escrowManager);
        escrow.createEscrow(JOB_ID, client, freelancer, ESCROW_AMOUNT);

        vm.prank(client);
        vm.expectEmit(true, false, false, false);
        emit DisputeInitiated(JOB_ID);
        escrow.initiateDispute(JOB_ID);
    }

    function testResolveDispute() public {
        vm.prank(escrowManager);
        escrow.createEscrow(JOB_ID, client, freelancer, ESCROW_AMOUNT);

        vm.prank(client);
        escrow.initiateDispute(JOB_ID);

        vm.prank(escrowManager);
        escrow.resolveDispute(JOB_ID, freelancer);

        (uint256 balance, , , , Escrow.EscrowStatus status, , ) = escrow.escrows(JOB_ID);

        assertEq(balance, 0);
        assertEq(uint(status), uint(Escrow.EscrowStatus.Released));
        assertEq(paymentToken.balanceOf(freelancer), ESCROW_AMOUNT);
    }

    function testResolveDisputeEmitsEvent() public {
        vm.prank(escrowManager);
        escrow.createEscrow(JOB_ID, client, freelancer, ESCROW_AMOUNT);

        vm.prank(client);
        escrow.initiateDispute(JOB_ID);

        vm.prank(escrowManager);
        vm.expectEmit(true, true, false, true);
        emit DisputeResolved(JOB_ID, freelancer, ESCROW_AMOUNT);
        escrow.resolveDispute(JOB_ID, freelancer);
    }

    function testAddFunds() public {
        vm.prank(escrowManager);
        escrow.createEscrow(JOB_ID, client, freelancer, ESCROW_AMOUNT);

        uint256 additionalAmount = 50 * 10**18;
        vm.prank(client);
        escrow.addFunds(JOB_ID, additionalAmount);

        (uint256 balance, , , , , , ) = escrow.escrows(JOB_ID);
        assertEq(balance, ESCROW_AMOUNT + additionalAmount);
    }

    function testAddFundsEmitsEvent() public {
        vm.prank(escrowManager);
        escrow.createEscrow(JOB_ID, client, freelancer, ESCROW_AMOUNT);

        uint256 additionalAmount = 50 * 10**18;
        vm.prank(client);
        vm.expectEmit(true, false, false, true);
        emit FundsDeposited(JOB_ID, additionalAmount);
        escrow.addFunds(JOB_ID, additionalAmount);
    }

    function testPauseContract() public {
        vm.prank(admin);
        escrow.pauseContract();
        assertTrue(escrow.paused());
    }

    function testUnpauseContract() public {
        vm.startPrank(admin);
        escrow.pauseContract();
        escrow.unpauseContract();
        vm.stopPrank();
        assertFalse(escrow.paused());
    }

    function testFailWhenPaused() public {
        vm.prank(admin);
        escrow.pauseContract();

        vm.expectRevert("Pausable: paused");
        vm.prank(escrowManager);
        escrow.createEscrow(JOB_ID, client, freelancer, ESCROW_AMOUNT);
    }

    function testAccessControl() public {
        vm.expectRevert("AccessControl: account 0x0000000000000000000000000000000000000001 is missing role 0xaf290d8680820aad922855f39b306097b20e28774d6c1ad35a20325630c3a02c");
        vm.prank(address(1));
        escrow.createEscrow(JOB_ID, client, freelancer, ESCROW_AMOUNT);
    }
}