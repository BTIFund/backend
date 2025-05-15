// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/SolarCrowdfunding.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20WithMint is ERC20 {
    address public admin;

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        admin = msg.sender;
    }

    // Fungsi untuk mint token, hanya admin yang dapat melakukannya
    function adminMint(address to, uint256 amount) external {
        require(msg.sender == admin, "Only admin can mint");
        _mint(to, amount);
    }
}

contract SolarCrowdfundingTest is Test {
    SolarCrowdfunding public crowdfunding;
    ERC20WithMint public idrxToken;

    address public deployer = address(0x1);
    address public alice = address(0x2);
    address public bob = address(0x3);
    
    uint256 public constant INITIAL_IDRX_SUPPLY = 1000000 * 10**18; // 1M IDRX

    event ProjectCreated(uint256 indexed projectId, address developer, string name, uint256 fundingGoal);
    event InvestmentMade(uint256 indexed projectId, address investor, uint256 amount);
    event ProjectFunded(uint256 indexed projectId, uint256 totalRaised);
    event ReturnsClaimed(uint256 indexed projectId, address investor, uint256 amount);

    function setUp() public {
        vm.startPrank(deployer);

        // Deploy IDRX token with minting capability
        idrxToken = new ERC20WithMint("IDRX Token", "IDRX");
        idrxToken.adminMint(deployer, INITIAL_IDRX_SUPPLY);
        
        // Deploy SolarCrowdfunding contract
        crowdfunding = new SolarCrowdfunding(address(idrxToken));
        
        // Add Alice and Bob as investors (you can add their token balances if needed)
        vm.stopPrank();
    }
    
// ===================== Test Project Creation =====================

    function testCreateProject() public {
        vm.startPrank(deployer);
        
        uint256 fundingGoal = 10000 * 10**18;
        uint256 expectedReturn = 500; // 5% expected monthly return
        uint256 fundingDuration = 30; // 30 days
        
        crowdfunding.createProject("Solar Panel Project", "Location 1", fundingGoal, expectedReturn, fundingDuration);
        
        uint256 projectCount = crowdfunding.getProjectCount();
        assertEq(projectCount, 1);
        
        (string memory name, string memory location, uint256 fundingRaised, uint256 fundingGoalStored, uint256 expectedReturnStored, , , , ) = crowdfunding.getProjectDetails(0);
        
        assertEq(name, "Solar Panel Project");
        assertEq(location, "Location 1");
        assertEq(fundingGoalStored, fundingGoal);
        assertEq(expectedReturnStored, expectedReturn);
        
        vm.stopPrank();
    }

    // ===================== Test Investment =====================

    function testInvestInProject() public {
        vm.startPrank(alice);
        
        uint256 fundingGoal = 10000 * 10**18;
        uint256 expectedReturn = 500; // 5% expected monthly return
        uint256 fundingDuration = 30; // 30 days
        
        crowdfunding.createProject("Solar Panel Project", "Location 1", fundingGoal, expectedReturn, fundingDuration);
        
        uint256 amountToInvest = 1000 * 10**18;
        
        // Approve and invest in project
        idrxToken.approve(address(crowdfunding), amountToInvest);
        crowdfunding.invest(0, amountToInvest);
        
        (uint256 investedAmount, uint256 claimedReturns, uint256 lastClaimDate) = crowdfunding.getInvestmentDetails(0, alice);
        
        assertEq(investedAmount, amountToInvest);
        
        vm.stopPrank();
    }

    // ===================== Test Return Claim =====================

    function testClaimReturns() public {
        vm.startPrank(alice);
        
        uint256 fundingGoal = 10000 * 10**18;
        uint256 expectedReturn = 500; // 5% expected monthly return
        uint256 fundingDuration = 30; // 30 days
        
        crowdfunding.createProject("Solar Panel Project", "Location 1", fundingGoal, expectedReturn, fundingDuration);
        
        uint256 amountToInvest = 1000 * 10**18;
        
        // Approve and invest in project
        idrxToken.approve(address(crowdfunding), amountToInvest);
        crowdfunding.invest(0, amountToInvest);
        
        // Simulate time passage (30 days)
        vm.warp(block.timestamp + 30 days);
        
        // Claim returns
        crowdfunding.claimReturns(0);
        
        (uint256 claimedReturns, , ) = crowdfunding.getInvestmentDetails(0, alice);
        
        uint256 expectedClaimAmount = (amountToInvest * expectedReturn) / 10000; // 5% return
        assertEq(claimedReturns, expectedClaimAmount);
        
        vm.stopPrank();
    }

    // ===================== Test Project Completion =====================

    function testCompleteProject() public {
        vm.startPrank(deployer);
        
        uint256 fundingGoal = 10000 * 10**18;
        uint256 expectedReturn = 500; // 5% expected monthly return
        uint256 fundingDuration = 30; // 30 days
        
        crowdfunding.createProject("Solar Panel Project", "Location 1", fundingGoal, expectedReturn, fundingDuration);
        
        // Simulate funding completion
        uint256 amountToInvest = 10000 * 10**18;
        idrxToken.approve(address(crowdfunding), amountToInvest);
        crowdfunding.invest(0, amountToInvest);
        
        // Complete the project
        crowdfunding.completeProject(0);
        
        ( , , , , , , , , uint256 status) = crowdfunding.getProjectDetails(0);
        
        assertEq(status, uint256(SolarCrowdfunding.ProjectStatus.Completed));
        
        vm.stopPrank();
    }

    // ===================== Test Refund Investment =====================

    function testRefundInvestment() public {
        vm.startPrank(alice);
        
        uint256 fundingGoal = 10000 * 10**18;
        uint256 expectedReturn = 500; // 5% expected monthly return
        uint256 fundingDuration = 30; // 30 days
        
        crowdfunding.createProject("Solar Panel Project", "Location 1", fundingGoal, expectedReturn, fundingDuration);
        
        uint256 amountToInvest = 1000 * 10**18;
        idrxToken.approve(address(crowdfunding), amountToInvest);
        crowdfunding.invest(0, amountToInvest);
        
        // Simulate project cancellation
        vm.warp(block.timestamp + 31 days); // Past funding deadline
        crowdfunding.cancelProject(0);
        
        // Refund investment
        crowdfunding.refundInvestment(0);
        
        uint256 aliceBalance = idrxToken.balanceOf(alice);
        assertEq(aliceBalance, amountToInvest);
        
        vm.stopPrank();
    }
}
