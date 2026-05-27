# Audit Notes Index

## Overview

This directory contains audit-related notes, analysis outputs, and observations for the Kiln V1 staking contracts audit.

### Re-evaluation Summary

All 19 findings were rigorously re-evaluated against the Cantina bounty criteria and 11 prior audit PDFs (Halborn 2022 → Cantina Managed Apr 2025).

| Outcome        | Count                                                       |
| -------------- | ----------------------------------------------------------- |
| **KEPT**       | 1 (F-008 — High)                                            |
| **DOWNGRADED** | 3 (F-010: Medium→Low, F-004: Low→Info, F-013: Low→Info)     |
| **REMOVED**    | 15 (duplicates, out of scope, known issues, best practices) |
| **Total**      | **19**                                                      |

### Validated Severity Summary

| Severity      | Count |
| ------------- | ----- |
| High          | 1     |
| Low           | 1     |
| Informational | 2     |
| **Total**     | **4** |

### Test Statistics

- **62 Foundry tests** (18 StakingContract + 21 FeeDispatcher + 23 Proxy)
- **0 failures**
- Slither analysis: 202 detections across 5 contracts, ~11 real issues

---

## 1. Slither Static Analysis Results

| #   | Contract                                                                     | Detections | Key Findings                                                                                                             |
| --- | ---------------------------------------------------------------------------- | ---------- | ------------------------------------------------------------------------------------------------------------------------ |
| 1   | [`StakingContract.sol`](slither-StakingContract.txt)                         | 122        | `calls-loop`, `reentrancy-events`, `unused-return`, `uninitialized-local`, `unindexed-event-address`, naming conventions |
| 2   | [`ConsensusLayerFeeDispatcher.sol`](slither-ConsensusLayerFeeDispatcher.txt) | 21         | `arbitrary-send-eth`, `divide-before-multiply`, `incorrect-equality`, `missing-zero-check`, `reentrancy-events`          |
| 3   | [`ExecutionLayerFeeDispatcher.sol`](slither-ExecutionLayerFeeDispatcher.txt) | 21         | `arbitrary-send-eth`, `divide-before-multiply`, `incorrect-equality`, `missing-zero-check`, `reentrancy-events`          |
| 4   | [`FeeRecipient.sol`](slither-FeeRecipient.txt)                               | 4          | `arbitrary-send-eth`, `solc-version`, naming conventions                                                                 |
| 5   | [`TUPProxy.sol`](slither-TUPProxy.txt)                                       | 34         | `incorrect-return` (assembly), `incorrect-modifier`, `unused-return`, dead code, assembly usage                          |

**Total Slither Detections: 202**

### Detector Categories (across all contracts)

- **High/Medium Severity:**
  - `arbitrary-send-eth` — ETH sent to arbitrary user addresses via low-level calls
  - `reentrancy-events` — Events emitted after external calls (CEI pattern violations)
  - `incorrect-equality` — Dangerous strict equality comparisons (e.g., `balance == 0`, `status == false`)
  - `missing-zero-check` — No zero-address validation before sending ETH
  - `calls-loop` — External calls inside loops (gas DoS risk)
  - `divide-before-multiply` — Precision loss in fee calculations

- **Low/Informational:**
  - `assembly` usage in storage libraries
  - `naming-convention` violations (underscore prefix parameters)
  - `solc-version` warnings
  - `unindexed-event-address` — Address parameters not indexed
  - `boolean-equal` — Comparison to boolean constants
  - `too-many-digits` — Long hex literals
  - Dead code in inherited OpenZeppelin contracts

---

## 2. Gas Report

- [`gas-report.txt`](gas-report.txt) — Foundry-generated gas report

---

## 3. Manual Code Review Findings

### Validated Findings (Kept)

