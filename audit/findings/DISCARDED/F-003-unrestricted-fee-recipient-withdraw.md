# Finding: Unrestricted FeeRecipient.withdraw()

## Severity

**Medium**

## Description

The [`FeeRecipient.withdraw()`](src/contracts/FeeRecipient.sol:42) function has **no access control**. Any external caller can invoke `withdraw()` on any FeeRecipient clone, triggering the fee dispatch logic in the associated fee dispatcher contract.

```solidity
// FeeRecipient.sol, lines 42-49
function withdraw() external {
    IFeeDispatcher _dispatcher = dispatcher;
    dispatcher = IFeeDispatcher(address(0));
    _dispatcher.dispatch{value: address(this).balance}(publicKeyRoot);
}
```

The StakingContract itself calls `withdraw()` on the FeeRecipient clones during `batchWithdrawELFee()` and `batchWithdrawCLFee()`. However, nothing prevents any third party from calling `withdraw()` directly on any deployed FeeRecipient at any time.

While the [`AuthorizedFeeRecipient`](src/contracts/AuthorizedFeeRecipient.sol:42) variant does restrict `withdraw()` to the staking contract, the StakingContract currently deploys `FeeRecipient` (not `AuthorizedFeeRecipient`) for validators.

## Impact

- **Premature Fee Extraction**: A third party could trigger fee withdrawal from a validator's FeeRecipient at an inopportune time, potentially disrupting the operator's or withdrawer's preferred withdrawal scheduling.
- **Loss of Control**: Validators/operators lose granular control over when fees are dispatched. The dispatcher computes fees based on the balance at time of dispatch, so premature dispatching could result in less favorable fee timing.
- **Gas Griefing**: A malicious actor could trigger withdrawals at high gas prices, forcing the fee recipient to pay excessive gas relative to the fee amount being extracted (especially for small balances).

## Proof of Concept

Anyone can call `withdraw()` on any deployed FeeRecipient:

```solidity
// Attacker calls withdraw on a targeted validator's fee recipient
address feeRecipient = staking.getOperatorFeeRecipient(pubKeyRoot);
IFeeRecipient(feeRecipient).withdraw(); // Succeeds for any caller
```

Contrast with `AuthorizedFeeRecipient` which restricts this:

```solidity
// AuthorizedFeeRecipient.sol, lines 42-47
function withdraw() external {
    require(msg.sender == stakingContract, "Unauthorized");
    // ...
}
```

## Recommended Mitigation

1. **Use `AuthorizedFeeRecipient`**: Replace `FeeRecipient` with `AuthorizedFeeRecipient` in the StakingContract's deployment logic. Only the StakingContract itself should be able to trigger withdrawals, maintaining control over fee dispatch timing.
2. **Add access control to FeeRecipient**: If the non-authorized variant is needed for other purposes, add a `onlyStakingContract` modifier or equivalent access control check.

## Status

Open
