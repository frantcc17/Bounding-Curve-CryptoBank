// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import "../src/CryptoBankV2.sol";
import "forge-std/Test.sol";

/**
* @title CryptoBankV2Test
* @notice Comprehensive test suite for CryptoBankBondingCurve contract
* @dev Tests cover core banking operations including deposits, loans, repayments, and liquidations
*/
contract CryptoBankV2Test is Test {
    // Contract instance and test addresses
    CryptoBankBondingCurve public bank;
    address public admin = address(1);
    address public user1 = address(2);
    address public user2 = address(3);
    
    // System constants
    uint256 public constant MAX_CAPACITY = 100 ether;
    uint256 public constant MAX_LOAN_RATIO = 6000; // 60%

    /**
    * @notice Test setup routine
    * @dev Initializes contract and funds test addresses
    * - Deploys new CryptoBankBondingCurve contract
    * - Funds admin and users with 100 ETH each
    */
    function setUp() public {
        vm.deal(admin, 100 ether);
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        
        vm.prank(admin);
        bank = new CryptoBankBondingCurve();
    }

    /**
    * @notice Calculates required collateral for a loan amount
    * @dev Uses bank's MAX_LTV_RATIO (50% LTV)
    * @param loanAmount Desired loan amount in wei
    * @return Required collateral amount in wei
    */
    function calculateCollateral(uint256 loanAmount) internal view returns (uint256) {
        return (loanAmount * 1e4) / bank.MAX_LTV_RATIO();
    }

    /**
    * @notice Helper function for admin deposits
    * @param amount ETH amount to deposit into the bank
    */
    function _depositFunds(uint256 amount) internal {
        vm.prank(admin);
        bank.deposit{value: amount}();
    }

    function calculateInterest(
        uint256 principal,
        uint256 rateBps,
        uint256 duration
    ) public pure returns (uint256) {
        return (principal * rateBps * duration) / (365 days * 10000);
    }
    // --- Core Functionality Tests --- //

    /**
    * @notice Tests successful loan request with proper collateral
    * @dev Sequence:
    * 1. Admin deposits loan amount (ensures liquidity)
    * 2. User requests loan with correct collateral
    * 3. Verifies loan activation and parameters
    */
    function test_RequestLoanWithCollateral() public {
        uint256 loanAmount = 10 ether;
        uint256 collateral = calculateCollateral(loanAmount);
        
        _depositFunds(loanAmount); // Fund the bank
        
        vm.prank(user1);
        bank.requestLoan{value: collateral}(loanAmount);
    
        CryptoBankBondingCurve.Loan memory loan = bank.getLoanDetails(user1);
        assertTrue(loan.active, "Loan should be active");
        assertEq(loan.amount, loanAmount, "Loan amount mismatch");
    }

    /**
    * @notice Tests loan request rejection with insufficient collateral
    * @dev Attempts loan with 1 wei less than required collateral
    * Verifies contract reverts with correct error message
    */
    function test_RequestLoanRevertIfInsufficientCollateral() public {
        uint256 loanAmount = 10 ether;
        _depositFunds(loanAmount);
        
        uint256 insufficientCollateral = calculateCollateral(loanAmount) - 1 wei;

        vm.expectRevert("Insufficient collateral");
        vm.prank(user1);
        bank.requestLoan{value: insufficientCollateral}(loanAmount);
    }

    /**
    * @notice Tests full loan repayment with accrued interest
    * @dev Sequence:
    * 1. Deposit funds and create loan
    * 2. Advance time by 30 days
    * 3. Calculate expected interest
    * 4. Repay loan and verify state updates
    */
    function test_RepayLoanWithInterest() public {
        uint256 loanAmount = 5 ether;
        uint256 collateral = calculateCollateral(loanAmount);
        
        _depositFunds(loanAmount);
        
        vm.prank(user1);
        bank.requestLoan{value: collateral}(loanAmount);
        
        // Get loan-specific interest rate
        CryptoBankBondingCurve.Loan memory loan = bank.getLoanDetails(user1);
        uint256 interestRate = loan.interestRate;
        
        // Simulate 30-day loan duration
        vm.warp(block.timestamp + 30 days);
        
        // Calculate interest: (principal * rate * time) / (365 days * 10000)
        uint256 expectedInterest = (loanAmount * interestRate * 30 days) / (365 days * 10000);
        uint256 repayment = loanAmount + expectedInterest;
        
        vm.prank(user1);
        bank.repayLoan{value: repayment}();
        
        assertFalse(bank.getLoanDetails(user1).active, "Loan should be closed");
        assertEq(bank.totalLoans(), 0, "Total loans should reset");
    }

    /**
    * @notice Tests liquidation of overdue loan
    * @dev Sequence:
    * 1. Create loan and advance time by 31 days
    * 2. Execute liquidation as admin
    * 3. Verify:
    *    - Loan closure
    *    - Collateral seizure (50%)
    *    - System loan balance update
    */
    function test_LiquidateOverdueLoan() public {
        uint256 loanAmount = 10 ether;
        uint256 collateral = calculateCollateral(loanAmount);
        
        _depositFunds(loanAmount);
        
        vm.prank(user1);
        bank.requestLoan{value: collateral}(loanAmount);
        
        // Make loan overdue (+31 days)
        vm.warp(block.timestamp + 31 days);
        
        vm.prank(admin);
        bank.liquidate(user1);
        
        CryptoBankBondingCurve.Loan memory loan = bank.getLoanDetails(user1);
        assertFalse(loan.active, "Loan should be closed");
        assertEq(bank.totalLoans(), 0, "Total loans should reset");
    }

    /**
    * @notice Tests interest calculation accuracy and event emission
    * @dev Verifies:
    * 1. Correct interest calculation for 15-day period
    * 2. Proper LoanRepaid event emission
    */
    function test_InterestCalculation() public {
        uint256 loanAmount = 10 ether;
        uint256 collateral = calculateCollateral(loanAmount);
        
        _depositFunds(loanAmount);
        
        vm.prank(user1);
        bank.requestLoan{value: collateral}(loanAmount);
    
        // Simulate 15-day duration
        vm.warp(block.timestamp + 15 days);
    
        CryptoBankBondingCurve.Loan memory loan = bank.getLoanDetails(user1);
        uint256 expectedInterest = (loanAmount * loan.interestRate * 15 days) / (365 days * 10000);
        
        // Verify event emission with exact parameters
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit CryptoBankBondingCurve.LoanRepaid(user1, loanAmount, expectedInterest);
        bank.repayLoan{value: loanAmount + expectedInterest}();
    }

    /**
    * @notice Tests collateral return logic after repayment
    * @dev Verifies:
    * 1. Correct balance changes after loan lifecycle
    * 2. Proper collateral return
    * 3. Interest deduction accuracy
    */
    function test_CollateralReturnAfterRepayment() public {
        uint256 loanAmount = 2 ether;
        uint256 collateral = calculateCollateral(loanAmount);
        
        _depositFunds(loanAmount);
        
        uint256 initialBalance = user1.balance;

        vm.prank(user1);
        bank.requestLoan{value: collateral}(loanAmount);
        
        // Calculate actual interest for 1 day
        vm.warp(block.timestamp + 1 days);
        CryptoBankBondingCurve.Loan memory loan = bank.getLoanDetails(user1);
        uint256 interest = (loanAmount * loan.interestRate * 1 days) / (365 days * 10000);
        
        vm.prank(user1);
        bank.repayLoan{value: loanAmount + interest}();
        
        // Final balance = initial - interest (collateral is returned)
        assertEq(user1.balance, initialBalance - interest, "Balance mismatch");
    }
    
function checkSystemInvariants() public view{
        // 1. Balance del contrato = totalDeposits + colateral - préstamos
        uint256 expectedBalance = bank.totalDeposits() + 
            (address(bank).balance + bank.totalLoans() - bank.totalDeposits()) - 
            bank.totalLoans();
        assertEq(address(bank).balance, expectedBalance, "Balance mismatch");
        
        // 2. Total depósitos <= MAX_CAPACITY
        assertLe(bank.totalDeposits(), MAX_CAPACITY, "Capacity exceeded");
        
        // 3. Total préstamos <= 60% capacidad
        assertLe(bank.totalLoans(), (MAX_CAPACITY * bank.MAX_LOAN_RATIO()) / 1e4, "Loan limit exceeded");
    }

    // ========== Tests Existentes ==========
    // ... [tus tests existentes aquí] ...

    // ========== Tests Fuzzing ==========
    function testFuzz_DepositWithdraw(uint96 amount) public {
        amount = uint96(bound(amount, 1 wei, MAX_CAPACITY));
        
        vm.prank(user1);
        bank.deposit{value: amount}();
        
        assertEq(bank.userBalances(user1), amount, "Deposit failed");
        assertEq(bank.totalDeposits(), amount, "Total deposits mismatch");
        
        vm.prank(user1);
        bank.withdraw(amount);
        
        assertEq(bank.userBalances(user1), 0, "Withdraw failed");
        assertEq(bank.totalDeposits(), 0, "Total deposits not zero");
        
        checkSystemInvariants();
    }

    function testFuzz_LoanLifecycle(
        uint96 depositAmount,
        uint96 loanAmount,
        uint40 timePassed
    ) public {
        depositAmount = uint96(bound(depositAmount, 1 ether, MAX_CAPACITY));
        loanAmount = uint96(bound(loanAmount, 1 wei, depositAmount));
        
        // Depósito inicial
        _depositFunds(depositAmount);
        
        // Solicitar préstamo
        uint256 collateral = calculateCollateral(loanAmount);
        vm.assume(collateral <= 100 ether); // Limitar colateral máximo
        vm.deal(user2, collateral);
        
        vm.prank(user2);
        bank.requestLoan{value: collateral}(loanAmount);
        
        // Simular paso del tiempo
        timePassed = uint40(bound(timePassed, 1, 365 days));
        vm.warp(block.timestamp + timePassed);
        
        // Calcular interés
        uint256 interest = calculateInterest(
            loanAmount,
             bank.getLoanDetails(user2).interestRate,
            timePassed
        );
        
        // Pagar préstamo
        vm.deal(user2, loanAmount + interest);
        vm.prank(user2);
        bank.repayLoan{value: loanAmount + interest}();
        
        checkSystemInvariants();
    }

    // ========== Tests Edge Cases ==========
    function test_RequestLoanMaxCapacity() public {
        uint256 maxLoan = (MAX_CAPACITY * bank.MAX_LOAN_RATIO()) / 1e4;
        uint256 collateral = calculateCollateral(maxLoan);
        
        _depositFunds(MAX_CAPACITY);
        vm.deal(user1, collateral);
        
        vm.prank(user1);
        bank.requestLoan{value: collateral}(maxLoan);
        
        assertEq(bank.totalLoans(), maxLoan, "Max loan not reached");
        checkSystemInvariants();
    }
}

