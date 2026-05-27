# Finding: Reentrancy via receive() on Deposit

## Severity

**Informational**

## Description

The [`receive()`](src/contracts/StakingContract.sol:141) function calls [`_deposit()`](src/contracts/StakingContract.sol:898), which makes an external call to the Ethereum DepositContract at [`_depositValidator()`](src/contracts/StakingContract.sol:875):

```solidity
// StakingContract.sol, line 141-143
receive() external payable {
    _deposit();
}
```

This violates the **checks-effects-interactions** pattern. An external call (`DepositContract.deposit()`) is made inside a value receipt flow (`receive()`). While the current DepositContract is the canonical Ethereum beacon chain deposit contract (which does not call back), the pattern is fragile.

The Foundry test [`test_reentrancy_on_receive()`](test/StakingContractAudit.t.sol:179) confirms that with the trusted DepositContract, reentrancy is not exploitable — only 1 deposit (32 ETH) goes through as expected.

Slither flags this as **`reentrancy-events`** (events emitted after external calls), specifically in [`_depositValidatorsOfOperator()`](src/contracts/StakingContract.sol:827) where `Deposit()` and `ValidatorDeposit()` events are emitted after the external `DepositContract.deposit()` call.

## Impact

- **Low/Informational**: Currently not exploitable because the DepositContract is a trusted protocol contract with no callback mechanism.
- **Fragile Pattern**: If the protocol is upgraded to use a different deposit contract or if the deposit contract's behavior changes, this could become a reentrancy vector.
- **Defense in Depth**: Even trusted external calls should be guarded to protect against edge cases and future changes.

## Proof of Concept

The reentrancy path:

```
receive() → _deposit() → _depositOnOneOperator() → _depositValidatorsOfOperator()
    → _depositValidator() → DepositContract.deposit()  // External call
    → emit Deposit()  // Event AFTER external call
    → emit ValidatorDeposit()  // Event AFTER external call
```

The Foundry test confirms no reentrancy is possible through the current path:

```solidity
// test_reentrancy_on_receive()
attackerContract.attack{value: 64 ether}();
// Only 32 ETH deposited = 1 validator funded
(, , , , uint256 funded, , ) = staking.getOperator(0);
assertEq(funded, 1, "Only 1 deposit went through - no reentrancy");
```

## Recommended Mitigation

1. **Apply a reentrancy guard**: Use OpenZeppelin's `ReentrancyGuard` on `receive()` and `deposit()` functions for defense-in-depth.
2. **Follow checks-effects-interactions**: Move event emissions before external calls in `_depositValidatorsOfOperator()`.
3. **Consider removing `receive()`**: Require explicit `deposit()` calls instead of accepting raw ETH, making the call flow explicit.

## Status

Open
