# Finding: Balance Check After External Call in \_depositValidator

## Severity

**Low**

## Description

The [`_depositValidator()`](src/contracts/StakingContract.sol:859) function uses a balance-check pattern that computes a target balance **before** making an external call to the DepositContract, then checks the actual balance **after** the call returns:

```solidity
// Lines 879-890
uint256 targetBalance = address(this).balance - DEPOSIT_SIZE;

// External call to trusted DepositContract
IDepositContract(DEPOSIT_CONTRACT).deposit{value: DEPOSIT_SIZE}(
    publicKey, withdrawalCredentials, signature, depositDataRoot
);

// Balance check after external call
if (address(this).balance != targetBalance) {
    revert InvalidBalance(
        targetBalance,
        address(this).balance
    );
}
```

While this specific pattern is not directly exploitable (the DepositContract is a trusted protocol contract that does not call back), it violates the **checks-effects-interactions** pattern. A self-destruct forcing ETH into the contract between the subtraction and the check would cause a revert, making the deposit fail but not lose funds.

## Impact

- **Griefing**: A malicious actor could force ETH into the StakingContract (via `selfdestruct`) between the balance computation and the check, causing the transaction to revert. The 32 ETH sent to the DepositContract would not be recoverable by the StakingContract (it's locked in the Beacon DepositContract).
- **Fund Loss Risk**: Although the current implementation reverts on mismatch (safe), any future modification to this pattern that silently continues on mismatch could lead to actual fund loss.
- **Readability**: The pattern is fragile and confusing to auditors, increasing maintenance risk.

## Proof of Concept

The balance check pattern is at [`StakingContract.sol:879-890`](src/contracts/StakingContract.sol:879):

```solidity
// Compute expected balance BEFORE external call
uint256 targetBalance = address(this).balance - DEPOSIT_SIZE;

// External call
IDepositContract(DEPOSIT_CONTRACT).deposit{value: DEPOSIT_SIZE}(...);

// Check AFTER external call
if (address(this).balance != targetBalance) {
    revert InvalidBalance(targetBalance, address(this).balance);
}
```

A self-destruct forced ETH between the subtraction and check would cause:

```
targetBalance = currentBalance - 32 ETH
// selfdestruct forces +X ETH
// external deposit sends -32 ETH
actualBalance = currentBalance + X - 32 ETH  // != targetBalance (off by X)
// Reverts
```

## Recommended Mitigation

1. **Move the balance check before the external call**: Compute and compare targetBalance before making the deposit call:

   ```solidity
   uint256 balanceBefore = address(this).balance;
   IDepositContract(DEPOSIT_CONTRACT).deposit{value: DEPOSIT_SIZE}(...);
   if (address(this).balance != balanceBefore - DEPOSIT_SIZE) {
       revert InvalidBalance(...);
   }
   ```

   This is equivalent but more clearly communicates intent.

2. **Use a reentrancy guard**: Add a `nonReentrant` modifier to `receive()` and `deposit()` to prevent any reentrancy concerns.

3. **Use OpenZeppelin's `ReentrancyGuard`**: For defense-in-depth, inherit from OpenZeppelin's `ReentrancyGuard`.

## Status

Open
