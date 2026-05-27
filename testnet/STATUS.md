# Testnet (Holesky) Contract Source Code Status

**Date:** 2026-05-26
**Chain:** Holesky (Chain ID: 17000)

## Summary

| # | Contract | Address | Sourcify | Etherscan |
|---|---------|---------|----------|-----------|
| 1 | ConsensusLayerFeeDispatcher | `0xD36B422a7EE65219732724d849B8b6BceD6155Fe` | ❌ Not found | ❌ Unreachable |
| 2 | ConsensusLayerFeeDispatcherProxy | `0x50Dba42662FD69f5Fd9236540aaD9f99f7F6b3b2` | ❌ Not found | ❌ Unreachable |
| 3 | ExecutionLayerFeeDispatcher | `0xa69dDEBd0B6893A6F3d34A5df610d0E2ED433D18` | ❌ Not found | ❌ Unreachable |
| 4 | ExecutionLayerFeeDispatcherProxy | `0x639d818639B85a1892Bfbb40Bd724b4Ddea43C0C` | ❌ Not found | ❌ Unreachable |
| 5 | FeeRecipient | `0x1AcD717aDF8A3A1e4c23C6510cfbE76834E3f1bf` | ❌ Not found | ❌ Unreachable |
| 6 | StakingContract | `0xcd01846F1b37aCE16916969989C136e3c52ef7d2` | ❌ Not found | ❌ Unreachable |
| 7 | StakingContractProxy | `0xe8Ff2a04837aac535199eEcB5ecE52b2735b3543` | ❌ Not found | ❌ Unreachable |

## Source Code

All testnet contracts on Holesky deploy **the same source code** as the mainnet
contracts. The mainnet source files are located in [`src/contracts/`](../src/contracts/).

## Verification

To verify bytecode equivalence between mainnet and testnet deployments:

1. Use a Holesky RPC endpoint to fetch the deployed bytecode:
   ```bash
   cast code <TESTNET_ADDRESS> --rpc-url <HOLESKY_RPC_URL>
   ```

2. Compare with mainnet bytecode:
   ```bash
   cast code <MAINNET_ADDRESS> --rpc-url <MAINNET_RPC_URL>
   ```

3. Or compare with the compiled output:
   ```bash
   cast code <TESTNET_ADDRESS> --rpc-url <HOLESKY_RPC_URL> | \
     diff - <(cat out/*.sol/*.json | jq -r '.deployedBytecode.object')
   ```

## Re-running This Script

```bash
# With Etherscan API key:
export HOLESKY_ETHERSCAN_API_KEY="your-api-key"
python3 download_testnet_sources.py

# Without API key (only tries Sourcify):
python3 download_testnet_sources.py
```
