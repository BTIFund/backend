// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title SolarCrowdfunding
 * @dev Simplified MVP for crowdfunding solar panel projects with IDRX token
 */
contract SolarCrowdfunding is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    // IDRX token interface
    IERC20 public idrxToken;

    // Constants
    uint256 public constant BASIS_POINTS = 10000; // 100% = 10000 basis points
    uint256 public constant CARBON_OFFSET_PER_KWH = 500000000000000000; // 0.5 * 10^18
    uint256 private constant MAX_TRANSACTIONS = 10;

    // Project status enum
    enum ProjectStatus {
        Funding,   // Project is in funding phase
        Active,    // Project is funded and producing energy
        Completed, // Project has completed its contract term
        Cancelled  // Project was cancelled before completion
    }

    // Project data
    struct Project {
        string name;                    // Project name
        string location;                // Project location
        uint256 fundingGoal;            // Total funding needed in IDRX
        uint256 fundingRaised;          // Total funding raised in IDRX
        uint256 expectedMonthlyReturn;  // Expected monthly return percentage (basis points)
        uint256 fundingDeadline;        // Deadline for funding
        address developer;              // Developer address
        ProjectStatus status;           // Project status
    }

    // Portofolio performance
    struct PortfolioPerformance {
        uint256 totalInvestment;
        uint256 totalReturns;
    }

    // Transaction
    struct Transaction {
        uint256 projectId;
        string transactionType;
        uint256 amount;
        uint256 timestamp;
    }

    // Investor data
    struct Investment {
        uint256 amount;          // Investment amount in IDRX
        uint256 claimedReturns;  // Returns already claimed in IDRX
        uint256 lastClaimDate;   // Last date when returns were claimed
    }

    // Storage
    Project[] public projects;
    mapping(uint256 => mapping(address => Investment)) public investments;
    mapping(address => bool) public isDeveloper;
    mapping(address => mapping(uint256 => PortfolioPerformance)) public monthlyPerformance;
    mapping(uint256 => mapping(uint256 => uint256)) public monthlyEnergyProduction; // projectId => monthId => kWh
    mapping(address => Transaction[]) private userTransactions;

    // Events
    event ProjectCreated(uint256 indexed projectId, address developer, string name, uint256 fundingGoal);
    event InvestmentMade(uint256 indexed projectId, address investor, uint256 amount);
    event ProjectFunded(uint256 indexed projectId, uint256 totalRaised);
    event ReturnsClaimed(uint256 indexed projectId, address investor, uint256 amount);
    event ProjectCompleted(uint256 indexed projectId);
    event ProjectCancelled(uint256 indexed projectId);
    event DeveloperAdded(address developer);
    event DeveloperRemoved(address developer);
    event MonthlyReturnsDistributed(uint256 indexed projectId, uint256 amount);
    event Transactions(address indexed user, uint256 indexed projectId, string transactionType, uint256 amount, uint256 timestamp);

    /**
     * @dev Constructor
     * @param _idrxTokenAddress Address of the IDRX token contract
     */
    constructor(address _idrxTokenAddress) Ownable(msg.sender) {
        require(_idrxTokenAddress != address(0), "Invalid IDRX token address");
        idrxToken = IERC20(_idrxTokenAddress);
        
        // Add contract deployer as developer
        isDeveloper[msg.sender] = true;
    }

    /**
     * @dev Add a developer
     * @param _developer Developer address
     */
    function addDeveloper(address _developer) external onlyOwner {
        isDeveloper[_developer] = true;
        emit DeveloperAdded(_developer);
    }

    /**
     * @dev Remove a developer
     * @param _developer Developer address
     */
    function removeDeveloper(address _developer) external onlyOwner {
        isDeveloper[_developer] = false;
        emit DeveloperRemoved(_developer);
    }

    /**
     * @dev Create a new solar project
     * @param _name Project name
     * @param _location Project location
     * @param _fundingGoal Total funding needed in IDRX
     * @param _expectedMonthlyReturn Expected monthly return percentage (basis points)
     * @param _fundingDurationDays Duration of funding period in days
     */
    function createProject(
        string memory _name,
        string memory _location,
        uint256 _fundingGoal,
        uint256 _expectedMonthlyReturn,
        uint256 _fundingDurationDays
    ) external {
        require(isDeveloper[msg.sender], "Only developers can create projects");
        require(_fundingGoal > 0, "Funding goal must be positive");
        require(_expectedMonthlyReturn > 0, "Return percentage must be positive");
        
        // Create new project
        Project memory newProject = Project({
            name: _name,
            location: _location,
            fundingGoal: _fundingGoal,
            fundingRaised: 0,
            expectedMonthlyReturn: _expectedMonthlyReturn,
            fundingDeadline: block.timestamp + (_fundingDurationDays * 1 days),
            developer: msg.sender,
            status: ProjectStatus.Funding
        });

        uint256 projectId = projects.length;
        projects.push(newProject);
        emit ProjectCreated(projectId, msg.sender, _name, _fundingGoal);
    }

    /**
    * @dev Mendapatkan semua ID proyek yang ada
    * @return projectIds Daftar ID proyek yang ada di dalam kontrak
    */
    function getAllProjectIds() external view returns (uint256[] memory) {
        uint256[] memory projectIds = new uint256[](projects.length);
        for (uint256 i = 0; i < projects.length; i++) {
            projectIds[i] = i;
        }
        return projectIds;
    }

    /**
     * @dev Invest in a project using IDRX
     * @param _projectId Project ID
     * @param _amount Amount of IDRX to invest
     */
    function invest(uint256 _projectId, uint256 _amount) external nonReentrant {
        require(_projectId < projects.length, "Project does not exist");
        Project storage project = projects[_projectId];
        
        require(project.status == ProjectStatus.Funding, "Project is not in funding phase");
        require(block.timestamp < project.fundingDeadline, "Funding deadline has passed");
        require(_amount > 0, "Investment amount must be positive");
        
        uint256 remainingFunding = project.fundingGoal - project.fundingRaised;
        uint256 investmentAmount = (_amount > remainingFunding) ? remainingFunding : _amount;
        
        // Transfer IDRX from investor to contract
        idrxToken.safeTransferFrom(msg.sender, address(this), investmentAmount);
        
        // Update project funding
        project.fundingRaised += investmentAmount;
        
        // Update investor's investment
        Investment storage investment = investments[_projectId][msg.sender];
        investment.amount += investmentAmount;
        investment.lastClaimDate = block.timestamp;
        _updatePortfolioPerformance(msg.sender, investmentAmount, 0);
        _addTransaction(msg.sender, _projectId, "Investment", investmentAmount);
        
        emit InvestmentMade(_projectId, msg.sender, investmentAmount);
        emit Transactions(msg.sender, _projectId, "Investment", investmentAmount, block.timestamp);
        
        // If funding goal is reached, update project status to Active
        if (project.fundingRaised >= project.fundingGoal) {
            project.status = ProjectStatus.Active;
            emit ProjectFunded(_projectId, project.fundingRaised);
        }
        
        // Refund excess investment if any
        if (_amount > investmentAmount) {
            idrxToken.safeTransfer(msg.sender, _amount - investmentAmount);
        }
    }

    /**
    * @dev Mendapatkan semua ID proyek yang sudah mendapatkan investasi
    * Fungsi ini return ID project yang memiliki dana yang terkumpul (fundingRaised > 0)
    * @return investedProjectIds Daftar ID proyek yang sudah melakukan investasi
    */
    function getInvestedProjectIds() external view returns (uint256[] memory) {
        uint256 investedCount = 0;

        // Hitung jumlah proyek yang sudah mendapatkan investasi
        for (uint256 i = 0; i < projects.length; i++) {
            Project storage project = projects[i];
            
            // Periksa apakah ada investasi pada proyek ini
            if (project.fundingRaised > 0) {
                investedCount++;
            }
        }

        uint256[] memory investedProjectIds = new uint256[](investedCount);
        uint256 index = 0;

        // Masukkan ID proyek yang sudah diinvestasikan ke dalam array
        for (uint256 i = 0; i < projects.length; i++) {
            Project storage project = projects[i];
            
            if (project.fundingRaised > 0) {
                investedProjectIds[index] = i;
                index++;
            }
        }

        return investedProjectIds;
    }

    /**
     * @dev Distribute monthly returns to project investors
     * @param _projectId Project ID
     */
    function distributeMonthlyReturns(uint256 _projectId) external onlyOwner {
        require(_projectId < projects.length, "Project does not exist");
        Project storage project = projects[_projectId];
        
        require(project.status == ProjectStatus.Active, "Project is not active");
        
        // Transfer IDRX funds to contract for distribution if needed
        // This is simplified - in a real implementation, you would calculate 
        // based on actual energy production data from oracles
        uint256 monthlyReturnsAmount = project.fundingRaised * project.expectedMonthlyReturn / BASIS_POINTS;
        
        // Emit event for UI tracking
        emit MonthlyReturnsDistributed(_projectId, monthlyReturnsAmount);
    }

    /**
     * @dev Claim returns for investor
     * @param _projectId Project ID
     */
    function claimReturns(uint256 _projectId) external nonReentrant {
        require(_projectId < projects.length, "Project does not exist");
        Project storage project = projects[_projectId];
        Investment storage investment = investments[_projectId][msg.sender];
        
        require(investment.amount > 0, "No investment found");
        require(project.status == ProjectStatus.Active, "Project is not active");
        
        // Calculate claimable return (simplified)
        // In a full implementation, this would account for actual energy data
        uint256 monthsSinceLastClaim = (block.timestamp - investment.lastClaimDate) / 30 days;
        if (monthsSinceLastClaim == 0) return;
        
        uint256 investorShare = investment.amount * BASIS_POINTS / project.fundingRaised;
        uint256 monthlyReturnsAmount = project.fundingRaised * project.expectedMonthlyReturn / BASIS_POINTS;
        uint256 claimableAmount = monthlyReturnsAmount * investorShare * monthsSinceLastClaim / BASIS_POINTS;
        
        // Check if contract has enough balance
        uint256 idrxBalance = idrxToken.balanceOf(address(this));
        claimableAmount = claimableAmount > idrxBalance ? idrxBalance : claimableAmount;
        
        require(claimableAmount > 0, "No returns to claim");
        
        // Update investment record
        investment.claimedReturns += claimableAmount;
        investment.lastClaimDate = block.timestamp;
        _updatePortfolioPerformance(msg.sender, 0, claimableAmount);
        _addTransaction(msg.sender, _projectId, "Claim Returns", claimableAmount);
        
        // Transfer IDRX returns to investor
        idrxToken.safeTransfer(msg.sender, claimableAmount);
        
        emit ReturnsClaimed(_projectId, msg.sender, claimableAmount);
        emit Transactions(msg.sender, _projectId, "Claim Returns", claimableAmount, block.timestamp);
    }

    /**
     * @dev Cancel project if funding deadline has passed and goal not reached
     * @param _projectId Project ID
     */
    function cancelProject(uint256 _projectId) external {
        require(_projectId < projects.length, "Project does not exist");
        Project storage project = projects[_projectId];
        
        require(project.status == ProjectStatus.Funding, "Project is not in funding phase");
        require(block.timestamp > project.fundingDeadline, "Funding deadline has not passed yet");
        require(project.fundingRaised < project.fundingGoal, "Funding goal reached, cannot cancel");
        
        project.status = ProjectStatus.Cancelled;
        emit ProjectCancelled(_projectId);
    }

    /**
     * @dev Refund investment if project is cancelled
     * @param _projectId Project ID
     */
    function refundInvestment(uint256 _projectId) external nonReentrant {
        require(_projectId < projects.length, "Project does not exist");
        Project storage project = projects[_projectId];
        Investment storage investment = investments[_projectId][msg.sender];
        
        require(project.status == ProjectStatus.Cancelled, "Project is not cancelled");
        require(investment.amount > 0, "No investment found");
        
        uint256 refundAmount = investment.amount;

        // Check the contract's balance to ensure it has enough IDRX to refund
        uint256 contractBalance = idrxToken.balanceOf(address(this));
        require(contractBalance >= refundAmount, "Insufficient balance in contract");

        // Reset investment record
        investment.amount = 0;
        investment.claimedReturns = 0;
        
        // Transfer IDRX refund to investor
        idrxToken.safeTransfer(msg.sender, refundAmount);
    }


    /**
     * @dev Complete a project (only owner can call)
     * @param _projectId Project ID
     */
    function completeProject(uint256 _projectId) external onlyOwner {
        require(_projectId < projects.length, "Project does not exist");
        Project storage project = projects[_projectId];
        
        require(project.status == ProjectStatus.Active, "Project is not active");
        
        project.status = ProjectStatus.Completed;
        emit ProjectCompleted(_projectId);
    }

    /**
     * @dev Get project details
     * @param _projectId Project ID
     * @return Project details
     */
    function getProjectDetails(uint256 _projectId) external view returns (Project memory) {
        require(_projectId < projects.length, "Project does not exist");
        return projects[_projectId];
    }

    /**
     * @dev Get investor details for a project
     * @param _projectId Project ID
     * @param _investor Investor address
     * @return Investment details
     */
    function getInvestmentDetails(uint256 _projectId, address _investor) external view returns (Investment memory) {
        require(_projectId < projects.length, "Project does not exist");
        return investments[_projectId][_investor];
    }

    /**
     * @dev Get number of projects
     * @return Number of projects
     */
    function getProjectCount() external view returns (uint256) {
        return projects.length;
    }

    /**
     * @dev Get user's monthly returns across all projects
     * @param _user Address of the user
     * @return Monthly returns in IDRX
     */
    function getUserMonthlyReturns(address _user) external view returns (uint256) {
        uint256 totalMonthlyReturns = 0;
        for (uint256 i = 0; i < projects.length; i++) {
            if (projects[i].status == ProjectStatus.Active) {
                Investment storage investment = investments[i][_user];
                uint256 investorShare = investment.amount * BASIS_POINTS / projects[i].fundingRaised;
                uint256 monthlyReturnsAmount = projects[i].fundingRaised * projects[i].expectedMonthlyReturn / BASIS_POINTS;
                totalMonthlyReturns += monthlyReturnsAmount * investorShare / BASIS_POINTS;
            }
        }
        return totalMonthlyReturns;
    }

    /**
     * @dev Get user's annual returns across all projects
     * @param _user Address of the user
     * @return Annual returns in IDRX
     */
    function getUserAnnualReturns(address _user) external view returns (uint256) {
        uint256 monthlyReturns = this.getUserMonthlyReturns(_user);
        return monthlyReturns * 12;
    }

    /**
     * @dev Get user's portfolio performance for a specific month
     * @param _user Address of the user
     * @param _year Year of the performance
     * @param _month Month of the performance (1-12)
     * @return PortfolioPerformance struct containing total investment and returns
     */
    function getUserPortfolioPerformance(address _user, uint256 _year, uint256 _month) external view returns (PortfolioPerformance memory) {
        require(_month >= 1 && _month <= 12, "Invalid month");
        uint256 monthId = _year * 12 + _month;
        return monthlyPerformance[_user][monthId];
    }

    /**
     * @dev Update user's portfolio performance
     * @param _user Address of the user
     * @param _investment Amount invested
     * @param _returns Amount of returns
     */
    function _updatePortfolioPerformance(address _user, uint256 _investment, uint256 _returns) internal {
        uint256 currentMonth = (block.timestamp / 30 days) + 1;
        uint256 currentYear = 1970 + (block.timestamp / 365 days);
        uint256 monthId = currentYear * 12 + currentMonth;

        PortfolioPerformance storage performance = monthlyPerformance[_user][monthId];
        performance.totalInvestment += _investment;
        performance.totalReturns += _returns;
    }

    /**
     * @dev Get user's transaction history
     * @param _user Address of the user
     * @param _fromTimestamp Start timestamp for history
     * @param _toTimestamp End timestamp for history
     * @return Array of Transaction events
     */
    function getUserTransactionHistory(address _user, uint256 _fromTimestamp, uint256 _toTimestamp) external view returns (Transaction[] memory) {
        // Note: This function is a placeholder and won't work as is.
        // Implementing this correctly would require additional storage and indexing,
        // which is beyond the scope of a simple contract update.
        // In a real-world scenario, you'd typically use events and external indexing (e.g., The Graph) for this.
    }

    /**
     * @dev Set monthly energy production for a project
     * @param _projectId Project ID
     * @param _year Year of production
     * @param _month Month of production (1-12)
     * @param _kWh Energy produced in kWh
     */
    function setMonthlyEnergyProduction(uint256 _projectId, uint256 _year, uint256 _month, uint256 _kWh) external onlyOwner {
        require(_projectId < projects.length, "Project does not exist");
        require(_month >= 1 && _month <= 12, "Invalid month");
        uint256 monthId = _year * 12 + _month;
        monthlyEnergyProduction[_projectId][monthId] = _kWh;
    }

    /**
     * @dev Calculate carbon offset for a user across all projects
     * @param _user Address of the user
     * @param _year Year of calculation
     * @param _month Month of calculation (1-12)
     * @return Carbon offset in kg (scaled by 10^18)
     */
    function getUserCarbonOffset(address _user, uint256 _year, uint256 _month) external view returns (uint256) {
        require(_month >= 1 && _month <= 12, "Invalid month");
        uint256 monthId = _year * 12 + _month;
        uint256 totalCarbonOffset = 0;

        for (uint256 i = 0; i < projects.length; i++) {
            if (projects[i].status == ProjectStatus.Active) {
                Investment storage investment = investments[i][_user];
                if (investment.amount > 0) {
                    uint256 investorShare = investment.amount * 1e18 / projects[i].fundingRaised;
                    uint256 projectEnergyProduction = monthlyEnergyProduction[i][monthId];
                    uint256 userEnergyShare = projectEnergyProduction * investorShare / 1e18;
                    totalCarbonOffset += userEnergyShare * CARBON_OFFSET_PER_KWH / 1e18;
                }
            }
        }

        return totalCarbonOffset;
    }

    function _addTransaction(address user, uint256 projectId, string memory transactionType, uint256 amount) internal {
        Transaction memory newTransaction = Transaction(projectId, transactionType, amount, block.timestamp);
        
        if (userTransactions[user].length >= MAX_TRANSACTIONS) {
            // Remove the oldest transaction
            for (uint i = 0; i < MAX_TRANSACTIONS - 1; i++) {
                userTransactions[user][i] = userTransactions[user][i + 1];
            }
            userTransactions[user][MAX_TRANSACTIONS - 1] = newTransaction;
        } else {
            userTransactions[user].push(newTransaction);
        }
    }

    function getUserTransactionHistory(address _user) external view returns (Transaction[] memory) {
        return userTransactions[_user];
    }

    /**
     * @dev Add IDRX tokens to contract (for monthly returns)
     * @param _amount Amount of IDRX to add
     */
    function addIDRXFunds(uint256 _amount) external {
        require(_amount > 0, "Amount must be positive");
        idrxToken.safeTransferFrom(msg.sender, address(this), _amount);
    }

    /**
     * @dev Withdraw IDRX tokens (for emergency use)
     * @param _amount Amount of IDRX to withdraw
     */
    function withdrawEmergencyIDRX(uint256 _amount) external onlyOwner {
        uint256 idrxBalance = idrxToken.balanceOf(address(this));
        require(_amount <= idrxBalance, "Insufficient IDRX balance");
        idrxToken.safeTransfer(owner(), _amount);
    }
}