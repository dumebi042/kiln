# Finding: Calls-Loop in addValidators

## Severity

**Medium**

## Description

The [`addValidators()`](src/contracts/StakingContract.sol:530) function iterates over user-provided validator keys in an unbounded loop. For each key, it performs:

1. SHA256 precompile calls for public key root computation and duplicate detection
2. Storage writes for each validator's public key, signature, and operator index
3. Internal function calls to `_updateAvailableValidatorCount()`

The gas cost is approximately **118,000 gas per key** (measured via Foundry test with 10 keys). With a block gas limit of ~30M on Ethereum, approximately **250 keys** could cause the transaction to exceed the block gas limit and revert.

This is not a direct fund loss but represents a **griefing vector** and **progressive DoS risk**. An operator cannot be forced to add keys they don't want to, but legitimate bulk operations become increasingly expensive and could hit gas limits during high-demand periods.

Slither flags this as **`calls-loop`** (external precompile calls inside a loop). The finding is **CONFIRMED as a real vulnerability**.

## Impact

- **Progressive Gas Cost**: Adding validators costs ~118k gas per key. For a typical operator adding 1,000 validators, the transaction would cost ~118M gas — far exceeding the block gas limit.
- **Griefing**: While operators control their own key additions, the lack of an upper bound means that an operator managing many validators must split additions across multiple transactions, increasing complexity and cost.
- **Front-running Potential**: During periods of high demand, an operator adding a large batch of validators could have their transaction stuck or delayed.

## Proof of Concept

The Foundry test [`test_unbounded_gas_addValidators()`](test/StakingContractAudit.t.sol:407) confirms the gas scaling:

```
Gas used for 10 keys: 1,180,552
Avg gas per key: 118,055
```

The vulnerable loop is in [`addValidators()`](src/contracts/StakingContract.sol:530):

```solidity
for (uint256 i = 0; i < _validatorCount; i++) {
    bytes memory publicKey = BytesLib.slice(_publicKeys, i * PUBLIC_KEY_LENGTH, PUBLIC_KEY_LENGTH);
    bytes memory signature = BytesLib.slice(_signatures, i * SIGNATURE_LENGTH, SIGNATURE_LENGTH);

    // SHA256 precompile calls (external)
    bytes32 pubKeyRoot = sha256(abi.encodePacked(publicKey, bytes16(0)));

    // Storage reads/writes per iteration
    // ...
}
```

## Recommended Mitigation

1. **Enforce a maximum batch size**: Add `require(_validatorCount <= MAX_VALIDATORS_PER_BATCH, "Batch too large")` where `MAX_VALIDATORS_PER_BATCH` is set to a reasonable value (e.g., 50-100).
2. **Benchmark and document**: Even without a hard cap, document the gas-per-key cost and recommend batch sizes accordingly.
3. **Consider using a push-based pattern**: Allow operators to add validators incrementally and only validate+deposit at deposit time, splitting the computational cost across transactions.

## Status

Open