| ID                                                              | Title                                                   | Final Severity | Validation Status |
| --------------------------------------------------------------- | ------------------------------------------------------- | -------------- | ----------------- |
| [F-008](../findings/F-008-arbitrary-send-eth-zero-address.md)   | ETH Burned via Missing Zero-Address Checks              | **High**       | ✅ KEPT           |
| [F-010](../findings/F-010-reentrancy-events-cei-violation.md)   | CEI Pattern Violations in Fee Dispatchers               | **Low**        | ⬇️ DOWNGRADED     |
| [F-004](../findings/F-004-balance-check-after-external-call.md) | Balance Check After External Call in \_depositValidator | **Info**       | ⬇️ DOWNGRADED     |
| [F-013](../findings/F-013-fee-recipient-init-frontrunning.md)   | FeeRecipient init() Front-Running                       | **Info**       | ⬇️ DOWNGRADED     |

### Removed Findings (Discarded)

| ID                                                                                 | Title                                                        | Original Severity | Removal Reason                                       |
| ---------------------------------------------------------------------------------- | ------------------------------------------------------------ | ----------------- | ---------------------------------------------------- |
| [F-001](../findings/DISCARDED/F-001-calls-loop-batch-withdraw.md)                  | Calls-Loop in Batch Withdraw Functions                       | **Medium**        | Out of scope: gas consumption                        |
| [F-002](../findings/DISCARDED/F-002-calls-loop-addValidators.md)                   | Calls-Loop in addValidators                                  | **Medium**        | Out of scope: gas consumption                        |
| [F-003](../findings/DISCARDED/F-003-unrestricted-fee-recipient-withdraw.md)        | Unrestricted FeeRecipient.withdraw()                         | **Medium**        | Design choice                                        |
| [F-005](../findings/DISCARDED/F-005-swap-pop-removeValidators.md)                  | Swap-and-Pop State Inconsistency in removeValidators         | **Low**           | Best practice suggestion                             |
| [F-006](../findings/DISCARDED/F-006-centralization-risks.md)                       | Centralization Risks in Admin Powers                         | **Informational** | Out of scope: centralization                         |
| [F-007](../findings/DISCARDED/F-007-reentrancy-receive-deposit.md)                 | Reentrancy via receive() on Deposit                          | **Informational** | Out of scope: informational + not exploitable        |
| [F-009](../findings/DISCARDED/F-009-divide-before-multiply-precision-loss.md)      | Precision Loss in Cascading Fee Calculation                  | **Medium**        | Out of scope: rounding errors                        |
| [F-011](../findings/DISCARDED/F-011-incorrect-equality-balance-check.md)           | Strict Equality Checks on Balance and Status                 | **Low**           | Best practice suggestion                             |
| [F-012](../findings/DISCARDED/F-012-selfdestruct-forced-eth-bypass.md)             | Self-Destruct Forced ETH Bypasses receive()/fallback()       | **Low**           | Known EVM limitation                                 |
| [F-014](../findings/DISCARDED/F-014-unauthorized-dispatch-public-access.md)        | Unauthorized dispatch() and withdraw() — Public Access       | **Medium**        | Design choice + duplicate of F-003                   |
| [F-015](../findings/DISCARDED/F-015-proxy-admin-centralization.md)                 | TUPProxy Admin Centralization — Malicious Upgrade Drains ETH | **High**          | Out of scope: centralization + trusted role          |
| [F-016](../findings/DISCARDED/F-016-authorized-fee-recipient-missing-events.md)    | AuthorizedFeeRecipient Missing Events on Init/Withdraw       | **Medium**        | Out of scope: missing events + duplicate of Spearbit |
| [F-017](../findings/DISCARDED/F-017-authorized-fee-recipient-frozen-dispatcher.md) | AuthorizedFeeRecipient Frozen Dispatcher — No Update         | **Medium**        | Design choice + proxy upgrade recovery               |
| [F-018](../findings/DISCARDED/F-018-proxy-pause-bypass-address-zero.md)            | TUPProxy Pause Bypass for address(0)                         | **Informational** | Out of scope: informational                          |
| [F-019](../findings/DISCARDED/F-019-proxy-slither-false-positives.md)              | Slither False Positives — TUPProxy.sol                       | **Informational** | Out of scope: informational                          |

