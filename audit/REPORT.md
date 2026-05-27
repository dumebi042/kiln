# Kiln On-Chain V1 — Validated Security Audit Report

## Overview

- **Protocol**: Kiln On-Chain V1 — Non-custodial ETH staking
- **Audit Scope**: Full manual code review, Slither static analysis verification, Foundry fuzz and unit testing across all contracts, then re-evaluated against Cantina bounty criteria and 11 prior audit PDFs
- **Contracts Audited**:
  - [`StakingContract.sol`](src/contracts/StakingContract.sol) — Core staking logic (959 lines)
  - [`ConsensusLayerFeeDispatcher.sol`](src/contracts/ConsensusLayerFeeDispatcher.sol) — CL fee distribution
  - [`ExecutionLayerFeeDispatcher.sol`](src/contracts/ExecutionLayerFeeDispatcher.sol) — EL fee distribution
  - [`FeeRecipient.sol`](src/contracts/FeeRecipient.sol) — Standard fee recipient clone
  - [`AuthorizedFeeRecipient.sol`](src/contracts/AuthorizedFeeRecipient.sol) — Access-controlled fee recipient
  - [`TUPProxy.sol`](src/contracts/TUPProxy.sol) — Transparent upgradeable proxy with pause
- **Deployments**: [Mainnet](src/DeployedAddresses.sol:23) (`0x0A7272e8573aea8359FEC143ac02AED90F822bD0`), [Testnet](src/DeployedAddresses.sol:31) (Holesky)
- **Solidity Version**: `0.8.13` with built-in overflow protection
- **Methodology**: Manual line-by-line code review, Slither static analysis, Foundry tests (62 total), then strict cross-referencing against 11 prior audit PDFs (Halborn 2022 → Cantina Managed Apr 2025) applying Cantina bounty criteria: "prove the delta", incremental impact only

## Re-evaluation Summary

- **19 original findings** → **1 validated**, **3 downgraded**, **15 removed**
- Cross-referenced against 11 prior audit PDFs:
  - Halborn (2022)
  - Spearbit (Jul 2023, Apr 2024, Aug 2024)
  - Quantstamp (Feb 2024)
  - Cantina Managed — Kiln Staking Contracts
  - Cantina Managed — Kiln DeFi Integrations (×2)
  - Sigma Prime — Kiln DeFi Integrations (v2)
  - Cantina Code — Kiln 1202
  - Cantina Managed (Apr 2025)
- Strict bounty criteria applied: "prove the delta" — only findings with incremental impact beyond prior audits are eligible
- **Result**: Only F-008 (Inconsistent Address Validation in Fee Dispatchers) is a novel, medium-severity vulnerability not covered in any prior audit

## Findings Summary

Findings are organized using the Cantina submission template headings: **Summary**, **Finding Description**, **Impact Explanation**, **Likelihood Explanation**, **Proof of Concept**, and **Recommendation**. Both submissions are Cantina-ready.

---

## Final Validated Findings

### 🟡 Medium Severity (1)

#### F-008 — Inconsistent Address Validation in Fee Dispatchers Allows Permanent ETH Burn to Zero Address

**Value at risk: ~9.5+ ETH per dispatch, scales with validators × accumulated rewards**
**Novel finding**: Not covered in any of 11 prior audits. Halborn (Jul 2023, 5.3.5) and Spearbit (Jul 2023) flagged missing `_checkAddress()` in setters but **never examined the dispatchers' `dispatch()` functions** — the actual ETH transfer paths.

**The bug is missing validation, not Admin behavior.** This finding does NOT fall under the trusted-role exclusion ([`AUDIT_SCOPE.md:94-96`](AUDIT_SCOPE.md:94)). It is a code defect: [`_checkAddress()`](src/contracts/StakingContract.sol:954) — a reusable zero-address guard — is used in 3 address-setting functions but missing in 4 others including both dispatchers' `dispatch()`. The inconsistent application proves developer oversight, not intentional design.

**What makes this a code defect**:

- [`_checkAddress()`](src/contracts/StakingContract.sol:954) exists and is consistently applied in [`initialize_1()`](src/contracts/StakingContract.sol:163) (6×), [`setOperatorAddresses()`](src/contracts/StakingContract.sol:417) (2×), and [`setWithdrawer()`](src/contracts/StakingContract.sol:434) (1×)
- It is missing in [`setTreasury()`](src/contracts/StakingContract.sol:214), [`addOperator()`](src/contracts/StakingContract.sol:392), and **both fee dispatchers' [`dispatch()`](src/contracts/ConsensusLayerFeeDispatcher.sol:59)** — the contracts that actually send ETH
- Halborn (Jul 2023, 5.3.5) flagged the same missing-`_checkAddress` pattern in `setOperatorAddresses()`/`addOperator()` as a valid Low finding — confirming the codebase should have these checks

**Non-malicious trigger scenarios** (escape the scope exclusion):

