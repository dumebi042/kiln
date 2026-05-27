# Finding: Centralization Risks in Admin Powers

## Severity

**Informational**

## Description

The StakingContract grants significant powers to a single admin address, creating centralization risks. The admin can:

1. **Deactivate operators and redirect their fees** ([`deactivateOperator()`](src/contracts/StakingContract.sol:482)): Admin can set a `_temporaryFeeRecipient` for any operator, redirecting all future fee rewards to an arbitrary address. This can be done without the operator's consent or knowledge.

2. **Set fee parameters unilaterally**:
   - [`setOperatorFee()`](src/contracts/StakingContract.sol:506): Adjusts operator commission rate (up to `operatorCommissionLimit`)
   - [`setGlobalFee()`](src/contracts/StakingContract.sol:516): Adjusts global protocol fee (up to `globalCommissionLimit`)
   - Both are set in `initialize_2()` with limits that can only be set once

3. **Set treasury address** ([`setTreasury()`](src/contracts/StakingContract.sol:214)): Admin can redirect protocol fees to any address.

4. **Enable/disable deposits** ([`setDepositsStopped()`](src/contracts/StakingContract.sol:741)): Admin can pause all deposits, halting the protocol's core functionality.

5. **Set operator validator limits** ([`setOperatorLimit()`](src/contracts/StakingContract.sol:455)): Admin controls how many validators each operator can register.

These powers are concentrated in a single EOA or multisig. Slither flags various access control patterns as `missing-check` or `unused-return`, but these are by design — the centralization is intentional but represents a trust assumption.

## Impact

- **Single Point of Compromise**: If the admin key is compromised, an attacker can redirect all operator fees to themselves, change the treasury, and halt deposits.
- **Operator Trust Dependency**: Operators must trust that the admin will not abuse their powers. This is a significant trust assumption, especially for a non-custodial staking protocol.
- **No Timelock**: There is no timelock or two-step process for sensitive operations like fee redirection or treasury changes.

## Proof of Concept

The admin can redirect all fees from any operator:

```solidity
// StakingContract.sol, lines 482-491
function deactivateOperator(uint256 _operatorIndex, address _temporaryFeeRecipient)
    external onlyAdmin
{
    StakingContractStorageLib.OperatorInfo storage operator =
        StakingContractStorageLib._getOperatorInfo(operators[_operatorIndex]);
    // Sets _temporaryFeeRecipient — all future fees go here
    // ...
}
```

No timelock or operator consent is required.

## Recommended Mitigation

1. **Use a multisig for the admin address**: Deploy with a multisig wallet (e.g., Gnosis Safe) requiring M-of-N signatures for admin operations.
2. **Add a timelock**: Implement a timelock delay (e.g., 48-72 hours) for sensitive operations like `deactivateOperator()`, `setTreasury()`, and fee parameter changes.
3. **Two-step ownership transfer**: If `acceptOwnership()` (line 372) is intended for admin transfer, ensure it follows a two-step pattern (propose + accept) to prevent accidental ownership loss.
4. **Consider a DAO/governance module**: For a fully decentralized protocol, migrate admin powers to a governance contract over time.

## Status

Open
