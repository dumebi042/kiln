# Finding: FeeRecipient init() Front-Running Vulnerability

## Severity

**Low** — No fund loss, but FeeRecipient rendered permanently unusable

## Description

The [`FeeRecipient.init()`](src/contracts/FeeRecipient.sol:19) function is callable by **anyone** after contract deployment. While it can only be called once (guarded by the `dispatcher != address(0)` check), a malicious actor can front-run the legitimate initialization:

```solidity
// FeeRecipient.sol, lines 19-27
function init(address _dispatcher, bytes32 _publicKeyRoot) external {
    if (address(dispatcher) != address(0)) {
        revert AlreadyInitialized();
    }
    dispatcher = IFeeDispatcher(_dispatcher);
    publicKeyRoot = _publicKeyRoot;
}
```

There is **no access control** on `init()` and **no way to change** the dispatcher or public key root after initialization (no setter functions exist).

If an attacker front-runs the legitimate `init()` call:

1. The legitimate `init()` reverts with `AlreadyInitialized`
2. The attacker sets a malicious dispatcher address and/or wrong public key root
3. The FeeRecipient is permanently locked — ETH sent to it can only be withdrawn through the attacker's dispatcher (which will either revert or misdirect funds)

The same vulnerability exists in [`AuthorizedFeeRecipient.init()`](src/contracts/AuthorizedFeeRecipient.sol:24), though that variant has a staking contract check.

## Impact

- **Permanent Fund Lock**: If a FeeRecipient is initialized with a malicious or incorrect dispatcher address before the legitimate init, any ETH sent to the FeeRecipient is permanently locked. The legitimate deployer cannot re-initialize the FeeRecipient.
- **Deployment DOS**: The FeeRecipient contract is deployed deterministically via CREATE2 (OpenZeppelin `Clones` library). An attacker monitoring the mempool can front-run every `init()` call, rendering all deployed FeeRecipients unusable.
- **No Recovery**: There is no `setDispatcher()`, `setPublicKeyRoot()`, or `rescueETH()` function on the FeeRecipient. If `init()` is front-run, the contract must be abandoned and a new clone deployed (at additional gas cost).

## Proof of Concept

```solidity
function test_fee_recipient_init_frontrunning() public {
    FeeRecipient freshRecipient = new FeeRecipient();

    // Attacker front-runs the legitimate init
    vm.prank(attacker);
    freshRecipient.init(address(0xBAD), PUBKEY_ROOT_1);

    // Legitimate init reverts
    vm.expectRevert(FeeRecipient.AlreadyInitialized.selector);
    freshRecipient.init(address(elDispatcher), PUBKEY_ROOT_2);
}
```

### Impact on FeeRecipient with address(0) dispatcher

If the attacker sets the dispatcher to `address(0)`, the FeeRecipient becomes a dead contract:

```solidity
function test_fee_recipient_eth_lock_no_dispatcher() public {
    FeeRecipient brokenRecipient = new FeeRecipient();
    brokenRecipient.init(address(0), PUBKEY_ROOT_1);
    vm.deal(address(brokenRecipient), 10 ether);

    // withdraw() calls IFeeDispatcher(address(0)).dispatch(...)
    // This reverts because address(0) has no code
    vm.expectRevert();
    brokenRecipient.withdraw();

    // ETH remains stuck — 10 ETH locked with no recovery path
    assertEq(address(brokenRecipient).balance, 10 ether, "ETH locked");
}
```

## Recommended Mitigation

1. **Add access control to `init()`**: Only the StakingContract (or a designated deployer) should be able to initialize the FeeRecipient:

   ```solidity
   address public immutable deployer;

   constructor() {
       deployer = msg.sender;
   }

   function init(address _dispatcher, bytes32 _publicKeyRoot) external {
       require(msg.sender == deployer, "Unauthorized");
       require(address(dispatcher) == address(0), "Already initialized");
       dispatcher = IFeeDispatcher(_dispatcher);
       publicKeyRoot = _publicKeyRoot;
   }
   ```

2. **Initialize atomically during clone deployment**: Instead of a two-step deploy-then-init process, consider a factory pattern that initializes the clone in the same transaction as deployment:

   ```solidity
   // Factory contract
   function deployFeeRecipient(address dispatcher, bytes32 pubKeyRoot) external returns (address) {
       address clone = Clones.clone(FEE_RECIPIENT_IMPLEMENTATION);
       FeeRecipient(clone).init(dispatcher, pubKeyRoot); // atomic — cannot be front-run
       return clone;
   }
   ```

3. **Add a rescue function**: Even without full access control, adding a `rescueETH()` function (only callable before `init()` or by the original deployer) would mitigate permanent fund locks.

## Status

Open
