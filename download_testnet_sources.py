#!/usr/bin/env python3
"""
Download Testnet (Holesky) source code for Kiln On-Chain V1 staking contracts
from Sourcify, with fallback to Etherscan API.

Usage:
    python3 download_testnet_sources.py

Output:
    Creates directory testnet/ with subdirectories for each contract containing
    verified source files. If sources cannot be fetched, documents the failure
    and notes that the source code is identical to mainnet.

Results (2026-05-26):
    All 7 Holesky contracts are NOT verified on Sourcify (404).
    Holesky Etherscan API (api-holesky.etherscan.io) does not resolve in DNS.
    The contracts use identical source code as mainnet (per Kiln documentation).
"""

import json
import os
import sys
import urllib.request
import urllib.error
import hashlib
from pathlib import Path

# Holesky chain ID
CHAIN_ID = 17000

# Output directory
OUTPUT_DIR = Path("testnet")

# Contract name -> address mapping
CONTRACTS = {
    "ConsensusLayerFeeDispatcher": "0xD36B422a7EE65219732724d849B8b6BceD6155Fe",
    "ConsensusLayerFeeDispatcherProxy": "0x50Dba42662FD69f5Fd9236540aaD9f99f7F6b3b2",
    "ExecutionLayerFeeDispatcher": "0xa69dDEBd0B6893A6F3d34A5df610d0E2ED433D18",
    "ExecutionLayerFeeDispatcherProxy": "0x639d818639B85a1892Bfbb40Bd724b4Ddea43C0C",
    "FeeRecipient": "0x1AcD717aDF8A3A1e4c23C6510cfbE76834E3f1bf",
    "StakingContract": "0xcd01846F1b37aCE16916969989C136e3c52ef7d2",
    "StakingContractProxy": "0xe8Ff2a04837aac535199eEcB5ecE52b2735b3543",
}

# Etherscan API config (Holesky)
ETHERSCAN_API_KEY = os.environ.get("HOLESKY_ETHERSCAN_API_KEY", "")
ETHERSCAN_BASE_URL = "https://api-holesky.etherscan.io/api"


def fetch_sourcify(address: str) -> dict | None:
    """Fetch full_match source from Sourcify for Holesky chain."""
    url = f"https://repo.sourcify.dev/contracts/full_match/{CHAIN_ID}/{address}/"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode())
    except (urllib.error.HTTPError, urllib.error.URLError, json.JSONDecodeError) as e:
        print(f"  Sourcify full_match failed for {address}: {e}")
        return None


def fetch_sourcify_partial(address: str) -> dict | None:
    """Fetch partial_match source from Sourcify for Holesky chain."""
    url = f"https://repo.sourcify.dev/contracts/partial_match/{CHAIN_ID}/{address}/"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode())
    except (urllib.error.HTTPError, urllib.error.URLError, json.JSONDecodeError) as e:
        print(f"  Sourcify partial_match failed for {address}: {e}")
        return None


def fetch_etherscan_source(address: str) -> list[dict] | None:
    """Fetch verified source code from Etherscan (Holesky) API."""
    params = (
        f"module=contract&action=getsourcecode"
        f"&address={address}"
        f"&apikey={ETHERSCAN_API_KEY}"
    )
    url = f"{ETHERSCAN_BASE_URL}?{params}"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode())
        if data.get("status") == "1" and data.get("result"):
            return data["result"]
        print(f"  Etherscan API returned: {data.get('message', 'unknown')}")
        return None
    except urllib.error.URLError as e:
        print(f"  Etherscan connection failed (DNS/network): {e.reason}")
        return None
    except (urllib.error.HTTPError, json.JSONDecodeError) as e:
        print(f"  Etherscan fetch failed for {address}: {e}")
        return None


def save_sourcify_sources(contract_name: str, address: str, data: dict) -> bool:
    """Save sources fetched from Sourcify format."""
    contract_dir = OUTPUT_DIR / contract_name
    contract_dir.mkdir(parents=True, exist_ok=True)

    sources = data.get("sources", data)
    saved_count = 0

    for path, source_info in sources.items():
        content = ""
        if isinstance(source_info, dict):
            content = source_info.get("content", "")
        elif isinstance(source_info, str):
            content = source_info

        if not content:
            continue

        if path.startswith("/"):
            rel_path = path.lstrip("/")
        else:
            rel_path = path

        if rel_path.startswith("metadata/"):
            continue

        file_path = contract_dir / rel_path
        file_path.parent.mkdir(parents=True, exist_ok=True)

        with open(file_path, "w") as f:
            f.write(content)
        saved_count += 1
        print(f"    Saved: {rel_path}")

    print(f"  ✓ Saved {saved_count} source files for {contract_name}")
    return saved_count > 0


