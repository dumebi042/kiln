# Finding: CEI Pattern Violations in Fee Dispatchers

## Summary

Both [`ConsensusLayerFeeDispatcher.dispatch()`](src/contracts/ConsensusLayerFeeDispatcher.sol:95) and [`ExecutionLayerFeeDispatcher.dispatch()`](src/contracts/ExecutionLayerFeeDispatcher.sol:73) violate the Checks-Effects-Interactions (CEI) pattern: ETH is sent via `.call()` before events are emitted, and the `withdrawer` receives ETH before `operator` and `treasury` — enabling reentrancy (DOS/griefing only). Events being out of order is an informational/QA issue.

## Finding Description

Both fee dispatchers violate the CEI pattern in their [`dispatch()`](src/contracts/ConsensusLayerFeeDispatcher.sol:59) functions. Two specific violations exist:

### Violation 1: State Change Before External Call (CL dispatcher only)

In [`ConsensusLayerFeeDispatcher.dispatch()`](src/contracts/ConsensusLayerFeeDispatcher.sol:81), the state-modifying call `toggleWithdrawnFromPublicKeyRoot()` is made **BEFORE** the ETH transfer to the withdrawer:

```solidity
// Line 81 — STATE CHANGE (effect) BEFORE external call
stakingContract.toggleWithdrawnFromPublicKeyRoot(_publicKeyRoot);

// ...

// Line 95 — EXTERNAL CALL (interaction)
(bool status, bytes memory data) = withdrawer.call{value: balance - globalFee}("");
```

Correct CEI ordering would place `toggleWithdrawnFromPublicKeyRoot()` **after** all ETH transfers and **before** the event emission.

### Violation 2: Events After External Calls (both dispatchers)

In both dispatchers, the [`Withdrawal`](src/contracts/ConsensusLayerFeeDispatcher.sol:111) event is emitted **after** all ETH transfers complete:

```solidity
// Lines 95-110 — EXTERNAL CALLS (interactions)
withdrawer.call{value: balance - globalFee}("");
treasury.call{value: globalFee - operatorFee}("");
operator.call{value: operatorFee}("");

// Line 111 — EVENT (effect) AFTER external calls
emit Withdrawal(withdrawer, operator, _publicKeyRoot, ...);
```

Correct ordering would emit events before or atomically with the state changes, not after external calls.

### Reentrancy Path Analysis

The reentrancy path works as follows: a malicious FeeRecipient (withdrawer contract) can reenter `dispatch()` during the first `.call{value: ...}` ETH transfer using its `receive()` function. The reentrant call computes fees on the remaining dispatcher balance, consuming all remaining ETH. The outer dispatch then fails with `TreasuryReceiveError` because no ETH remains for the treasury/operator sends.

However, as analyzed in our cross-reference against prior audits, this is **DOS/griefing only** — no fund-moving path exists because:

1. The reentrant call drains the dispatcher's remaining balance, but the attacker (the malicious withdrawer) only receives their own fee share for the reentered validator.
2. The attacker's economic incentive is zero — they can only grief their own rewards.
3. No state manipulation allows redirecting funds intended for other recipients.

### Prior Audit Precedent

An identical CEI pattern violation was rated **Low** in Spearbit DeFi Integrations v1.2 (Jan 2025) finding 5.2.3. The Spearbit finding was confirmed by the Cantina Managed (Apr 2025) review. Per Cantina bounty rules requiring "prove the delta" and incremental impact, this finding cannot be submitted at Medium when a prior audit already identified the same pattern at Low severity.

## Impact Explanation

**Severity**: Low 🟢
**Severity Matrix**: `Impact Low × Likelihood Low` — falls below the matrix threshold at [`AUDIT_SCOPE.md:44-54`](AUDIT_SCOPE.md:44), confirming minimal practical risk.

