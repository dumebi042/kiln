#!/bin/bash
set -e

echo "=== Kiln V1 Audit Tool Runner ==="
echo ""

# 1. Build
echo "🔨 Building contracts..."
forge build
echo ""

# 2. Slither
echo "🔍 Running Slither analysis..."
for contract in StakingContract ConsensusLayerFeeDispatcher ExecutionLayerFeeDispatcher FeeRecipient TUPProxy; do
    echo "  → $contract"
    slither "src/contracts/${contract}.sol" \
        --compile-force-framework foundry \
        --solc-remaps @openzeppelin/=@openzeppelin/ \
        --foundry-out-dir out \
        2>&1 | tee "audit/notes/slither-${contract}.txt"
done
echo ""

# 3. Gas Report
echo "⛽ Generating gas report..."
forge build --gas-report 2>&1 | tee audit/notes/gas-report.txt
echo ""

# 4. Summary
echo "✅ Audit tools complete."
echo "   Slither reports saved to audit/notes/slither-*.txt"
echo "   Gas report saved to audit/notes/gas-report.txt"