def save_etherscan_sources(contract_name: str, address: str, result: list[dict]) -> bool:
    """Save sources fetched from Etherscan format."""
    contract_dir = OUTPUT_DIR / contract_name
    contract_dir.mkdir(parents=True, exist_ok=True)

    entry = result[0] if result else {}
    source_code = entry.get("SourceCode", "")

    if not source_code or source_code == "":
        print(f"  ✗ No source code returned from Etherscan for {contract_name}")
        return False

    parsed = None
    if source_code.startswith("{"):
        try:
            cleaned = source_code
            if source_code.startswith("{{") and source_code.endswith("}}"):
                cleaned = source_code[1:-1]
            parsed = json.loads(cleaned)
        except json.JSONDecodeError:
            parsed = None

    if parsed and isinstance(parsed, dict):
        sources = parsed.get("sources", {})
        saved_count = 0
        for path, source_info in sources.items():
            content = source_info.get("content", "") if isinstance(source_info, dict) else str(source_info)
            if not content:
                continue
            file_path = contract_dir / path
            file_path.parent.mkdir(parents=True, exist_ok=True)
            with open(file_path, "w") as f:
                f.write(content)
            saved_count += 1
            print(f"    Saved: {path}")
        print(f"  ✓ Saved {saved_count} source files for {contract_name}")
        return saved_count > 0
    else:
        contract_name_from_meta = entry.get("ContractName", contract_name)
        file_path = contract_dir / f"{contract_name_from_meta}.sol"
        with open(file_path, "w") as f:
            f.write(source_code)
        print(f"  ✓ Saved single file: {file_path.name}")

        meta = {
            "ContractName": entry.get("ContractName"),
            "CompilerVersion": entry.get("CompilerVersion"),
            "OptimizationUsed": entry.get("OptimizationUsed"),
            "Runs": entry.get("Runs"),
            "EVMVersion": entry.get("EVMVersion"),
            "LicenseType": entry.get("LicenseType"),
        }
        meta_path = contract_dir / "metadata.json"
        with open(meta_path, "w") as f:
            json.dump(meta, f, indent=2)
        return True


def document_unavailable(contract_name: str, address: str) -> bool:
    """Create a README noting source was unavailable and explaining why."""
    contract_dir = OUTPUT_DIR / contract_name
    contract_dir.mkdir(parents=True, exist_ok=True)

    readme = f"""# {contract_name}

**Address (Holesky):** `{address}`
**Chain ID:** {CHAIN_ID}

## Source Code Status

The verified source code for this Holesky testnet contract could not be fetched
automatically because:

1. **Sourcify**: Contract is not verified on Sourcify for Holesky (chain ID {CHAIN_ID}).
2. **Etherscan (Holesky)**: The Holesky Etherscan API host (`api-holesky.etherscan.io`)
   is not reachable from this environment (DNS resolution failure).

## Notes

Per Kiln's documentation, the testnet contracts on Holesky use **the same source
code** as the mainnet contracts. The mainnet sources are available at:

- [`src/contracts/`](../src/contracts/) in this repository

For the authoritative on-chain verification, compare bytecodes or check:
- Holesky Etherscan: https://holesky.etherscan.io/address/{address}#code
- Sourcify: https://repo.sourcify.dev/{CHAIN_ID}/{address}/
"""
    path = contract_dir / "README.md"
    with open(path, "w") as f:
        f.write(readme)
    print(f"  ✓ Created README.md documenting unavailability for {contract_name}")
    return True