### Summary of 122 Slither Findings (StakingContract.sol)

| Detector                  | Count | Verdict                                                                              |
| ------------------------- | ----- | ------------------------------------------------------------------------------------ |
| `calls-loop`              | 9     | ✅ **Confirmed** — Real vulnerability (see F-001, F-002, both removed from bounty)   |
| `reentrancy-events`       | 5     | ⚠️ **Partially confirmed** — Events after external call, but not exploitable (F-007) |
| `uninitialized-local`     | 3     | ⚠️ **False positive** — Variables are initialized in all execution paths             |
| `assembly`                | 1     | ⚠️ **False positive** — Intentional storage slot access (design feature)             |
| `boolean-equal`           | 2     | ⚠️ **False positive** — Boolean comparisons in require() are style choice            |
| `dead-code`               | 1     | ⚠️ **False positive** — Unused `_min()` kept for future use                          |
| `pragma` version          | 1     | ⚠️ **Informational** — Solidity 0.8.13 specified as intended                         |
| Naming conventions        | ~60   | ⚠️ **False positive** — Contract follows project style conventions                   |
| `unused-return`           | ~12   | ⚠️ **False positive** — Return values used in calling context                        |
| `unindexed-event-address` | ~15   | ⚠️ **Informational** — Gas optimization, not a vulnerability                         |
| `too-many-digits`         | ~13   | ⚠️ **False positive** — Address literals and constants                               |

---

## 4. Foundry Test Results

| Test                                         | Result  | Gas       | Notes                                                           |
| -------------------------------------------- | ------- | --------- | --------------------------------------------------------------- |
| `test_reentrancy_on_receive`                 | ✅ PASS | 771,460   | No reentrancy exploitable through trusted DepositContract       |
| `test_unauthorized_operator_registration`    | ✅ PASS | 14,666    | Access control works                                            |
| `test_unauthorized_validator_addition`       | ✅ PASS | 19,363    | Access control works                                            |
| `test_unauthorized_set_limit`                | ✅ PASS | 13,510    | Access control works                                            |
| `test_deposit_frontrunning`                  | ✅ PASS | 739,432   | No economic advantage to front-run (validators are equivalent)  |
| `test_reward_accounting` (fuzz)              | ✅ PASS | 3,593 avg | 256 fuzz runs, no overflow or precision loss                    |
| `test_commission_precision_loss`             | ✅ PASS | 8,458     | Dust rounds in favor of withdrawer (truncation toward zero)     |
| `test_unbounded_gas_loop`                    | ✅ PASS | 498,793   | **Vulnerability confirmed:** ~118k gas per key in batchWithdraw |
| `test_unbounded_gas_addValidators`           | ✅ PASS | 1,180,552 | **Vulnerability confirmed:** ~118k gas per key in addValidators |
| `test_admin_fee_redirection`                 | ✅ PASS | 59,487    | Admin can redirect fees (centralization risk - F-006)           |
| `test_duplicate_key_prevention`              | ✅ PASS | 284,291   | Duplicate key detection works                                   |
| `test_removeValidators_swap_state`           | ✅ PASS | 773,154   | Swap-and-pop works but changes index mapping (F-005)            |
| `test_removeValidators_funded_protection`    | ✅ PASS | 500,125   | Funded validators protected from deletion                       |
| `test_removeValidators_unsorted_indexes`     | ✅ PASS | 527,034   | Unsorted indexes correctly rejected                             |
| `test_balance_check_selfdestruct_resilience` | ✅ PASS | 443,320   | Balance check reverts on mismatch (F-004)                       |
| `test_max_operator_count`                    | ✅ PASS | 16,871    | Max 1 operator enforced                                         |
| `test_initialize_once`                       | ✅ PASS | 20,730    | Double-init prevented                                           |
| `test_operator_fee_limit`                    | ✅ PASS | 15,622    | Fee limits enforced                                             |

