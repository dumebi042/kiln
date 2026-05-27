# Discarded Findings

This directory contains findings from the Kiln V1 original audit that were **removed** after strict cross-referencing against 11 prior audit PDFs and the Cantina bounty criteria.

## Cross-Reference Sources

The following 11 prior audit PDFs were used for validation:

| #   | Source                                               | Date     |
| --- | ---------------------------------------------------- | -------- |
| 1   | Halborn                                              | 2022     |
| 2   | Spearbit                                             | Jul 2023 |
| 3   | Spearbit                                             | Apr 2024 |
| 4   | Spearbit                                             | Aug 2024 |
| 5   | Quantstamp                                           | Feb 2024 |
| 6   | Cantina Managed — Kiln Staking Contracts             | ~2024    |
| 7   | Cantina Managed — Kiln DeFi Integrations             | ~2024    |
| 8   | Cantina Managed — Kiln DeFi Integrations (duplicate) | ~2024    |
| 9   | Sigma Prime — Kiln DeFi Integrations (v2)            | ~2024    |
| 10  | Cantina Code — Kiln 1202                             | ~2025    |
| 11  | Cantina Managed                                      | Apr 2025 |

## Removal Criteria

Each finding was evaluated against:

1. **Duplication**: Already documented in one or more prior audits
2. **Out of Scope**: Gas consumption, rounding errors, missing events, centralization, informational findings — explicitly excluded from Cantina bounty scope
3. **Known Issues / EVM Limitations**: Self-destruct bypasses of `receive()`/`fallback()`, transparent proxy admin risks
4. **Best Practice Suggestions**: Coding style recommendations without exploit path
5. **Design Choices**: Permissionless fee dispatch, pause bypass for RPC compatibility

## Removed Findings (15)

| ID    | Title                              | Original Severity | Removal Reason                                       |
| ----- | ---------------------------------- | ----------------- | ---------------------------------------------------- |
| F-001 | Calls-Loop batch withdraw          | Medium            | Out of scope: gas consumption                        |
| F-002 | Calls-Loop addValidators           | Medium            | Out of scope: gas consumption                        |
| F-003 | Unrestricted FeeRecipient.withdraw | Medium            | Design choice                                        |
| F-005 | Swap-and-pop state inconsistency   | Low               | Best practice suggestion                             |
| F-006 | Centralization risks               | Info              | Out of scope: centralization                         |
| F-007 | Reentrancy via receive()           | Info              | Out of scope: informational + not exploitable        |
| F-009 | Precision loss fee calc            | Medium            | Out of scope: rounding errors                        |
| F-011 | Strict equality checks             | Low               | Best practice suggestion                             |
| F-012 | Self-destruct bypass               | Low               | Known EVM limitation                                 |
| F-014 | Public access dispatch/withdraw    | Medium            | Design choice + duplicate of F-003                   |
| F-015 | Proxy admin centralization         | High              | Out of scope: centralization + trusted role          |
| F-016 | Missing events                     | Medium            | Out of scope: missing events + duplicate of Spearbit |
| F-017 | Frozen dispatcher                  | Medium            | Design choice + proxy upgrade recovery               |
| F-018 | Pause bypass address(0)            | Info              | Out of scope: informational                          |
| F-019 | Slither false positives            | Info              | Out of scope: informational                          |

## Validation Result

After applying strict Cantina bounty criteria ("prove the delta", incremental impact only):

- **19 original findings** → **1 kept** (F-008), **3 downgraded** (F-010, F-004, F-013), **15 removed** (here)
- Only **F-008 (High)** — ETH Burned via Missing Zero-Address Checks in Fee Dispatchers — represents a novel vulnerability not covered in any prior audit
