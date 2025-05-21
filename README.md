# 🏦 CryptoBankBondingCurveV2

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

**Decentralized ETH Bank with Dynamic Interest Rates, Collateralized Loans, and Liquidation Mechanism**

> “Where DeFi meets sound banking principles... with math.”

---

## ✨ Features

- 🔐 **Deposits & Withdrawals:** ETH-based banking system with a 100 ETH max capacity.
- 📈 **Bonding Curve Loans:** Dynamic interest rates from 1% to 20%, based on utilization.
- 💰 **Collateralized Borrowing:** Borrow ETH with 50% LTV ratio (2x collateral required).
- 🚨 **Liquidation:** Auto-seize collateral on overdue loans (>30 days).
- ⛓️ **No Reentrancy:** Manually protected, gas-efficient, non-reentrant architecture.
- 📦 **Auditable Structure:** Full visibility of loan terms, rates, and durations.

---

## 🛠 Tech Stack

- **Solidity 0.8.24**
- **OpenZeppelin Math Library**
- No external dependencies (besides Math)
- Optimized for EVM execution

---

## 🧩 Smart Contract Overview

| 🧱 Component     | 📋 Description                                                              |
|------------------|----------------------------------------------------------------------------|
| `deposit()`       | Add ETH to the bank (capped at 100 ETH).                                   |
| `withdraw()`      | Withdraw user ETH balance.                                                  |
| `requestLoan()`   | Request a loan with 2x collateral, dynamic interest.                        |
| `repayLoan()`     | Repay loan + interest, reclaim collateral.                                 |
| `liquidate()`     | Admin-triggered liquidation if loan overdue 30+ days.                      |
| `getCurrentInterestBps()` | View function to fetch current dynamic interest rate.              |
| `getLoanDetails()`        | Returns all data on user’s active loan (if any).                   |

---

## 📈 Interest Rate Model

Dynamic rate calculated with this bonding curve formula:

Where:

- `Utilization = totalDeposits / MAX_CAPACITY`  
- Range: 1% (low usage) to 20% (high usage)

---

## 🧠 How It Works

### 📤 Deposits
- Users can deposit ETH (up to 100 ETH total).
- Each deposit updates the internal balance & emits events.

### 💳 Borrowing
- Must deposit **2x** the loan amount as collateral.
- Can borrow if system-wide loans < 60% of capacity.
- Borrower gets ETH, contract logs loan terms.

### 💸 Repayment
- Repay principal + time-based interest.
- Get full collateral back.
- Admin receives interest.

### ⚠️ Liquidation
- If not repaid in 30 days, admin can seize 50% of collateral.
- Remaining 50% returned to borrower.
- Loan is marked closed.

---

## ✅ Security Notes

- ✅ Manual reentrancy lock via `locked` flag
- ✅ Validations for all state changes
- ✅ Fallback-proof ETH transfer logic
- ✅ Immutable loan terms

---

## 📜 License

```solidity
// SPDX-License-Identifier: MIT

----
### 🧪 Test Ideas
Deposit and withdraw ETH (check event logs).
Issue and repay loan within deadline.
Trigger liquidation after 30+ days.
Overpay loan & validate refund logic.
----
📚 Developer Notes
All balances and logic are in native ETH (no ERC20).
All interest rates in BPS (Basis Points): 1% = 100.
Time logic uses block.timestamp and days.


