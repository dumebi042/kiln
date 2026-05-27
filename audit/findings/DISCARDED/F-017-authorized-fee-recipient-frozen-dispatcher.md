# Finding: AuthorizedFeeRecipient Frozen Dispatcher — No Update Mechanism

## Severity

**Medium** — ETH becomes permanently locked if dispatcher fails or is compromised

## Description

The [`AuthorizedFeeRecipient`](src/contracts/AuthorizedFeeRecipient.sol) contract sets its dispatcher address once during [`init()`](src/contracts/AuthorizedFeeRecipient.sol:24) and provides **no setter function** to update it afterward:

```solidity
// AuthorizedFeeRecipient.sol, lines 24-36
function init(address _dispatcher, bytes32 _publicKeyRoot) external {
    if (initialized) { revert AlreadyInitialized(); }
    initialized = true;
    dispatcher = IFeeDispatcher(_dispatcher);
    publicKeyRoot = _publicKeyRoot;
    stakingContract = msg.sender;
}
```

The `dispatcher` variable is `IFeeDispatcher` (an interface) and is only readable via the implicit getter. The `withdraw()` function forwards all ETH to this dispatcher:

```solidity
// AuthorizedFeeRecipient.sol, lines 42-47
function withdraw() external {
    if (msg.sender != stakingContract) { revert Unauthorized(); }
    uint256 balance = address(this).balance;
    if (balance == 0) { revert ZeroBalance(); }
    dispatcher.dispatch{value: balance}(publicKeyRoot);
}
```

Unlike the standard [`FeeRecipient`](src/contracts/FeeRecipient.sol) (which also lacks a setter), `AuthorizedFeeRecipient` is designed for use with a specific staking contract, making the frozen dispatcher a more significant constraint since:

1. The dispatcher is set during `init()` and can never be changed
2. The dispatcher address is passed as a parameter with no validation
3. There is no upgrade mechanism for the proxy's implementation (admin-only)

## Impact

1. **Permanent ETH Lockup**: If the dispatcher contract is compromised, paused, or self-destructed, all ETH sent to the `AuthorizedFeeRecipient` becomes permanently locked — there is no recovery path.
2. **No migration path**: If a new dispatcher is deployed (e.g., due to a bug fix or protocol upgrade), each `AuthorizedFeeRecipient` instance cannot be migrated.
3. **Single point of failure**: The correctness of fee distribution depends entirely on the dispatcher address set at initialization time.

## Proof of Concept

The [`test_no_dispatcher_update`](test/ProxyAudit.t.sol:1356) Foundry test demonstrates the constraint:

```solidity
function test_no_dispatcher_update() public {
    bytes32 publicKeyRoot = keccak256("validator_1");

    vm.startPrank(admin);
    TUPProxy afrProxy = new TUPProxy(
        address(authorizedFeeRecipient),
        admin,
        ""
    );
    vm.stopPrank();

    // init() sets the dispatcher
    vm.startPrank(stakingContract);
    AuthorizedFeeRecipient(payable(address(afrProxy))).init(
        address(dispatcher),
        publicKeyRoot
    );
    vm.stopPrank();

    // withdraw() uses the stored dispatcher
    vm.deal(address(afrProxy), 1 ether);
    vm.startPrank(stakingContract);
    AuthorizedFeeRecipient(payable(address(afrProxy))).withdraw();
    vm.stopPrank();

    // No setDispatcher() function exists
    // If dispatcher is compromised, ETH is permanently locked
}
```

## Recommended Mitigation

1. **Add a setter with access control**:

   ```solidity
   event DispatcherUpdated(address indexed oldDispatcher, address indexed newDispatcher);

   function setDispatcher(address _newDispatcher) external {
       if (msg.sender != stakingContract) { revert Unauthorized(); }
       if (_newDispatcher == address(0)) { revert InvalidAddress(); }
       address oldDispatcher = address(dispatcher);
       dispatcher = IFeeDispatcher(_newDispatcher);
       emit DispatcherUpdated(oldDispatcher, _newDispatcher);
   }
   ```

2. **Alternatively**, use the proxy upgrade mechanism to update the entire implementation in an emergency.

## Status

Open
