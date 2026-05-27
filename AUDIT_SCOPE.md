# Kiln On-Chain V1 — Audit Scope

## Overview

- **Program:** Kiln V1 Bounty (Cantina)
- **Protocol:** Kiln On-Chain (v1) — Non-custodial ETH staking smart contracts
- **Total Reward Pool:** $1,000,000 (hard cap of $1,500,000 across all findings)
- **Start Date:** 9 September 2024
- **Findings Submitted:** 307
- **Rewards Paid In:** USDC
- **Bounty Page:** https://cantina.xyz/bounties/607dd012-08ad-4080-bf4a-78dc1c28faa9

## Repository

- **Source Code:** https://github.com/kilnfi/staking-contracts
- **Documentation:** https://docs.kiln.fi/kiln-on-chain-v1/

## In-Scope Smart Contracts

The bug bounty is focused on the **Staking Smart Contracts only**. All items regarding dApps or validation infrastructure are out of scope.

### Mainnet

| #   | Contract                       | Address                                      | Proxy                                        |
| --- | ------------------------------ | -------------------------------------------- | -------------------------------------------- |
| 1   | Consensus Layer Fee Dispatcher | `0x462Dd07A79e5DDfBe0C171449C5c01788d5d03C3` | `0xE8EC6F702D68ded71112031D78bBFf959c7234C7` |
| 2   | Execution Layer Fee Dispatcher | `0xca4DD914fA713214844c84F153A5e1627536a7fC` | `0x72b4C52f18f52EbA3E4290a002dF7c387427b058` |
| 3   | Fee Recipient                  | `0x933fBfeb4Ed1F111D12A39c2aB48657e6fc875C6` | —                                            |
| 4   | Staking Contract               | `0x0A7272e8573aea8359FEC143ac02AED90F822bD0` | `0x1e68238ce926dec62b3fbc99ab06eb1d85ce0270` |

### Testnet (Holesky)

| #   | Contract                       | Address                                      | Proxy                                        |
| --- | ------------------------------ | -------------------------------------------- | -------------------------------------------- |
| 1   | Consensus Layer Fee Dispatcher | `0xD36B422a7EE65219732724d849B8b6BceD6155Fe` | `0x50Dba42662FD69f5Fd9236540aaD9f99f7F6b3b2` |
| 2   | Execution Layer Fee Dispatcher | `0xa69dDEBd0B6893A6F3d34A5df610d0E2ED433D18` | `0x639d818639B85a1892Bfbb40Bd724b4Ddea43C0C` |
| 3   | Fee Recipient                  | `0x1AcD717aDF8A3A1e4c23C6510cfbE76834E3f1bf` | —                                            |
| 4   | Staking Contract               | `0xcd01846F1b37aCE16916969989C136e3c52ef7d2` | `0xe8Ff2a04837aac535199eEcB5ecE52b2735b3543` |

## Severity Definitions

### Smart Contract Severity Matrix

|                        | Impact: High | Impact: Medium | Impact: Low |
| ---------------------- | ------------ | -------------- | ----------- |
| **Likelihood: High**   | **Critical** | **High**       | **Medium**  |
| **Likelihood: Medium** | **High**     | **Medium**     | —           |
| **Likelihood: Low**    | **Medium**   | —              | —           |

### Severity Descriptions

- **Critical:** Complete loss of funds or permanent freezing of funds
- **High:** Theft of unclaimed yield, commission/fees, or permanent freezing of unclaimed yield; temporary freezing of funds > 2 days (excluding potential delay due to an oracle)
- **Medium:** Smart contracts inoperable due to lack of funds; griefing or unbounded gas consumption

### PoC Requirements

A Proof of Concept is required for the following severity levels:

- **Critical** ✅
- **High** ✅
- **Medium** ✅

## Rewards

| Severity     | Reward Amount | Min Payout | Cap                          |
| ------------ | ------------- | ---------- | ---------------------------- |
| **Critical** | $1,000,000    | $100,000   | 10% of direct funds at risk  |
| **High**     | $100,000      | $20,000    | 100% of direct funds at risk |
| **Medium**   | $20,000       | $5,000     | 100% of direct funds at risk |

- The bug bounty has a **hard cap of $1,500,000**.
- In the case of multiple bug findings exceeding this amount, rewards are distributed on a **first come, first served** basis.

## Out of Scope

### General

- Consequences resulting from exploits the reporter has already carried out, which lead to damage
- Issues caused by attacks that require access to leaked keys or credentials
- Problems arising from attacks that need access to privileged roles (e.g., governance or strategist), except when the contracts are explicitly designed to prevent privileged access to functions that enable the attack
- Issues relying on attacks triggered by the depegging of an external stablecoin, unless the attacker causes the depegging due to a bug in the code
- References to secrets, access tokens, API keys, private keys, etc., that are not being used in production

### Smart Contracts

- Issues arising from incorrect data provided by third-party oracles (except oracle manipulation or flash loan attacks)
- Attacks that rely on basic economic or governance vulnerabilities (e.g., 51% attack)
- Problems related to insufficient liquidity
- Issues stemming from Sybil attacks
- Concerns involving risks of centralization
- Suggestions for best practices

### Trusted Roles

The **Operator**, **Admin**, and **Proxy Admin** are trusted to behave properly and in the best interest of users. They should not be considered as malicious. Submissions citing malicious behaviour of these roles will be considered invalid.

### Specific Types of Issues

- Informational findings
- Design choices related to protocol
- Issues that are ultimately user errors (e.g., transfers to `address(0)`)
- Rounding errors
- Relatively high gas consumption
- Extreme market turmoil vulnerability

## Known Issues

Known issues listed and acknowledged in the external audits are not eligible for any reward:

- **External Audits Notion Page:** https://kilnfi.notion.site/EXTERNAL-AUDITS-479819dce90540d1a0800c0541d2352b

## Disclosure Policy

1. Upon confirmation of a valid vulnerability, Kiln will work diligently to develop and implement a fix
2. Once the fix is deployed to production, Kiln will notify the researcher and initiate a **1-month (30 calendar days)** disclosure waiting period
3. During this waiting period, the researcher must maintain strict confidentiality
4. After the 1-month period, the researcher may publicly disclose the vulnerability with **written approval** from Kiln regarding the content
5. The researcher agrees to coordinate with Kiln on timing and content of any public disclosure

## Prohibited Actions

- Live testing on public chains (including mainnet and public testnet deployments) — use local forks (e.g., Foundry)
- Public disclosure of bugs without protocol team consent
- Denial of service attacks against project assets
- Automated testing resulting in denial of service
- Phishing or social engineering attacks against employees/customers
- Participation by employees or contractors working with Kiln (conflict of interest)

## Audit Working Directory Structure

```
audit/
├── findings/    # Audit findings/reports
├── scripts/     # Audit helper scripts
├── tests/       # Custom audit tests
└── notes/       # Audit notes and observations
```