1. Multi-sig accidentally passing `address(0)` to `setTreasury()` (honest mistake, not malicious)
2. Operator registered via `addOperator()` before addresses are finalized (operational oversight)
3. Migration window where addresses are temporarily `address(0)` (timing gap)
4. Default `address(0)` return from `getWithdrawerFromPublicKeyRoot()` for unconfigured validators (data state)
5. External attacker compromising a single multi-sig signer (Admin acting in good faith)
6. Separate bug setting a `withdrawer` to `address(0)` (defense-in-depth failure)

**Impact**: Permanent ETH burn. The EVM executes `address(0).call{value: X}("")` successfully, returning `(true, 0x)`, and the sent ETH is irretrievably destroyed. No recovery mechanism exists. Silent failure — the dispatcher's error types (`WithdrawerReceiveError`, `TreasuryReceiveError`) are never triggered because the call succeeds.

**PoC**: Foundry tests in [`audit/tests/FeeDispatcherAudit.t.sol`](audit/tests/FeeDispatcherAudit.t.sol): `test_arbitrary_send_eth_withdrawer_zero`, `test_arbitrary_send_eth_operator_zero`, `test_el_treasury_zero_burns_eth`, `test_arbitrary_send_eth_el_dispatcher`.

**Mitigation**: Add `_checkAddress()` (or equivalent inline checks) before each ETH transfer in both dispatchers' `dispatch()`, plus add it to `setTreasury()` and `addOperator()` for defense-in-depth.

**Full finding**: [`audit/findings/F-008-arbitrary-send-eth-zero-address.md`](audit/findings/F-008-arbitrary-send-eth-zero-address.md)

---

### 🟢 Low Severity (1)

#### F-010 — CEI Pattern Violations in Fee Dispatchers (Downgraded from Medium)

**Summary**: Both [`ConsensusLayerFeeDispatcher`](src/contracts/ConsensusLayerFeeDispatcher.sol) and [`ExecutionLayerFeeDispatcher`](src/contracts/ExecutionLayerFeeDispatcher.sol) violate checks-effects-interactions: the CL dispatcher calls `toggleWithdrawnFromPublicKeyRoot()` (state change) _before_ the withdrawer ETH transfer, and both dispatchers emit events _after_ all external calls.

**Downgrade rationale**: An identical CEI pattern violation was rated **Low** in Spearbit DeFi Integrations v1.2 (Jan 2025) finding 5.2.3. The Spearbit finding was confirmed by the Cantina Managed (Apr 2025) review. Per Cantina bounty rules requiring "prove the delta" and incremental impact, this finding cannot be submitted at Medium when a prior audit already identified the same pattern at Low severity.

**Impact**: A malicious withdrawer contract can reenter `dispatch()` during the ETH transfer, consuming the dispatcher balance and causing the outer call to fail with `TreasuryReceiveError`. Griefing/DOS only — no direct fund loss.

**Full finding**: [`audit/findings/F-010-reentrancy-events-cei-violation.md`](audit/findings/F-010-reentrancy-events-cei-violation.md)

---

### ⚪ Informational (2)

#### F-004 — Balance Check After External Call in \_depositValidator (Downgraded from Low)

