# Finding: Strict Equality Checks on Balance and Status

## Severity

**Low** — Griefing and edge-case vulnerabilities, not direct fund loss

## Description

Both dispatchers use strict equality (`== 0`) to check the contract balance before processing a dispatch:

```solidity
// ConsensusLayerFeeDispatcher.sol, line 65
uint256 balance = address(this).balance;
if (balance == 0) {
    revert ZeroBalanceWithdrawal();
}
```

This is flagged by Slither's [`incorrect-equality`](audit/notes/slither-ConsensusLayerFeeDispatcher.txt) detector because:

1. **Balance == 0 is a strict equality check** — any non-zero balance passes, including dust amounts (1 wei) that result in zero fees due to truncation. A dust amount of 1-3 wei with realistic BPS values produces `globalFee = 0`, meaning the dispatcher processes the withdrawal but collects no fees.

2. **Self-destruct edge case** — The [`receive()`](src/contracts/ConsensusLayerFeeDispatcher.sol:135) and [`fallback()`](src/contracts/ConsensusLayerFeeDispatcher.sol:139) functions revert, but `selfdestruct` can force ETH into the contract, bypassing these guards. After forced ETH, `balance == 0` passes and the dispatch proceeds normally.

The [`getWithdrawnFromPublicKeyRoot()`](src/contracts/ConsensusLayerFeeDispatcher.sol:70) check (`!withdrawn`) and [`getExitRequestedFromRoot()`](src/contracts/ConsensusLayerFeeDispatcher.sol:69) check (`exitRequested`) use strict equality against `false`:

```solidity
// Line 74
if (exitRequested && balance >= 31 ether && !withdrawn) {
```

While functionally equivalent to `withdrawn == false`, Slither flags these as [`boolean-equal`](audit/notes/slither-ConsensusLayerFeeDispatcher.txt) style issues.

## Impact

- **Griefing via Dust**: An attacker could send 1 wei to the dispatcher at negligible cost, triggering a dispatch that collects zero fees. While the dispatcher is drained (dust goes to the withdrawer), the treasury and operator lose their fee collection for that dispatch. This is currently impractical due to gas costs exceeding the griefing value.

- **Self-destruct Dust Forced**: A griefer could deploy a contract with 1 wei and `selfdestruct` to the dispatcher address, forcing 1 wei into the dispatcher. The next legitimate dispatch then processes this dust along with the intended balance. This has no material impact since the dust is distributed proportionally.

- **No Direct Fund Loss**: The `balance == 0` check is functionally correct for its purpose — preventing empty dispatches. The edge cases are theoretical or require impractical amounts of gas.

## Proof of Concept

### Dust balance passes the check but collects zero fees

```solidity
function test_incorrect_equality_dust_griefing() public {
    vm.deal(address(clDispatcher), 1 wei);
    vm.prank(attacker);
    clDispatcher.dispatch(PUBKEY_ROOT_1);

    // 1 wei passes balance == 0 check, but globalFee rounds to 0
    assertEq(user.balance, 1 wei, "Dust goes to withdrawer, no fees collected");
}
```

### Self-destruct forces ETH past the receive()/fallback() revert

```solidity
function test_forced_eth_selfdestruct() public {
    GriefingContract grief = new GriefingContract();
    vm.deal(address(grief), 1 ether);
    grief.forceSend(payable(address(clDispatcher)));

    // 1 ETH forced in — balance > 0, check passes
    assertEq(address(clDispatcher).balance, 1 ether, "ETH force-sent to dispatcher");

    // Dispatch succeeds, distributing the forced ETH
    mockStaking.setZeroWithdrawer(true);
    vm.prank(attacker);
    clDispatcher.dispatch(PUBKEY_ROOT_1);

    assertEq(address(clDispatcher).balance, 0, "Forced ETH dispatched");
}
```

## Recommended Mitigation

1. **Use a minimum balance threshold** instead of strict equality:

   ```solidity
   uint256 constant MIN_DISPATCH_BALANCE = 1 gwei; // or similar
   if (balance < MIN_DISPATCH_BALANCE) {
       revert InsufficientBalance();
   }
   ```

   This prevents dust-griefing and ensures dispatches are economically meaningful.

2. **Replace boolean equality comparisons** with the idiomatic form:

   ```solidity
   // Instead of: if (exitRequested && balance >= 31 ether && !withdrawn)
   // Use:      if (exitRequested && balance >= 31 ether && !withdrawn)
   // (The ! operator is already used — no change needed for boolean checks)
   ```

   The existing code already uses the idiomatic `!withdrawn` form, which is preferred over `withdrawn == false`.

3. **Acknowledge as informational**: The self-destruct vector is inherent to Ethereum contract design and cannot be fully mitigated without significant architectural changes. Document it as an accepted risk.

## Status

Open