**All 18 tests passed. 0 failures.**

### FeeDispatcherAudit.t.sol Results (21 tests)

| Test                                             | Result  | Gas       | Notes                                                                      |
| ------------------------------------------------ | ------- | --------- | -------------------------------------------------------------------------- |
| `test_arbitrary_send_eth_withdrawer_zero`        | ✅ PASS | 176,092   | Withdrawer ETH burned to address(0) — **F-008**                            |
| `test_arbitrary_send_eth_operator_zero`          | ✅ PASS | 173,286   | Operator fee burned to address(0) — **F-008**                              |
| `test_arbitrary_send_eth_el_dispatcher`          | ✅ PASS | 164,442   | Same vulnerability in EL dispatcher — **F-008**                            |
| `test_precision_loss` (fuzz)                     | ✅ PASS | 156,033 μ | 256 fuzz runs, all ETH accounted for — **F-009**                           |
| `test_precision_loss_dust_edge_case`             | ✅ PASS | 117,784   | Zero fees on small balances due to truncation — **F-009**                  |
| `test_unauthorized_dispatch`                     | ✅ PASS | 196,037   | Anyone can call dispatch()/withdraw() — **F-014**                          |
| `test_unauthorized_dispatch_zero_balance`        | ✅ PASS | 12,942    | Zero-balance dispatch correctly reverts                                    |
| `test_reentrancy_event_ordering`                 | ✅ PASS | 513,308   | Reentrant dispatch consumes funds, causes TreasuryReceiveError — **F-010** |
| `test_reentrancy_toggle_before_send`             | ✅ PASS | 181,069   | CEI: toggle called before send (vm.expectCall) — **F-010**                 |
| `test_incorrect_equality_dust_griefing`          | ✅ PASS | 77,864    | Dust passes balance == 0, zero fees collected — **F-011**                  |
| `test_incorrect_equality_status_checks`          | ✅ PASS | 137,353   | Funds preserved on revert (status == false check)                          |
| `test_fee_recipient_eth_lock_no_dispatcher`      | ✅ PASS | 252,687   | ETH stuck with address(0) dispatcher — **F-013**                           |
| `test_fee_recipient_no_setter`                   | ✅ PASS | 187       | No setDispatcher() exists — **F-013**                                      |
| `test_fee_recipient_receive_direct_eth`          | ✅ PASS | 158,877   | FeeRecipient forwards ETH correctly                                        |
| `test_fee_recipient_init_frontrunning`           | ✅ PASS | 254,046   | init() can be front-run — **F-013**                                        |
| `test_cross_contract_admin_control`              | ✅ PASS | 188,848   | Admin changes fee parameters (centralization risk)                         |
| `test_el_treasury_zero_burns_eth`                | ✅ PASS | 149,052   | Treasury fee burned to address(0) — **F-008**                              |
| `test_cl_exit_exemption_logic`                   | ✅ PASS | 196,858   | Fees on rewards only, principal exempted                                   |
| `test_cl_slashing_no_exemption`                  | ✅ PASS | 153,363   | Full fee charged on slashed principal                                      |
| `test_forced_eth_selfdestruct`                   | ✅ PASS | 244,064   | Self-destruct bypasses receive/fallback — **F-012**                        |
| `test_el_dispatcher_no_state_change_before_send` | ✅ PASS | 144,802   | EL dispatcher does not toggle withdrawn flag                               |

**All 21 tests passed. 0 failures.**

### ProxyAudit.t.sol Results (23 tests)