**Summary**: The [`_depositValidator()`](src/contracts/StakingContract.sol:879) function computes a target balance _before_ the external DepositContract call and checks _after_. While not currently exploitable (DepositContract is trusted and doesn't call back), this violates checks-effects-interactions. A self-destruct forcing ETH into the contract would cause a revert (safe but fragile).

**Downgrade rationale**: This is a best-practice violation with no realistic exploit path. The DepositContract is a trusted protocol contract with no callback mechanism. The pattern is fragile but reverts safely on any mismatch. Rated Informational as a coding style recommendation.

**Full finding**: [`audit/findings/F-004-balance-check-after-external-call.md`](audit/findings/F-004-balance-check-after-external-call.md)

#### F-013 — FeeRecipient init() Front-Running (Downgraded from Low)

**Summary**: [`FeeRecipient.init()`](src/contracts/FeeRecipient.sol:19) and [`AuthorizedFeeRecipient.init()`](src/contracts/AuthorizedFeeRecipient.sol:24) are callable by anyone and can only be called once. An attacker can front-run the legitimate initialization, setting a malicious dispatcher address and permanently locking the FeeRecipient.

**Downgrade rationale**: This is a well-known pattern issue in clone/factory-based contracts. Prior audits (Spearbit Jul 2023, Quantstamp Feb 2024) documented the same init-front-running concern for FeeRecipient-like patterns. The Cantina Staking Contracts review (2025) also notes this in best-practice context. Rated Informational as a recognized limitation of the clone pattern with documented defensive patterns available.

**Full finding**: [`audit/findings/F-013-fee-recipient-init-frontrunning.md`](audit/findings/F-013-fee-recipient-init-frontrunning.md)

---

## Removed Findings (15)

| ID    | Title                              | Original Severity | Removal Reason                                                                                                                     |
| ----- | ---------------------------------- | ----------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| F-001 | Calls-Loop batch withdraw          | Medium            | Out of scope: gas consumption / DoS via unbounded loops are explicitly excluded from bounty scope                                  |
| F-002 | Calls-Loop addValidators           | Medium            | Out of scope: gas consumption / DoS via unbounded loops (same rationale as F-001)                                                  |
| F-003 | Unrestricted FeeRecipient.withdraw | Medium            | Design choice — fee dispatch is intentionally permissionless for operational flexibility; documented in prior audits               |
| F-005 | Swap-and-pop state inconsistency   | Low               | Best practice suggestion — no fund loss path; operator UX issue only                                                               |
| F-006 | Centralization risks               | Info              | Out of scope: centralization / trusted role findings are excluded from bounty scope                                                |
| F-007 | Reentrancy via receive()           | Info              | Out of scope: informational + not exploitable (DepositContract is trusted, no callback)                                            |
| F-009 | Precision loss fee calc            | Medium            | Out of scope: rounding errors / precision loss is explicitly excluded from bounty scope                                            |
| F-011 | Strict equality checks             | Low               | Best practice suggestion — no exploit path; dust griefing has gas cost barrier                                                     |
| F-012 | Self-destruct bypass               | Low               | Known EVM limitation — selfdestruct bypassing receive()/fallback() is an inherent EVM property, not a contract-level vulnerability |
| F-014 | Public access dispatch/withdraw    | Medium            | Design choice + duplicate of F-003; fee dispatch is intentionally permissionless                                                   |
| F-015 | Proxy admin centralization         | High              | Out of scope: centralization / trusted role — proxy admin is a designated trusted role; prior audits already documented this risk  |
| F-016 | Missing events                     | Medium            | Out of scope: missing events are explicitly excluded from bounty scope + duplicate of Spearbit audit findings                      |
| F-017 | Frozen dispatcher                  | Medium            | Design choice + proxy upgrade recovery is available via contract migration; no fund loss path                                      |
| F-018 | Pause bypass address(0)            | Info              | Out of scope: informational — intentional design feature for eth_call RPC compatibility                                            |
| F-019 | Slither false positives            | Info              | Out of scope: informational — tool noise, not a vulnerability                                                                      |

---

## Bounty Submission Strategy

- **Primary submission**: **F-008** (Medium 🟡) — Inconsistent Address Validation in Fee Dispatchers
  - **Only novel vulnerability** not covered in any of 11 prior audits
  - **Prior audit precedent strengthens the claim**: Halborn (Jul 2023, 5.3.5) flagged missing `_checkAddress()` in `setOperatorAddresses()`/`addOperator()` as Low — Kiln fixed those. But the same defect persists in the dispatchers' `dispatch()` functions where impact is far higher (ETH actually transferred, not just stored)
  - **Scope exclusion analysis** (see finding's dedicated section): The bug is the **missing validation**, not Admin behavior. Six non-malicious trigger scenarios (multi-sig mistakes, uninitialized operators, migrations, default returns, compromised signers, external bugs) all bypass the trusted-role exclusion at [`AUDIT_SCOPE.md:94-96`](AUDIT_SCOPE.md:94)
  - **"User Errors" exclusion rebuttal** (see finding's dedicated subsection): Five-point rebuttal arguing the "user errors" exclusion at [`AUDIT_SCOPE.md:102`](AUDIT_SCOPE.md:102) does not apply — "ultimately" requires the root cause to be user error (not missing validation), the example describes manual transfers (not automated protocol logic), no frontend can catch on-chain dispatch, prior audit precedent (Halborn 5.3.5) validates the pattern, and `_checkAddress()` existence proves developer intent
  - **Code defect framing**: [`_checkAddress()`](src/contracts/StakingContract.sol:954) exists and is used in 3 functions. Its absence in 4 others — especially `dispatch()` — proves developer oversight, not intentional design. No documentation or comments justify `address(0)` as an intended recipient
  - **Permanent ETH loss**: `address(0).call{value: X}("")` returns `(true, 0x)` — ETH is irretrievably burned with no recovery path. ~9.5+ ETH per dispatch, scales with validators × accumulated rewards
  - **Four Foundry PoC tests** confirm the burn across all three recipient roles in both dispatchers
  - **Strong candidate for up to $100,000 bounty**

- **Optional secondary**: **F-010** (Low — downgraded from Medium) — CEI Pattern Violations
  - Limited eligibility due to identical pattern already rated Low in Spearbit DeFi v1.2 (Jan 2025) finding 5.2.3
  - Best submitted as supplemental context for F-008 (demonstrates related code quality concerns in the same dispatcher contracts)

- **Not recommended for submission**: F-004, F-013 — Both downgraded to Informational, zero bounty value
