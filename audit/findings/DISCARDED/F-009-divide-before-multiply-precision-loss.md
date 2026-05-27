# Finding: Precision Loss in Cascading Fee Calculation

## Severity

**Medium** — Systematic precision loss that accumulates across fee tiers

## Description

Both [`ConsensusLayerFeeDispatcher.dispatch()`](src/contracts/ConsensusLayerFeeDispatcher.sol:89) and [`ExecutionLayerFeeDispatcher.dispatch()`](src/contracts/ExecutionLayerFeeDispatcher.sol:70) compute fees using a **cascading division pattern**: `operatorFee` is calculated as a percentage of `globalFee`, which itself has already been truncated by integer division.

```solidity
// Line 89: globalFee = truncation #1
uint256 globalFee = (nonExemptBalance * stakingContract.getGlobalFee()) / BASIS_POINTS;

// Line 90: operatorFee = globalFee (already truncated) * operatorFeeBPS / 10000 = truncation #2
uint256 operatorFee = (globalFee * stakingContract.getOperatorFee()) / BASIS_POINTS;
```

Each `(X * BPS) / 10000` operation truncates toward zero (Solidity integer division). When `operatorFee` is computed from the already-truncated `globalFee`, the precision loss compounds:

- **First truncation**: `globalFee = (balance * globalFeeBPS) / 10000` — loses up to 0.01% of `balance`
- **Second truncation**: `operatorFee = (globalFee * operatorFeeBPS) / 10000` — loses up to 0.01% of `globalFee`

The lost precision is always **borne by the treasury**, because the withdrawer receives `balance - globalFee` (net of the truncated global fee), operator receives `operatorFee` (truncated from truncated globalFee), and treasury receives `globalFee - operatorFee` (the remainder after both truncations). The treasury is the residual claimant and thus absorbs all rounding error.

## Impact

- **Systematic Under-collection**: Every dispatch loses a small amount of treasury fees to integer truncation. While each individual loss is small (fractions of a wei), aggregated across thousands of validators and frequent dispatches, the cumulative loss is material.
- **Risk of Zero Fees on Dust**: With small balances and high BPS values, `globalFee` can round to zero, leaving fees entirely uncollected. For example, a balance of 2 wei with `globalFeeBPS = 3333` gives `(2 * 3333) / 10000 = 0`.
- **Non-deterministic Loss**: The precision loss depends on the balance and BPS values, making it hard to predict or account for off-chain.

## Proof of Concept

### Fuzz test — all ETH accounted for despite precision loss

The fuzz test confirms that while all ETH is distributed (no funds lost to the contract), the split between fee recipients is affected by rounding:

```solidity
function test_precision_loss(
    uint256 balance,
    uint256 globalFeeBPS,
    uint256 operatorFeeBPS
) public {
    globalFeeBPS = bound(globalFeeBPS, 1, 5000);
    operatorFeeBPS = bound(operatorFeeBPS, 1, 10000);
    balance = bound(balance, 1 wei, 1000 ether);

    mockStaking.setGlobalFee(globalFeeBPS);
    mockStaking.setOperatorFee(operatorFeeBPS);

    vm.deal(address(clDispatcher), balance);
    clDispatcher.dispatch(PUBKEY_ROOT_1);

    // All ETH accounted for — no funds stuck in dispatcher
    uint256 totalDistributed = user.balance + treasury.balance + operatorFeeRecipient.balance;
    assertEq(totalDistributed, balance, "All ETH accounted for despite precision loss");
}
```

### Dust edge case — zero fees on small balances

```solidity
function test_precision_loss_dust_edge_case() public {
    mockStaking.setGlobalFee(3333); // 33.33%
    mockStaking.setOperatorFee(5000); // 50% of global = 16.665%

    // 2 wei: globalFee = 2 * 3333 / 10000 = 0 — no fees collected
    vm.deal(address(clDispatcher), 2 wei);
    clDispatcher.dispatch(PUBKEY_ROOT_1);
    assertEq(treasury.balance, 0, "Treasury got 0 due to truncation");
    assertEq(operatorFeeRecipient.balance, 0, "Operator got 0 due to truncation");
    assertEq(user.balance, 2 wei, "User gets all due to fee truncation");
}
```

## Recommended Mitigation

1. **Use a higher precision intermediate**: Track fees in a higher-precision unit (e.g., basis points of wei, or use a scaling factor like `1e18`) and divide only at the final step:

   ```solidity
   // Compute globalFee with higher precision
   uint256 globalFeeScaled = nonExemptBalance * stakingContract.getGlobalFee();
   uint256 operatorFeeScaled = globalFeeScaled * stakingContract.getOperatorFee();
   uint256 globalFee = globalFeeScaled / BASIS_POINTS;
   uint256 operatorFee = operatorFeeScaled / (BASIS_POINTS * BASIS_POINTS);
   ```

   This ensures `operatorFee` is computed from the exact `globalFee` value before truncation.

2. **Account for remainder**: If the above is too large for the `uint256` range (unlikely for practical values), compute the remainder and distribute it to one of the parties (e.g., add to treasury):

   ```solidity
   uint256 globalFee = (nonExemptBalance * globalFeeBPS) / BASIS_POINTS;
   uint256 operatorFee = (nonExemptBalance * globalFeeBPS * operatorFeeBPS) / (BASIS_POINTS * BASIS_POINTS);
   // operatorFee is now the exact fraction of the original balance
   ```

## Status

Open
