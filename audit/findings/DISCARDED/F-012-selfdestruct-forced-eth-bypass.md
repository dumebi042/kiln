# Finding: Self-Destruct Forced ETH Bypasses receive()/fallback() Revert

## Severity

**Low** — Griefing vector, no fund loss path identified

## Description

Both [`ConsensusLayerFeeDispatcher`](src/contracts/ConsensusLayerFeeDispatcher.sol:135) and [`ExecutionLayerFeeDispatcher`](src/contracts/ExecutionLayerFeeDispatcher.sol:108) implement `receive()` and `fallback()` functions that **revert all direct ETH transfers**:

```solidity
// ConsensusLayerFeeDispatcher.sol, lines 135-142
receive() external payable {
    revert CannotReceiveETH();
}

fallback() external payable {
    revert CannotReceiveETH();
}
```

This is intended to prevent ETH from being sent to the dispatcher outside of the `dispatch()` function. However, the **`selfdestruct` opcode** bypasses both `receive()` and `fallback()`. When a contract self-destructs to the dispatcher's address, the forced ETH transfer does NOT trigger `receive()` or `fallback()` — the ETH is deposited directly into the dispatcher's balance.

The dispatcher's `dispatch()` function checks `balance == 0` to prevent zero-balance dispatches, but any ETH forced in via `selfdestruct` means `balance > 0` and the dispatch proceeds, distributing the forced ETH through the normal fee calculation pipeline.

## Impact

- **Griefing**: A malicious actor can force ETH into the dispatcher at any time. The forced ETH is then distributed according to the normal fee schedule when the next `dispatch()` is called. This is a nuisance but not a fund loss — the forced ETH goes to the intended recipients (withdrawer, treasury, operator).
- **No Fund Loss Path**: The `selfdestruct` bypass does not allow fund extraction or theft. The forced ETH is processed through the same fee logic as legitimate dispatches.
- **Gas Cost Barrier**: Deploying a self-destruct contract and funding it costs more gas than the minimum griefing value, making this attack economically irrational for small amounts.

## Proof of Concept

```solidity
function test_forced_eth_selfdestruct() public {
    GriefingContract grief = new GriefingContract();
    vm.deal(address(grief), 1 ether);
    grief.forceSend(payable(address(clDispatcher)));

    // 1 ETH forced into dispatcher — bypasses receive()/fallback() revert
    assertEq(address(clDispatcher).balance, 1 ether, "ETH force-sent to dispatcher");

    // Dispatch proceeds normally, distributing the forced ETH
    mockStaking.setZeroWithdrawer(true);
    vm.prank(attacker);
    clDispatcher.dispatch(PUBKEY_ROOT_1);

    assertEq(address(clDispatcher).balance, 0, "Forced ETH dispatched");
}
```

The helper contract:

```solidity
contract GriefingContract {
    function forceSend(address payable target) external payable {
        selfdestruct(target);
    }
}
```

## Recommended Mitigation

1. **Accept as inherent risk**: This is a well-known Ethereum design pattern limitation. The `selfdestruct` opcode exists at the EVM level and bypasses all Solidity-level guards. There is no practical way to prevent a contract from receiving ETH via `selfdestruct`.

2. **Track expected vs actual balance**: Maintain an internal balance accumulator that tracks ETH received through legitimate `dispatch()` calls (i.e., `msg.value` attached to `dispatch()` calls). Compare against `address(this).balance` periodically to detect discrepancies. This is complex and may not be worth the added gas cost.

3. **Document in operational procedures**: Note that forced ETH via `selfdestruct` is an accepted risk. In practice, the gas cost of a `selfdestruct` attack exceeds the value that can be forced in, making it economically irrational except for symbolic amounts.

## Status

Open
