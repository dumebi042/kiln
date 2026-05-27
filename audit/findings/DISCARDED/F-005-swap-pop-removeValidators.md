# Finding: Swap-and-Pop State Inconsistency in removeValidators

## Severity

**Low**

## Description

The [`removeValidators()`](src/contracts/StakingContract.sol:587) function uses a **swap-and-pop** pattern to delete validator entries from the operator's dynamic arrays. When a non-last element is removed, the last element is moved into the vacated position:

```solidity
// Lines 610-613
operator.publicKeys[_indexes[i]] = operator.publicKeys[keysCount - 1 - j];
operator.signatures[_indexes[i]] = operator.signatures[keysCount - 1 - j];
```

This changes the mapping between **validator index** and **validator key/signature**. An operator who tracks validators by index could be affected when indexes are reshuffled after removal.

Additionally, the function requires indexes to be provided in **strictly decreasing order** (`_indexes[i] > _indexes[i+1]`), but does not validate that indexes are within bounds of the operator's current key count. An operator could provide out-of-bounds indexes (though they would access stale/uninitialized storage).

## Impact

- **State Confusion**: Operators relying on index→key mapping for off-chain tracking may find their records out of sync after a removal that triggers a swap.
- **Off-by-One Errors**: If an operator computes indexes based on pre-removal state and then performs multiple removal transactions, the swap-and-pop can cause unintended validators to be removed.
- **Operator Error**: The decreasing-order requirement is non-obvious and error-prone. An operator providing indexes in ascending order would trigger a revert instead of a graceful error.

## Proof of Concept

The swap-and-pop at [`StakingContract.sol:610-613`](src/contracts/StakingContract.sol:610):

```solidity
// Remove from publicKeys array (swap-and-pop)
operator.publicKeys[_indexes[i]] = operator.publicKeys[keysCount - 1 - j];
operator.publicKeys.pop();

// Remove from signatures array (swap-and-pop)
operator.signatures[_indexes[i]] = operator.signatures[keysCount - 1 - j];
operator.signatures.pop();
```

Example scenario:

- Operator has keys at indexes [0:A, 1:B, 2:C, 3:D]
- Operator removes index 1 (B)
- Index 3 (D) is swapped into index 1
- New state: [0:A, 1:D, 2:C]
- If operator now removes index 2 (C) in a second transaction, index tracking works fine
- But if operator had computed indexes expecting [A, B, C, D], the swap changes which key is at which index

## Recommended Mitigation

1. **Document the swap-and-pop behavior clearly** in the function's NatSpec, explaining that indexes will be reshuffled and that operators must provide indexes in strictly decreasing order.
2. **Consider using a bitmap or mapping-based approach** instead of dynamic arrays for validator tracking, avoiding the swap-and-pop pattern entirely.
3. **Add index bounds validation**: Check that `_indexes[i] < keysCount` before accessing arrays.
4. **Emit detailed events**: Include the old and new index positions when a swap occurs, so off-chain indexers can track changes.

## Status

Open