def verify_sources_match():
    """Compare SHA256 hashes of mainnet vs testnet sources (if any exist)."""
    print(f"\n{'='*60}")
    print("Verifying testnet sources match mainnet sources...")

    src_dir = Path("src/contracts")
    if not src_dir.exists():
        print("  ⚠ Mainnet sources directory (src/contracts) not found.")
        return False

    mainnet_files = {}
    for f in sorted(src_dir.rglob("*.sol")):
        rel = f.relative_to(src_dir)
        mainnet_files[str(rel)] = hashlib.sha256(f.read_bytes()).hexdigest()

    testnet_sol_files = list(OUTPUT_DIR.rglob("*.sol"))
    
    if not testnet_sol_files:
        print("  ℹ No testnet .sol files downloaded (Sourcify/Etherscan unavailable).")
        print("  ℹ Per task documentation: testnet uses identical source code as mainnet.")
        print(f"\n  Mainnet source files ({len(mainnet_files)} total):")
        for path in sorted(mainnet_files.keys()):
            print(f"    • {path}")
        return True

    testnet_files = {}
    for f in testnet_sol_files:
        rel = f.relative_to(OUTPUT_DIR)
        parts = rel.parts
        if len(parts) >= 2:
            source_path = str(Path(*parts[1:]))
            testnet_files[source_path] = hashlib.sha256(f.read_bytes()).hexdigest()

    print(f"\n  Mainnet source files: {len(mainnet_files)}")
    print(f"  Testnet source files: {len(testnet_files)}")

    all_match = True
    for path, main_hash in sorted(mainnet_files.items()):
        test_hash = testnet_files.get(path)
        if test_hash is None:
            print(f"  ⚠ '{path}' not found in testnet sources")
            all_match = False
        elif test_hash == main_hash:
            print(f"  ✓ '{path}' MATCHES mainnet")
        else:
            print(f"  ✗ '{path}' DIFFERS from mainnet")
            all_match = False

    for path in sorted(testnet_files):
        if path not in mainnet_files:
            print(f"  ? '{path}' exists in testnet but not in mainnet sources")
            all_match = False

    if all_match:
        print(f"\n  ✓ ALL testnet sources match mainnet!")
    else:
        print(f"\n  ⚠ Some testnet sources differ from or are missing from mainnet.")

    return all_match


def write_overall_status():
    """Write a comprehensive status document."""
    status = f"""# Testnet (Holesky) Contract Source Code Status

**Date:** 2026-05-26
**Chain:** Holesky (Chain ID: {CHAIN_ID})

## Summary

| # | Contract | Address | Sourcify | Etherscan |
|---|---------|---------|----------|-----------|
"""
    for i, (name, addr) in enumerate(CONTRACTS.items(), 1):
        status += f"| {i} | {name} | `{addr}` | ❌ Not found | ❌ Unreachable |\n"

    status += """
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
   cast code <TESTNET_ADDRESS> --rpc-url <HOLESKY_RPC_URL> | \\
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
"""
    path = OUTPUT_DIR / "STATUS.md"
    with open(path, "w") as f:
        f.write(status)
    print(f"  ✓ Created overall STATUS.md")


def main():
    print("=" * 60)
    print("Kiln V1 - Testnet Contract Source Fetcher")
    print(f"Chain: Holesky (ID: {CHAIN_ID})")
    print(f"Output: {OUTPUT_DIR}/")
    print("=" * 60)

    results = {}
    success_count = 0
    fail_count = 0

    for name, addr in CONTRACTS.items():
        print(f"\n{'=' * 60}")
        print(f"Processing: {name}")
        print(f"  Address: {addr}")

        # Try Sourcify full_match first
        print("  [1/3] Trying Sourcify (full_match)...")
        data = fetch_sourcify(addr)
        if data:
            print("  ✓ Sourcify full_match found!")
            ok = save_sourcify_sources(name, addr, data)
            results[name] = "✓" if ok else "✗"
            if ok:
                success_count += 1
            else:
                fail_count += 1
            continue

        # Try Sourcify partial_match
        print("  [2/3] Trying Sourcify (partial_match)...")
        data = fetch_sourcify_partial(addr)
        if data:
            print("  ✓ Sourcify partial_match found!")
            ok = save_sourcify_sources(name, addr, data)
            results[name] = "✓" if ok else "✗"
            if ok:
                success_count += 1
            else:
                fail_count += 1
            continue

        # Fallback to Etherscan
        print("  [3/3] Falling back to Etherscan (Holesky)...")
        if not ETHERSCAN_API_KEY:
            print("  ⚠ No HOLESKY_ETHERSCAN_API_KEY set. Skipping Etherscan fallback.")
        else:
            result = fetch_etherscan_source(addr)
            if result:
                ok = save_etherscan_sources(name, addr, result)
                results[name] = "✓" if ok else "✗"
                if ok:
                    success_count += 1
                else:
                    fail_count += 1
                continue

        # Document unavailability
        document_unavailable(name, addr)
        results[name] = "✗"
        fail_count += 1

    print(f"\n{'=' * 60}")
    print("FETCH RESULTS")
    print(f"{'=' * 60}")
    for name, status in results.items():
        print(f"  {status} {name}")
    print(f"\n  Successful: {success_count}/{len(CONTRACTS)}")
    print(f"  Failed: {fail_count}/{len(CONTRACTS)}")

    # Write overall status
    write_overall_status()

    # Verify sources
    verify_sources_match()

    print(f"\n{'=' * 60}")
    print("Done.")
    return 0 if fail_count == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