| Test                                              | Result  | Gas     | Notes                                                                             |
| ------------------------------------------------- | ------- | ------- | --------------------------------------------------------------------------------- |
| `test_selector_clash_detection`                   | ✅ PASS | 89,494  | pause()/unpause() selectors match by design in transparent proxy — **F-019**      |
| `test_admin_only_upgrade`                         | ✅ PASS | 45,051  | Non-admin cannot upgrade; non-admin low-level call reverts with empty data        |
| `test_admin_can_upgrade_to_malicious`             | ✅ PASS | 61,423  | Admin upgrades to malicious impl + drain via selfdestruct — **F-015**             |
| `test_pause_blocks_nonadmin_calls`                | ✅ PASS | 44,196  | Paused system blocks non-admin calls with CallWhenPaused                          |
| `test_admin_functions_work_when_paused`           | ✅ PASS | 72,113  | Admin can still upgrade/changeAdmin when paused                                   |
| `test_pause_bypass_for_zero_address`              | ✅ PASS | 44,554  | address(0) bypasses pause (intentional eth_call compatibility) — **F-018**        |
| `test_storage_collision_analysis`                 | ✅ PASS | 64,082  | ERC1967 slots + pause slot do not collide with impl storage                       |
| `test_authorized_fee_recipient_init_access`       | ✅ PASS | 897,191 | Anyone can call init(), msg.sender becomes stakingContract — **F-013**            |
| `test_authorized_fee_recipient_init_frontrunning` | ✅ PASS | 896,214 | Attacker calls init() first -> front-run PoC — **F-013**                          |
| `test_authorized_withdraw_only`                   | ✅ PASS | 898,511 | Only stakingContract can withdraw; non-stakingContract reverts                    |
| `test_authorized_eth_lockup`                      | ✅ PASS | 898,450 | ETH sent before init() is lockable by whoever calls init() first                  |
| `test_authorized_reentrancy_resistance`           | ✅ PASS | 959,038 | withdraw() calls dispatcher.dispatch() — dispatcher could reenter                 |
| `test_forced_eth_selfdestruct`                    | ✅ PASS | 973,246 | Self-destruct forces ETH into fee recipient; forwarded on withdraw — **F-012**    |
| `test_missing_events_documentation`               | ✅ PASS | 893,631 | init() and withdraw() emit no events — **F-016**                                  |
| `test_before_fallback_call_chain`                 | ✅ PASS | 62,482  | BeforeFallback chain: TUPProxy pause check -> OZ admin check -> Proxy passthrough |
| `test_constructor_initialization`                 | ✅ PASS | 14,841  | Constructor sets impl, admin, and calls initializer via delegatecall              |
| `test_change_admin_access`                        | ✅ PASS | 43,269  | Only current admin can change admin; old admin loses access                       |
| `test_ifadmin_modifier_correctness`               | ✅ PASS | 29,124  | ifAdmin modifier: admin -> \_; non-admin -> \_fallback() — **F-019**              |
| `test_upgrade_event_emission`                     | ✅ PASS | 24,920  | Upgraded(address) event emitted on upgrade                                        |
| `test_pause_slot_initial_state`                   | ✅ PASS | 11,590  | Pause slot starts as false                                                        |
| `test_pause_only_admin`                           | ✅ PASS | 49,176  | Only admin can pause                                                              |
| `test_unpause_only_admin`                         | ✅ PASS | 29,471  | Only admin can unpause                                                            |
| `test_no_dispatcher_update`                       | ✅ PASS | 893,631 | No setDispatcher() function exists — **F-017**                                    |

**All 23 tests passed. 0 failures.**

---

## 5. Architecture Notes

- **Non-custodial ETH staking**: Users deposit ETH → protocol mints validators → rewards flow to FeeRecipient clones
- **Clone factory pattern**: Each validator gets a deterministic FeeRecipient (minimal proxy via CREATE2)
- **Fee dispatch**: EL/CL dispatchers compute treasury and operator fees, send remainder to withdrawer
- **Packed storage**: 4 `ValidatorsFundingInfo` per uint256 slot (64 bits each: 32 available + 32 funded)
- **Storage slots**: Custom assembly-based unstructured storage pattern (SLOAD/SSTORE with precomputed slots)
- **Fee computation**: In basis points (1 BPS = 0.01%), with `operatorFee` as percentage of `globalFee`
