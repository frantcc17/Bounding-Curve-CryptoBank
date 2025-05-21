// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/math/Math.sol";

/**
* @title CryptoBankBondingCurveV2
* @notice Decentralized banking protocol with dynamic interest rates and collateralized loans
* @dev Features include:
* - ETH deposits/withdrawals with capacity limits
* - Collateralized loans with time-based interest
* - Bonding curve interest rate mechanism
* - Automated liquidations for overdue loans
* - System-wide risk controls
*/
contract CryptoBankBondingCurve {
    address public admin;          // Contract administrator address
    uint256 public totalDeposits; // Total amount of ETH deposited by users (excluding loaned funds)
    uint256 public totalLoans;   // Total principal amount of all active loans
    uint256 public constant MAX_CAPACITY = 100 ether;   // Maximum ETH capacity of the bank (100 ETH)
    uint256 public constant MIN_INTEREST_BPS = 100;    // Minimum annual interest rate (1% = 100 basis points)
    uint256 public constant MAX_INTEREST_BPS = 2000;  // Maximum annual interest rate (20% = 2000 basis points)
    uint256 public constant MAX_LTV_RATIO = 5000;    // Loan-to-Value ratio (50% = 5000 basis points)
    uint256 public constant MAX_LOAN_RATIO = 6000;  // Maximum loans as percentage of total capacity (60%)
    bool private locked;                           // Reentrancy protection lock
    mapping(address => uint256) public userBalances;  // Tracks ETH deposits per user
    
    // Loan structure containing loan details
    struct Loan {
        uint256 amount;         // Loan principal
        uint256 interestRate;   // Annual interest rate in basis points
        uint256 timestamp;      // Loan start time
        uint256 collateral;     // ETH collateral amount
        bool active;           // Loan status
    }
    
    // Tracks active loans per user
    mapping(address => Loan) public loans;

    // Events
    event Deposit(address indexed user, uint256 amount);
    event Withdrawal(address indexed user, uint256 amount);
    event LoanIssued(address indexed user, uint256 amount, uint256 collateral);
    event LoanRepaid(address indexed user, uint256 amount, uint256 interest);
    event CollateralSeized(address indexed user, uint256 amount);

    /**
    * @dev Initializes contract with deployer as admin
    */
    constructor() {
        admin = msg.sender;
    }

    /**
    * @dev Prevents reentrancy attacks
    * Modifier applied to state-changing functions
    */
    modifier noReentrancy() {
        require(!locked, "Reentrant call");
        locked = true;
        _;
        locked = false;
    }

    // --- Core Banking Functions --- //
    
    /**
    * @notice Deposits ETH into the bank
    * @dev Funds are added to user balance and total deposits
    * Requirements:
    * - Deposit amount > 0
    * - Total deposits <= MAX_CAPACITY
    */
    function deposit() external payable {
        require(msg.value > 0, "Deposit must be > 0");
        require(totalDeposits + msg.value <= MAX_CAPACITY, "Exceeds capacity");
        
        userBalances[msg.sender] += msg.value;
        totalDeposits += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    /**
    * @notice Withdraws ETH from user's balance
    * @param amount ETH amount to withdraw
    * @dev Uses reentrancy protection
    * Requirements:
    * - Sufficient user balance
    */
    function withdraw(uint256 amount) external noReentrancy {
        require(userBalances[msg.sender] >= amount, "Insufficient balance");
        
        userBalances[msg.sender] -= amount;
        totalDeposits -= amount;

        (bool sent, ) = msg.sender.call{value: amount}("");
        require(sent, "Withdraw failed");
        emit Withdrawal(msg.sender, amount);
    }

    // --- Loan Management Functions --- //
    
    /**
    * @notice Requests a collateralized loan
    * @param amount ETH amount to borrow
    * @dev Loan terms:
    * - 50% LTV ratio (2x collateral required)
    * - Dynamic interest rate based on bank utilization
    * - System-wide loan limit (60% of capacity)
    * Requirements:
    * - Valid loan amount
    * - Sufficient collateral
    * - No existing active loan
    * - Within system loan limits
    */
    function requestLoan(uint256 amount) external payable noReentrancy {
        require(amount > 0, "Invalid loan amount");
        require(amount <= totalDeposits, "Insufficient liquidity");
        require(!loans[msg.sender].active, "Existing loan active");
        
        // Calculate required collateral (2x loan amount)
        uint256 requiredCollateral = (amount * 1e4) / MAX_LTV_RATIO;
        require(msg.value >= requiredCollateral, "Insufficient collateral");
        
        // Check system-wide loan limit
        uint256 newTotalLoans = totalLoans + amount;
        require(newTotalLoans <= (MAX_CAPACITY * MAX_LOAN_RATIO) / 1e4, "Loan capacity exceeded");

        // Calculate current interest rate using bonding curve
        uint256 utilization = Math.min(
            (totalDeposits * 1e18) / MAX_CAPACITY, 
            1e18 // Cap utilization at 100%
        );
        uint256 interestBps = MIN_INTEREST_BPS + 
            ((MAX_INTEREST_BPS - MIN_INTEREST_BPS) * utilization) / 1e18;

        // Update system state
        totalDeposits -= amount;
        totalLoans += amount;

        // Create loan record
        loans[msg.sender] = Loan({
            amount: amount,
            interestRate: interestBps,
            timestamp: block.timestamp,
            collateral: msg.value,
            active: true
        });

        // Transfer loan amount to borrower
        (bool sent, ) = msg.sender.call{value: amount}("");
        require(sent, "Loan transfer failed");
        emit LoanIssued(msg.sender, amount, msg.value);
    }

    /**
    * @notice Repays an active loan including accrued interest
    * @dev Handles:
    * - Interest payment to admin
    * - Collateral return to borrower
    * - Overpayment refunds
    * Requirements:
    * - Active loan exists
    * - Payment >= principal + interest
    */
    function repayLoan() external payable noReentrancy {
        Loan storage loan = loans[msg.sender];
        require(loan.active, "No active loan");

        // Calculate accrued interest
        uint256 duration = block.timestamp - loan.timestamp;
        uint256 interest = (loan.amount * loan.interestRate * duration) / 
            (365 days * 10000);
        uint256 totalRepayment = loan.amount + interest;

        require(msg.value >= totalRepayment, "Insufficient repayment");
        
        // Update system state
        totalDeposits += loan.amount;
        totalLoans -= loan.amount;
        loan.active = false;

        // Distribute interest to admin
        (bool success, ) = payable(admin).call{value: interest}("");
        require(success, "Interest transfer failed");
        
        // Return collateral to borrower
        (bool collateralReturned, ) = msg.sender.call{
            value: loan.collateral
        }("");
        require(collateralReturned, "Collateral return failed");

        // Refund any overpayment
        if (msg.value > totalRepayment) {
            (bool refunded, ) = msg.sender.call{
                value: msg.value - totalRepayment
            }("");
            require(refunded, "Refund failed");
        }
        emit LoanRepaid(msg.sender, loan.amount, interest);
    }

    // --- Risk Management Functions --- //
    
    /**
    * @notice Liquidates overdue loans
    * @param user Address of defaulting borrower
    * @dev:
    * - Seizes 50% of collateral
    * - Returns remaining 50% to borrower
    * - Closes loan
    * Requirements:
    * - Loan is overdue by >30 days
    */
    function liquidate(address user) external noReentrancy {
        Loan memory loan = loans[user];
        require(loan.active, "No active loan");
        require(block.timestamp > loan.timestamp + 30 days, "Not overdue");
        
        // Calculate collateral distribution
        uint256 seizeAmount = loan.collateral / 2;
        
        // Transfer seized collateral to admin
        (bool success, ) = admin.call{value: seizeAmount}("");
        require(success, "Liquidation failed");
        
        // Return remaining collateral to borrower
        (success, ) = user.call{value: loan.collateral - seizeAmount}("");
        require(success, "Collateral return failed");
        
        // Update loan state
        loans[user].active = false;
        totalLoans -= loan.amount;
        emit CollateralSeized(user, seizeAmount);
    }

    // --- View Functions --- //
    
    /**
    * @notice Returns current interest rate in basis points
    * @dev Rate calculated based on current bank utilization
    */
    function getCurrentInterestBps() public view returns (uint256) {
        uint256 utilization = Math.min(
            (totalDeposits * 1e18) / MAX_CAPACITY, 
            1e18
        );
        return MIN_INTEREST_BPS + 
            ((MAX_INTEREST_BPS - MIN_INTEREST_BPS) * utilization) / 1e18;
    }

    /**
    * @notice Returns loan details for specified user
    * @param user Borrower address
    * @return Loan struct with all loan parameters
    */
    function getLoanDetails(address user) external view returns (Loan memory) {
        return loans[user];
    }
}
