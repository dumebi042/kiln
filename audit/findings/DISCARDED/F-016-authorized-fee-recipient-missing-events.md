# Finding: AuthorizedFeeRecipient Missing Events on Critical State Changes

## Severity

**Medium** — Off-chain monitoring cannot track critical operations

## Description

The [`AuthorizedFeeRecipient`](src/contracts/AuthorizedFeeRecipient.sol) contract performs two critical state-changing operations — initialization and withdrawal — without emitting any events:

### init() — No event emitted

```solidity
// AuthorizedFeeRecipient.sol, lines 24-32
function init(address _dispatcher, bytes32 _publicKeyRoot) external {
    if (initialized) { revert AlreadyInitialized(); }
    initialized = true;
    dispatcher = IFeeDispatcher(_dispatcher);
    publicKeyRoot = _publicKeyRoot;
    stakingContract = msg.sender;
}
```

Critical state changes performed:

- `initialized` set to `true`
- `dispatcher` address set
- `publicKeyRoot` set
- `stakingContract` (msg.sender) recorded

None of these are emitted as events.

### withdraw() — No event emitted

```solidity
// AuthorizedFeeRecipient.sol, lines 42-47
function withdraw() external {
    if (msg.sender != stakingContract) { revert Unauthorized(); }
    uint256 balance = address(this).balance;
    if (balance == 0) { revert ZeroBalance(); }
    dispatcher.dispatch{value: balance}(publicKeyRoot);
}
```

The withdrawal amount and destination are not recorded on-chain as events.

## Impact

1. **No initialization audit trail**: Cannot verify when or by whom a fee recipient was initialized on-chain without scanning all transactions.
2. **No withdrawal tracking**: Off-chain accounting systems cannot reliably track fee distributions.
3. **Incident response delay**: If a dispatcher is compromised, there is no on-chain record of which withdrawals occurred.
4. **Indexer dependency**: DApps must rely on transaction-level indexing rather than contract events.

## Proof of Concept

The [`test_missing_events_documentation`](test/ProxyAudit.t.sol:1055) Foundry test confirms no events are emitted:

```solidity
function test_missing_events_documentation() public {
    bytes32 publicKeyRoot = keccak256("validator_1");

    vm.startPrank(admin);
    TUPProxy afrProxy = new TUPProxy(
        address(authorizedFeeRecipient),
        admin,
        ""
    );
    vm.stopPrank();

    vm.startPrank(stakingContract);
    AuthorizedFeeRecipient(payable(address(afrProxy))).init(
        address(dispatcher),
        publicKeyRoot
    );
    vm.stopPrank();

    // Same for withdraw - no event is emitted
    vm.deal(address(afrProxy), 1 ether);
    vm.startPrank(stakingContract);
    AuthorizedFeeRecipient(payable(address(afrProxy))).withdraw();
    vm.stopPrank();
}
```

The test passes — no events are emitted during init() or withdraw().

## Recommended Mitigation

Add events to both functions:

```solidity
event Initialized(
    address indexed stakingContract,
    address indexed dispatcher,
    bytes32 publicKeyRoot
);

event Withdrawn(
    address indexed stakingContract,
    address indexed dispatcher,
    uint256 amount,
    bytes32 publicKeyRoot
);

function init(address _dispatcher, bytes32 _publicKeyRoot) external {
    if (initialized) { revert AlreadyInitialized(); }
    initialized = true;
    dispatcher = IFeeDispatcher(_dispatcher);
    publicKeyRoot = _publicKeyRoot;
    stakingContract = msg.sender;
    emit Initialized(msg.sender, _dispatcher, _publicKeyRoot);
}

function withdraw() external {
    if (msg.sender != stakingContract) { revert Unauthorized(); }
    uint256 balance = address(this).balance;
    if (balance == 0) { revert ZeroBalance(); }
    dispatcher.dispatch{value: balance}(publicKeyRoot);
    emit Withdrawn(msg.sender, address(dispatcher), balance, publicKeyRoot);
}
```

## Status

Open
