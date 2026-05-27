# Finding: Unauthorized dispatch() and withdraw() — Public Access

## Severity

**Medium** — Anyone can trigger fee distribution at any time

## Description

The [`dispatch()`](src/contracts/ConsensusLayerFeeDispatcher.sol:59) function in both dispatchers and the [`withdraw()`](src/contracts/FeeRecipient.sol:42) function in FeeRecipient have **no access control**. Any external caller can invoke these functions at any time:

```solidity
// FeeRecipient.sol, lines 42-49 — no access control
function withdraw() external {
    IFeeDispatcher _dispatcher = dispatcher;
    dispatcher = IFeeDispatcher(address(0)); // CEI: set to 0 before external call
    _dispatcher.dispatch{value: address(this).balance}(publicKeyRoot);
}

// ConsensusLayerFeeDispatcher.sol, lines 59-119 — no access control
function dispatch(bytes32 _publicKeyRoot) external payable {
    // ... computes fees, sends ETH, emits event
}
```

While the protocol is designed to allow permissionless dispatch (anyone can trigger fee distribution for any validator), this design has security and operational implications:

- The [`FeeRecipient.withdraw()`](src/contracts/FeeRecipient.sol:42) function uses a **dispatcher = address(0)** pattern before making the external call. This correctly sets the dispatcher to zero before the external call (following CEI), preventing reentrancy from calling `withdraw()` again on the same FeeRecipient. However, anyone can trigger it.

- The `dispatch()` function is `payable` and `external` — anyone can call it with or without attached ETH. However, fees are computed on `address(this).balance` (not `msg.value`), so attaching ETH to a `dispatch()` call does not increase the fee base.

## Impact

- **Premature Fee Distribution**: A third party can trigger fee withdrawal at any time, potentially at unfavorable gas prices or market conditions for the withdrawer/operator.
- **Gas Griefing**: An attacker could repeatedly trigger dispatches on validators with minimal balances, forcing the withdrawer to receive dust amounts while the attacker pays gas. The attacker loses gas but the withdrawer receives negligible value.
- **Operational Disruption**: The timing of fee distribution affects the withdrawer's and operator's cash flows. Permissionless dispatch removes their ability to schedule distributions optimally.
- **No Direct Fund Loss**: The `dispatch()` function correctly distributes all ETH in the dispatcher. There is no theft path — the funds go to the intended recipients (withdrawer, treasury, operator) regardless of who triggers the dispatch.

## Proof of Concept

### Anyone can call withdraw() on any FeeRecipient

```solidity
function test_unauthorized_dispatch() public {
    // Anyone can call withdraw() on FeeRecipient
    vm.deal(address(feeRecipient), 1 ether);
    vm.prank(attacker);
    feeRecipient.withdraw();
    assertEq(address(feeRecipient).balance, 0, "FeeRecipient drained by anyone");

    // Anyone can call dispatch() directly on the dispatcher
    vm.deal(address(clDispatcher), 1 ether);
    vm.prank(attacker);
    clDispatcher.dispatch(PUBKEY_ROOT_1);
    assertEq(address(clDispatcher).balance, 0, "CL Dispatcher drained by anyone");
}
```

### Zero-balance dispatch correctly reverts

```solidity
function test_unauthorized_dispatch_zero_balance() public {
    vm.prank(attacker);
    vm.expectRevert(ConsensusLayerFeeDispatcher.ZeroBalanceWithdrawal.selector);
    clDispatcher.dispatch(PUBKEY_ROOT_1);
}
```

## Recommended Mitigation

1. **Accept as design choice**: Permissionless dispatch is a deliberate design decision that maximizes protocol accessibility. If this is intentional, document it clearly in the contract interface and operational guides.

2. **Consider time-locked dispatch**: If more control is desired, add a minimum time interval between dispatches for the same validator:

   ```solidity
   mapping(bytes32 => uint256) public lastDispatchTime;
   uint256 public constant MIN_DISPATCH_INTERVAL = 1 days;

   function dispatch(bytes32 _publicKeyRoot) external payable {
       require(
           block.timestamp >= lastDispatchTime[_publicKeyRoot] + MIN_DISPATCH_INTERVAL,
           "Dispatch too soon"
       );
       lastDispatchTime[_publicKeyRoot] = block.timestamp;
       // ... rest of dispatch logic
   }
   ```

3. **Use AuthorizedFeeRecipient**: Replace `FeeRecipient` with [`AuthorizedFeeRecipient`](src/contracts/AuthorizedFeeRecipient.sol) which restricts `withdraw()` to the StakingContract only. This at least prevents third-party triggering of the withdrawal flow, though `dispatch()` on the dispatchers would still be public.

## Status

Open
