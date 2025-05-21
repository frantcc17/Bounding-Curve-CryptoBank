// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import "../src/CryptoBankV2.sol";
import "forge-std/Test.sol";

contract CryptoBankV2Test is Test {
    CryptoBankBondingCurve public bank;
    address public admin = address(1);
    address public user1 = address(2);
    address public user2 = address(3);
    
    uint256 public constant MAX_CAPACITY = 100 ether;
    uint256 public constant MAX_LOAN_RATIO = 6000; // 60%

    function setUp() public {
        vm.deal(admin, 100 ether);
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        
        vm.prank(admin);
        bank = new CryptoBankBondingCurve();
    }

    function calculateCollateral(uint256 loanAmount) internal view returns (uint256) {
        return (loanAmount * 1e4) / bank.MAX_LTV_RATIO();
    }

    // Añadir función helper para depósitos
    function _depositFunds(uint256 amount) internal {
        vm.prank(admin);
        bank.deposit{value: amount}();
    }

    // Tests actualizados con depósitos iniciales

    function test_RequestLoanWithCollateral() public {
        uint256 loanAmount = 10 ether;
        uint256 collateral = calculateCollateral(loanAmount);
        
        _depositFunds(loanAmount); // Depósito inicial
        
        vm.prank(user1);
        bank.requestLoan{value: collateral}(loanAmount);
    
        CryptoBankBondingCurve.Loan memory loan = bank.getLoanDetails(user1);
        assertTrue(loan.active);
        assertEq(loan.amount, loanAmount);
    }

    function test_RequestLoanRevertIfInsufficientCollateral() public {
        uint256 loanAmount = 10 ether;
        _depositFunds(loanAmount); // Depósito inicial
        
        uint256 insufficientCollateral = calculateCollateral(loanAmount) - 1 wei;

        vm.expectRevert("Insufficient collateral");
        vm.prank(user1);
        bank.requestLoan{value: insufficientCollateral}(loanAmount);
    }

    function test_RepayLoanWithInterest() public {
    uint256 loanAmount = 5 ether;
    uint256 collateral = calculateCollateral(loanAmount);
    
    _depositFunds(loanAmount);
    
    vm.prank(user1);
    bank.requestLoan{value: collateral}(loanAmount);
    
    // Obtener tasa de interés del préstamo
    CryptoBankBondingCurve.Loan memory loan = bank.getLoanDetails(user1);
    uint256 interestRate = loan.interestRate;
    
    vm.warp(block.timestamp + 30 days);
    
    // Calcular con la tasa real del préstamo
    uint256 expectedInterest = (loanAmount * interestRate * 30 days) / (365 days * 10000);
    uint256 repayment = loanAmount + expectedInterest;
    
    vm.prank(user1);
    bank.repayLoan{value: repayment}();
    
    assertFalse(bank.getLoanDetails(user1).active);
    assertEq(bank.totalLoans(), 0);
}
    function test_LiquidateOverdueLoan() public {
        uint256 loanAmount = 10 ether;
        uint256 collateral = calculateCollateral(loanAmount);
        
        _depositFunds(loanAmount); // Depósito inicial
        
        vm.prank(user1);
        bank.requestLoan{value: collateral}(loanAmount);
        
        vm.warp(block.timestamp + 31 days);
        
        vm.prank(admin);
        bank.liquidate(user1);
        
        CryptoBankBondingCurve.Loan memory loan = bank.getLoanDetails(user1);
        assertFalse(loan.active);
        assertEq(bank.totalLoans(), 0);
    }

    function test_InterestCalculation() public {
        uint256 loanAmount = 10 ether;
        uint256 collateral = calculateCollateral(loanAmount);
        
        _depositFunds(loanAmount); // Depósito inicial
        
        vm.prank(user1);
        bank.requestLoan{value: collateral}(loanAmount);
    
        vm.warp(block.timestamp + 15 days);
    
        CryptoBankBondingCurve.Loan memory loan = bank.getLoanDetails(user1);
        uint256 expectedInterest = (loanAmount * loan.interestRate * 15 days) / (365 days * 10000);
        
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit CryptoBankBondingCurve.LoanRepaid(user1, loanAmount, expectedInterest);
        bank.repayLoan{value: loanAmount + expectedInterest}();
    }

    function test_CollateralReturnAfterRepayment() public {
    uint256 loanAmount = 2 ether;
    uint256 collateral = calculateCollateral(loanAmount);
    
    _depositFunds(loanAmount);
    
    uint256 initialBalance = user1.balance;

    vm.prank(user1);
    bank.requestLoan{value: collateral}(loanAmount);
    
    // Calcular interés real en lugar de usar valor fijo
    vm.warp(block.timestamp + 1 days);
    CryptoBankBondingCurve.Loan memory loan = bank.getLoanDetails(user1);
    uint256 interest = (loanAmount * loan.interestRate * 1 days) / (365 days * 10000);
    
    vm.prank(user1);
    bank.repayLoan{value: loanAmount + interest}();
    
    // Balance final = inicial - colateral - interés + colateral devuelto
    assertEq(user1.balance, initialBalance - interest);
}
}