- **Reentrancy Griefing/DOS only**: A malicious withdrawer contract can reenter `dispatch()` during the ETH transfer. The reentrant call computes fees on the remaining dispatcher balance, consuming all remaining ETH. The outer dispatch then fails with `TreasuryReceiveError` because no ETH remains for the treasury/operator sends. No funds are at risk.

- **Events out-of-order (Informational/QA)**: Off-chain monitors and indexers rely on event ordering to track fee distribution. If events are emitted after external calls complete, a reentrant dispatch causes interleaved event emissions that do not reflect the actual execution order. Events for the outer dispatch may be emitted after events from the reentrant call.

- **No fund-moving path exists**: The attacker can only grief their own rewards. No economic incentive.

## Likelihood Explanation

**Likelihood: Low** — Reentrancy requires a malicious FeeRecipient contract that reenters `dispatch()`. The attacker gains nothing economically (can only DOS/grief their own rewards). No economic incentive exists. Requires specific contract setup with a malicious withdrawer.

## Proof of Concept

Since this finding is rated **Low** severity, a PoC is not strictly required per Cantina rules. However, the following conceptual description demonstrates the reentrancy path:

### Reentrancy via `withdrawer.call` — DOS/Griefing

The test at [`test_reentrancy_event_ordering()`](audit/tests/FeeDispatcherAudit.t.sol:437) proves a reentrant `dispatch()` call is made during the outer dispatch's ETH transfer:

```
dispatch(PUBKEY_ROOT_2) [balance=10 ETH]
  -> withdrawer.call{value: 9.5 ETH} (detector receives ETH)
    -> detector reenters: dispatch(PUBKEY_ROOT_1) [balance=0.5 ETH]
      -> sends withdrawer (0.475 ETH), treasury (0.02 ETH), operator (0.005 ETH)
      -> emit Withdrawal for PUBKEY_ROOT_1
      -> dispatcher balance = 0
    <- reentrant dispatch returns
  -> treasury.call{value: 0.4 ETH} FAILS — OutOfFunds
  -> revert TreasuryReceiveError
```

The CEI violation is also confirmed at code level via [`test_reentrancy_toggle_before_send()`](audit/tests/FeeDispatcherAudit.t.sol:490), which uses `vm.expectCall` to prove `toggleWithdrawnFromPublicKeyRoot` is called before the ETH send — despite the eventual revert rolling back state.

## Recommendation

1. **Reorder operations in [`ConsensusLayerFeeDispatcher.dispatch()`](src/contracts/ConsensusLayerFeeDispatcher.sol:59)** to follow CEI:

   ```solidity
   // 1. Checks (already done — balance == 0 check)

   // 2. External calls (interactions) — all ETH transfers first
   (bool status, bytes memory data) = withdrawer.call{value: balance - globalFee}("");
   if (status == false) { revert WithdrawerReceiveError(data); }
   // ... treasury and operator sends

   // 3. Effects (state changes + events)
   if (exitRequested && ...) {
       stakingContract.toggleWithdrawnFromPublicKeyRoot(_publicKeyRoot);
   }
   emit Withdrawal(withdrawer, operator, _publicKeyRoot, ...);
   ```

2. **Move state changes before external calls, not after**: The `toggleWithdrawnFromPublicKeyRoot()` call should happen after all ETH transfers but before the event. This prevents the reentrancy griefing vector because the state change that prevents re-dispatching the same validator would already be committed before the withdrawer receives ETH.

3. **Move event emissions before external calls**: Consider emitting the `Withdrawal` event before the ETH transfers, and reverting with a separate error if the transfer fails. This ensures event ordering is deterministic regardless of reentrancy.

4. **Alternative: Use a reentrancy guard**: Apply OpenZeppelin's `ReentrancyGuard` or a custom mutex to the `dispatch()` functions as a simpler defensive measure.

5. **Alternative: Pull-over-push pattern**: Instead of pushing ETH to recipients during `dispatch()`, have recipients withdraw their accumulated fees on-demand. This eliminates the reentrancy vector entirely.
