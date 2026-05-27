# Finding: Calls-Loop in Batch Withdraw Functions

## Severity

**Medium**

## Description

The functions [`batchWithdrawELFee()`](src/contracts/StakingContract.sol:646), [`batchWithdrawCLFee()`](src/contracts/StakingContract.sol:664), and [`batchWithdraw()`](src/contracts/StakingContract.sol:681) iterate over user-provided public keys in an unbounded loop. Each iteration calls [`_deployAndWithdraw()`](src/contracts/StakingContract.sol:938) which:

1. Deploys a new deterministic FeeRecipient clone via the OpenZeppelin `Clones` library (costs ~9k gas for CREATE2)
2. Calls `withdraw()` on the deployed clone, which makes an external call to the fee dispatcher (another ~40k+ gas)

There is no maximum iteration limit. The gas cost scales linearly with the number of keys passed. With ~118k gas consumed per key in the withdrawal path (confirmed by Foundry test), submitting 250+ keys could exceed the block gas limit (~30M), causing the transaction to revert and potentially griefing legitimate users.

This is flagged by **Slither as `calls-loop`** (9 stack traces identified). The finding is **CONFIRMED as a real vulnerability**.

## Impact

- **DoS / Griefing**: An operator or withdrawer could maliciously call `batchWithdrawELFee()` with an excessive number of keys, causing the transaction to run out of gas and fail. While the caller pays for gas, this can block timely withdrawals for other validators.
- **Progressive Gas Cost**: Each additional key adds ~118k gas. There is no upper bound enforcement within the contract.
- **Economic Inefficiency**: Even for legitimate use cases, batching many withdrawals becomes increasingly expensive, disincentivizing proper batch processing.

## Proof of Concept

The vulnerability is demonstrated by the Foundry test [`test_unbounded_gas_loop()`](test/StakingContractAudit.t.sol:376) which measures gas for a single-key `batchWithdrawELFee()` call at **498,793 gas** (including FeeRecipient clone deployment). For N keys, the gas cost is approximately:

```
Gas(N) ≈ N × 118,000 + 380,000 (fixed overhead)
```

A 30-key batch would cost ~3.9M gas, and a 250-key batch would exceed ~30M (block gas limit).

```solidity
// In StakingContract.sol, line 646-658
function batchWithdrawELFee(bytes calldata _publicKeys) external {
    for (uint256 i = 0; i < _publicKeys.length; i += PUBLIC_KEY_LENGTH) {
        bytes memory publicKey = BytesLib.slice(_publicKeys, i, PUBLIC_KEY_LENGTH);
        _deployAndWithdraw(msg.sender, publicKey, 1); // EL prefix
    }
}
```

## Recommended Mitigation

1. **Enforce a maximum batch size**: Add a constant `MAX_BATCH_SIZE` (e.g., 50-100) and check `_publicKeys.length / PUBLIC_KEY_LENGTH <= MAX_BATCH_SIZE` at the start of each batch function.
2. **Pull-based pattern**: Instead of pushing fees in a batch, allow individual withdrawals only, requiring users to call `withdrawELFee()` for each key. This shifts the gas cost to the caller and prevents griefing.
3. **Proportional fee**: If batching must be supported, consider splitting the work across multiple transactions using an incremental pattern.

## Status

Open
