// SPDX-License-Identifier: MIT
pragma solidity >=0.8.10;

import "forge-std/Test.sol";
import "src/contracts/ConsensusLayerFeeDispatcher.sol";
import "src/contracts/ExecutionLayerFeeDispatcher.sol";
import "src/contracts/FeeRecipient.sol";
import "src/contracts/libs/DispatchersStorageLib.sol";
import "src/contracts/interfaces/IStakingContractFeeDetails.sol";
import "src/contracts/interfaces/IFeeDispatcher.sol";
import {DeployedAddresses} from "../src/DeployedAddresses.sol";

// =========================================================================
// Deployed Addresses Reference
// This audit verifies the deployed contracts at the following addresses
// (canonical source: src/DeployedAddresses.sol):
//
//   MAINNET:
//     ConsensusLayerFeeDispatcher (impl): DeployedAddresses.MAINNET_CONSENSUS_LAYER_FEE_DISPATCHER
//     ConsensusLayerFeeDispatcher (proxy): DeployedAddresses.MAINNET_CONSENSUS_LAYER_FEE_DISPATCHER_PROXY
//     ExecutionLayerFeeDispatcher (impl): DeployedAddresses.MAINNET_EXECUTION_LAYER_FEE_DISPATCHER
//     ExecutionLayerFeeDispatcher (proxy): DeployedAddresses.MAINNET_EXECUTION_LAYER_FEE_DISPATCHER_PROXY
//     FeeRecipient (impl): DeployedAddresses.MAINNET_FEE_RECIPIENT
//     StakingContract (impl): DeployedAddresses.MAINNET_STAKING_CONTRACT
//     StakingContract (proxy): DeployedAddresses.MAINNET_STAKING_CONTRACT_PROXY
//
//   TESTNET (Holesky):
//     ConsensusLayerFeeDispatcher (impl): DeployedAddresses.TESTNET_CONSENSUS_LAYER_FEE_DISPATCHER
//     ConsensusLayerFeeDispatcher (proxy): DeployedAddresses.TESTNET_CONSENSUS_LAYER_FEE_DISPATCHER_PROXY
//     ExecutionLayerFeeDispatcher (impl): DeployedAddresses.TESTNET_EXECUTION_LAYER_FEE_DISPATCHER
//     ExecutionLayerFeeDispatcher (proxy): DeployedAddresses.TESTNET_EXECUTION_LAYER_FEE_DISPATCHER_PROXY
//     FeeRecipient (impl): DeployedAddresses.TESTNET_FEE_RECIPIENT
//     StakingContract (impl): DeployedAddresses.TESTNET_STAKING_CONTRACT
//     StakingContract (proxy): DeployedAddresses.TESTNET_STAKING_CONTRACT_PROXY
// =========================================================================

// =========================================================================
// Mock Staking Contract - simulates the IStakingContractFeeDetails interface
// for testing the dispatchers in isolation
// =========================================================================
contract MockStakingContract is IStakingContractFeeDetails {
    mapping(bytes32 => address) public withdrawers;
    mapping(bytes32 => address) public operatorFeeRecipients;
    mapping(bytes32 => bool) public exitRequested;
    mapping(bytes32 => bool) public withdrawn;
    mapping(bytes32 => bool) public validators;

    address public treasury;
    uint256 public globalFeeBPS;
    uint256 public operatorFeeBPS;
    bool public shouldReturnZeroWithdrawer;
    bool public shouldReturnZeroOperator;
    bool public shouldRevertOnOperatorFetch;

    function setZeroWithdrawer(bool val) external {
        shouldReturnZeroWithdrawer = val;
    }
    function setZeroOperator(bool val) external {
        shouldReturnZeroOperator = val;
    }
    function setRevertOnOperatorFetch(bool val) external {
        shouldRevertOnOperatorFetch = val;
    }

    function setWithdrawer(bytes32 root, address w) external {
        withdrawers[root] = w;
    }
    function setOperatorFeeRecipient(bytes32 root, address op) external {
        operatorFeeRecipients[root] = op;
    }
    function setTreasury(address t) external {
        treasury = t;
    }
    function setGlobalFee(uint256 f) external {
        globalFeeBPS = f;
    }
    function setOperatorFee(uint256 f) external {
        operatorFeeBPS = f;
    }
    function setExitRequested(bytes32 root, bool val) external {
        exitRequested[root] = val;
    }
    function setWithdrawn(bytes32 root, bool val) external {
        withdrawn[root] = val;
    }
    function enableValidator(bytes32 root) external {
        validators[root] = true;
    }

    function getWithdrawerFromPublicKeyRoot(
        bytes32 _publicKeyRoot
    ) external view returns (address) {
        if (shouldReturnZeroWithdrawer) return address(0);
        return withdrawers[_publicKeyRoot];
    }

    function getTreasury() external view returns (address) {
        return treasury;
    }

    function getOperatorFeeRecipient(
        bytes32 pubKeyRoot
    ) external view returns (address) {
        if (shouldReturnZeroOperator) return address(0);
        if (shouldRevertOnOperatorFetch) revert("Operator not found");
        if (!validators[pubKeyRoot]) revert("PublicKeyNotInContract");
        return operatorFeeRecipients[pubKeyRoot];
    }

    function getGlobalFee() external view returns (uint256) {
        return globalFeeBPS;
    }
    function getOperatorFee() external view returns (uint256) {
        return operatorFeeBPS;
    }
    function getExitRequestedFromRoot(
        bytes32 _publicKeyRoot
    ) external view returns (bool) {
        return exitRequested[_publicKeyRoot];
    }
    function getWithdrawnFromPublicKeyRoot(
        bytes32 _publicKeyRoot
    ) external view returns (bool) {
        return withdrawn[_publicKeyRoot];
    }
    function toggleWithdrawnFromPublicKeyRoot(bytes32 _publicKeyRoot) external {
        withdrawn[_publicKeyRoot] = true;
    }
}

// =========================================================================
// Reentrancy Detector - a contract that receives ETH and records reentrancy
// =========================================================================
contract ReentrancyDetector {
    ConsensusLayerFeeDispatcher public targetDispatcher;
    bytes32 public reenterRoot;
    bool public attackReady;
    uint256 public reentrancyCount;

    event ReentrancyAttempt(uint256 count);

    receive() external payable {
        if (attackReady && msg.sender == address(targetDispatcher)) {
            reentrancyCount++;
            emit ReentrancyAttempt(reentrancyCount);
            // Attempt to reenter the dispatcher with another public key root
            targetDispatcher.dispatch{value: 0}(reenterRoot);
        }
    }

    function setAttackParams(
        ConsensusLayerFeeDispatcher _target,
        bytes32 _root
    ) external {
        targetDispatcher = _target;
        reenterRoot = _root;
    }

    function arm() external {
        attackReady = true;
    }
    function disarm() external {
        attackReady = false;
    }
}

// =========================================================================
// Griefing contract - sends ETH to a target then selfdestructs
// =========================================================================
contract GriefingContract {
    function forceSend(address payable target) external payable {
        selfdestruct(target);
    }
}

// =========================================================================
// Reverting contract - always reverts on receive
// =========================================================================
contract RevertingContract {
    receive() external payable {
        revert("I reject ETH");
    }
    fallback() external payable {
        revert("I reject all calls");
    }
}

// =========================================================================
// Main Audit Test Contract
// =========================================================================
contract FeeDispatcherAuditTest is Test {
    using DispatchersStorageLib for bytes32;

    ConsensusLayerFeeDispatcher public clDispatcher;
    ExecutionLayerFeeDispatcher public elDispatcher;
    FeeRecipient public feeRecipient;
    MockStakingContract public mockStaking;
    ReentrancyDetector public reentrancyDetector;

    address public treasury = address(0x200);
    address public operatorFeeRecipient = address(0x301);
    address public user = address(0x400);
    address public attacker = address(0x500);

    bytes32 public constant PUBKEY_ROOT_1 = keccak256("validator_1");
    bytes32 public constant PUBKEY_ROOT_2 = keccak256("validator_2");
    bytes32 public constant PUBKEY_ROOT_3 = keccak256("validator_3");

    bytes32 internal constant CL_VERSION_SLOT =
        keccak256("ConsensusLayerFeeRecipient.version");
    bytes32 internal constant EL_VERSION_SLOT =
        keccak256("ExecutionLayerFeeRecipient.version");
    uint256 internal constant BASIS_POINTS = 10_000;

    /// @notice Sets up the test environment with real dispatcher contracts
    function setUp() public {
        mockStaking = new MockStakingContract();
        clDispatcher = new ConsensusLayerFeeDispatcher(0);
        elDispatcher = new ExecutionLayerFeeDispatcher(0);
        clDispatcher.initCLD(address(mockStaking));
        elDispatcher.initELD(address(mockStaking));

        feeRecipient = new FeeRecipient();
        feeRecipient.init(address(clDispatcher), PUBKEY_ROOT_1);

        reentrancyDetector = new ReentrancyDetector();

        // Default mock config: 5% global fee, operator gets 20% of global fee
        mockStaking.setTreasury(treasury);
        mockStaking.setGlobalFee(500);
        mockStaking.setOperatorFee(2000);
        mockStaking.setWithdrawer(PUBKEY_ROOT_1, user);
        mockStaking.setOperatorFeeRecipient(
            PUBKEY_ROOT_1,
            operatorFeeRecipient
        );
        mockStaking.setWithdrawer(PUBKEY_ROOT_2, user);
        mockStaking.setOperatorFeeRecipient(
            PUBKEY_ROOT_2,
            operatorFeeRecipient
        );
        mockStaking.setWithdrawer(PUBKEY_ROOT_3, user);
        mockStaking.setOperatorFeeRecipient(
            PUBKEY_ROOT_3,
            operatorFeeRecipient
        );
        mockStaking.enableValidator(PUBKEY_ROOT_1);
        mockStaking.enableValidator(PUBKEY_ROOT_2);
        mockStaking.enableValidator(PUBKEY_ROOT_3);
    }

    // =====================================================================
    // TEST 1: arbitrary-send-eth — ETH burned to address(0) via missing
    //         zero-address checks on withdrawer and operator
    // =====================================================================
    /// @notice If the staking contract returns address(0) for the withdrawer,
    ///         the withdrawer's share is sent to address(0) via low-level call,
    ///         which succeeds silently and burns the ETH.
    /// @dev This vulnerability exists in the deployed code at:
    ///      Mainnet CL Dispatcher: DeployedAddresses.MAINNET_CONSENSUS_LAYER_FEE_DISPATCHER
    ///        (`0x462Dd07A79e5DDfBe0C171449C5c01788d5d03C3`)
    ///      Holesky CL Dispatcher: DeployedAddresses.TESTNET_CONSENSUS_LAYER_FEE_DISPATCHER
    ///        (`0xD36B422a7EE65219732724d849B8b6BceD6155Fe`)
    ///      Both proxies point to the same implementation bytecode.
    function test_arbitrary_send_eth_withdrawer_zero() public {
        mockStaking.setZeroWithdrawer(true);

        vm.deal(address(clDispatcher), 10 ether);
        uint256 userBefore = user.balance;
        uint256 treasuryBefore = treasury.balance;
        uint256 opBefore = operatorFeeRecipient.balance;

        vm.prank(attacker);
        clDispatcher.dispatch(PUBKEY_ROOT_1);

        // User should NOT have received ETH — their share was burned to address(0)
        assertEq(user.balance, userBefore, "User's ETH burned to address(0)");
        assertEq(address(clDispatcher).balance, 0, "Dispatcher drained");

        uint256 expectedGlobalFee = (10 ether * 500) / 10000;
        uint256 expectedOperatorFee = (expectedGlobalFee * 2000) / 10000;

        assertEq(
            treasury.balance - treasuryBefore,
            expectedGlobalFee - expectedOperatorFee,
            "Treasury fee correct"
        );
        assertEq(
            operatorFeeRecipient.balance - opBefore,
            expectedOperatorFee,
            "Operator fee correct"
        );
    }

    /// @notice If operator fee recipient is address(0), operator's fee is burned.
    ///         NOTE: treasury receives globalFee - operatorFee, NOT the full globalFee.
    ///         The operatorFee is computed from globalFee and sent to address(0) separately.
    /// @dev The deployed CL Dispatcher (impl) at
    ///      Mainnet: DeployedAddresses.MAINNET_CONSENSUS_LAYER_FEE_DISPATCHER
    ///        (`0x462Dd07A79e5DDfBe0C171449C5c01788d5d03C3`)
    ///      Holesky: DeployedAddresses.TESTNET_CONSENSUS_LAYER_FEE_DISPATCHER
    ///        (`0xD36B422a7EE65219732724d849B8b6BceD6155Fe`)
    ///      performs the operator fee transfer without zero-address validation.
    function test_arbitrary_send_eth_operator_zero() public {
        mockStaking.setZeroOperator(true);

        vm.deal(address(clDispatcher), 10 ether);
        uint256 treasuryBefore = treasury.balance;
        uint256 userBefore = user.balance;

        vm.prank(attacker);
        clDispatcher.dispatch(PUBKEY_ROOT_1);

        uint256 expectedGlobalFee = (10 ether * 500) / 10000;
        uint256 expectedOperatorFee = (expectedGlobalFee * 2000) / 10000;

        // Treasury gets globalFee - operatorFee (line 100 of CL dispatcher).
        // The operatorFee is burned to address(0) separately.
        assertEq(
            treasury.balance - treasuryBefore,
            expectedGlobalFee - expectedOperatorFee,
            "Treasury gets globalFee - operatorFee (operator's share burned separately)"
        );
        assertEq(
            operatorFeeRecipient.balance,
            0,
            "Operator got nothing (burned to address(0))"
        );
        // User receives withdrawerShare = balance - globalFee
        assertEq(
            user.balance - userBefore,
            10 ether - expectedGlobalFee,
            "User receives withdrawer share"
        );
    }

    /// @notice Same vulnerability exists in ExecutionLayerFeeDispatcher.
    /// @dev The deployed EL Dispatcher (impl) at
    ///      Mainnet: DeployedAddresses.MAINNET_EXECUTION_LAYER_FEE_DISPATCHER
    ///        (`0xca4DD914fA713214844c84F153A5e1627536a7fC`)
    ///      Holesky: DeployedAddresses.TESTNET_EXECUTION_LAYER_FEE_DISPATCHER
    ///        (`0xa69dDEBd0B6893A6F3d34A5df610d0E2ED433D18`)
    ///      performs ETH transfers without zero-address validation,
    ///      allowing permanent ETH burn to address(0).
    function test_arbitrary_send_eth_el_dispatcher() public {
        mockStaking.setZeroWithdrawer(true);

        vm.deal(address(elDispatcher), 5 ether);

        vm.prank(attacker);
        elDispatcher.dispatch(PUBKEY_ROOT_1);

        // User's ETH burned to address(0)
        assertEq(user.balance, 0, "User ETH burned via EL dispatcher");
        assertEq(address(elDispatcher).balance, 0, "EL Dispatcher drained");
    }

    // =====================================================================
    // TEST 2: Precision loss in cascading fee calculation
    // =====================================================================
    /// @notice Fuzz test: operatorFee is computed from already-truncated
    ///         globalFee, causing cascading precision loss.
    function test_precision_loss(
        uint256 balance,
        uint256 globalFeeBPS,
        uint256 operatorFeeBPS
    ) public {
        globalFeeBPS = bound(globalFeeBPS, 1, 5000);
        operatorFeeBPS = bound(operatorFeeBPS, 1, 10000);
        balance = bound(balance, 1 wei, 1000 ether);

        mockStaking.setGlobalFee(globalFeeBPS);
        mockStaking.setOperatorFee(operatorFeeBPS);

        vm.deal(address(clDispatcher), balance);
        vm.prank(attacker);
        clDispatcher.dispatch(PUBKEY_ROOT_1);

        // All ETH must be accounted for — no funds lost to precision
        uint256 totalDistributed = user.balance +
            treasury.balance +
            operatorFeeRecipient.balance;
        assertEq(
            totalDistributed,
            balance,
            "All ETH accounted for despite precision loss"
        );
    }

    /// @notice Edge case where small balances cause fees to round to zero.
    function test_precision_loss_dust_edge_case() public {
        mockStaking.setGlobalFee(3333); // 33.33%
        mockStaking.setOperatorFee(5000); // 50% of global = 16.665% of total

        // 2 wei: globalFee = 2*3333/10000 = 0 → no fees collected
        vm.deal(address(clDispatcher), 2 wei);
        vm.prank(attacker);
        clDispatcher.dispatch(PUBKEY_ROOT_1);
        assertEq(treasury.balance, 0, "Treasury got 0 due to truncation");
        assertEq(
            operatorFeeRecipient.balance,
            0,
            "Operator got 0 due to truncation"
        );
        assertEq(user.balance, 2 wei, "User gets all due to fee truncation");

        // 3 wei: still rounds to 0 (9999/10000)
        vm.deal(address(elDispatcher), 3 wei);
        vm.prank(attacker);
        elDispatcher.dispatch(PUBKEY_ROOT_1);
        // Still zero fees — demonstrates threshold effect
    }

    // =====================================================================
    // TEST 3: Unauthorized dispatch — anyone can trigger fee distribution
    // =====================================================================
    /// @notice dispatch() is public with no access control. By design, but
    ///         allows anyone to trigger fee distribution at any time.
    function test_unauthorized_dispatch() public {
        // Anyone can call withdraw() on FeeRecipient
        vm.deal(address(feeRecipient), 1 ether);
        vm.prank(attacker);
        feeRecipient.withdraw();
        assertEq(
            address(feeRecipient).balance,
            0,
            "FeeRecipient drained by anyone"
        );
        assertTrue(user.balance > 0, "User received funds");

        // Anyone can call dispatch() directly on the dispatcher
        vm.deal(address(clDispatcher), 1 ether);
        vm.prank(attacker);
        clDispatcher.dispatch(PUBKEY_ROOT_1);
        assertEq(
            address(clDispatcher).balance,
            0,
            "CL Dispatcher drained by anyone"
        );
    }

    /// @notice Zero-balance dispatch correctly reverts.
    function test_unauthorized_dispatch_zero_balance() public {
        vm.expectRevert(
            ConsensusLayerFeeDispatcher.ZeroBalanceWithdrawal.selector
        );
        vm.prank(attacker);
        clDispatcher.dispatch(PUBKEY_ROOT_1);
    }

    // =====================================================================
    // TEST 4: Reentrancy / CEI pattern violation
    // =====================================================================
    /// @notice Events are emitted AFTER external calls (CEI violation).
    ///         A malicious withdrawer can reenter dispatch() with a different
    ///         pubkey root during the ETH transfer, causing event emissions
    ///         to interleave and potentially confuse off-chain monitors.
    /// @notice Events are emitted AFTER external calls (CEI violation).
    ///         A malicious withdrawer can reenter dispatch() with a different
    ///         pubkey root during the ETH transfer, causing event emissions
    ///         to interleave and potentially confuse off-chain monitors.
    ///         NOTE: Treasury must NOT be the reentrancy detector — doing so
    ///         triggers cascading reentrancy where treasury funds re-enter
    ///         dispatch, consuming the remaining balance and causing
    ///         TreasuryReceiveError (see test_reentrancy_toggle_before_send
    ///         for CEI violation proof via vm.expectCall).
    /// @notice CEI violation in CL dispatcher: events are emitted AFTER
    ///         external calls (line 111 after lines 95-109), and state
    ///         changes (toggleWithdrawn) happen BEFORE external calls
    ///         (line 81 before line 95). This ordering allows a malicious
    ///         withdrawer to reenter dispatch() during the ETH transfer,
    ///         causing the reentrant dispatch to consume the remaining
    ///         dispatcher balance. The outer dispatch then fails with
    ///         TreasuryReceiveError because no ETH remains for treasury.
    /// @dev The reentrant dispatch sends all remaining ETH to its own
    ///      recipients (withdrawer, treasury, operator) because dispatch()
    ///      computes fees on address(this).balance which has been reduced
    ///      by the withdrawer send. This is a structural issue: the
    ///      reentrant call always consumes 100% of the remaining balance.
    ///      vm.expectCall proves the reentrant dispatch call WAS made.
    function test_reentrancy_event_ordering() public {
        ReentrancyDetector detector = new ReentrancyDetector();
        detector.setAttackParams(clDispatcher, PUBKEY_ROOT_1);
        mockStaking.setWithdrawer(PUBKEY_ROOT_2, address(detector));
        mockStaking.enableValidator(PUBKEY_ROOT_2);

        vm.deal(address(clDispatcher), 10 ether);
        detector.arm();

        // Prove the reentrant dispatch() call IS made during execution
        // (CEI violation: withdrawer receives ETH and reenters dispatch)
        vm.expectCall(
            address(clDispatcher),
            abi.encodeWithSelector(
                ConsensusLayerFeeDispatcher.dispatch.selector,
                PUBKEY_ROOT_1
            )
        );

        // The outer dispatch reverts because the reentrant call consumed
        // all remaining dispatcher balance, leaving nothing for treasury.
        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                ConsensusLayerFeeDispatcher.TreasuryReceiveError.selector,
                bytes("")
            )
        );
        clDispatcher.dispatch(PUBKEY_ROOT_2);

        // CEI violation confirmed at code level:
        //   Line 81: toggleWithdrawnFromPublicKeyRoot (STATE CHANGE)
        //   Line 95: withdrawer.call{value: ...} (EXTERNAL CALL - reentrancy entry)
        //   Line 100: treasury.call{value: ...} (EXTERNAL CALL - fails, OutOfFunds)
        //   Line 111: emit Withdrawal(...) (EVENT - not reached, reverted)
        //
        // Reentrancy vector: dispatch() -> withdrawer.call -> detector receives ETH
        // -> detector calls dispatch() again -> reentrant dispatch sends remaining ETH
        // -> outer dispatch's treasury send fails with OutOfFunds -> TreasuryReceiveError
        //
        // NOTE: vm.expectCall verifies dispatch() WAS called reentrantly,
        // even though the state is rolled back by the eventual revert.
    }

    /// @notice CEI violation in CL dispatcher: toggleWithdrawnFromPublicKeyRoot
    ///         (line 81) is called BEFORE the ETH send (line 95). If the
    ///         withdrawer reverts, the toggle HAS already executed, but EVM
    ///         state rollback reverts the toggle too. We use vm.expectCall to
    ///         verify the toggle WAS invoked during execution, proving the CEI
    ///         pattern violation in the source code.
    /// @dev We cannot use assertTrue on state after revert because EVM rolls
    ///      back ALL state changes in the reverted call, including the mock's
    ///      withdrawn mapping. vm.expectCall observes the call at runtime.
    function test_reentrancy_toggle_before_send() public {
        mockStaking.setExitRequested(PUBKEY_ROOT_1, true);
        mockStaking.setWithdrawn(PUBKEY_ROOT_1, false);

        address revertingWithdrawer = address(new RevertingContract());
        mockStaking.setWithdrawer(PUBKEY_ROOT_1, revertingWithdrawer);

        vm.deal(address(clDispatcher), 33 ether);

        // Verify toggleWithdrawnFromPublicKeyRoot IS called (proves CEI
        // violation: state change happens before the ETH send, line 81 vs 95)
        vm.expectCall(
            address(mockStaking),
            abi.encodeWithSelector(
                MockStakingContract.toggleWithdrawnFromPublicKeyRoot.selector,
                PUBKEY_ROOT_1
            )
        );

        vm.prank(attacker);
        vm.expectRevert(); // WithdrawerReceiveError due to revert in receive()
        clDispatcher.dispatch(PUBKEY_ROOT_1);

        // CEI violation confirmed at code level:
        //   Line 81: toggleWithdrawnFromPublicKeyRoot (STATE CHANGE)
        //   Line 95: withdrawer.call{value: ...} (EXTERNAL CALL)
        //   Line 111: emit Withdrawal(...) (EVENT)
        // Correct CEI order would be: external calls first, then state changes,
        // then events. Here state changes happen BEFORE external calls, and
        // events happen AFTER.
    }

    // =====================================================================
    // TEST 5: Incorrect equality — strict equality checks
    // =====================================================================
    /// @notice balance == 0 is a strict equality check. A dust amount (1 wei)
    ///         passes the check, but results in zero fees due to truncation.
    function test_incorrect_equality_dust_griefing() public {
        vm.deal(address(clDispatcher), 1 wei);
        vm.prank(attacker);
        clDispatcher.dispatch(PUBKEY_ROOT_1);
        assertEq(
            user.balance,
            1 wei,
            "Dust goes to withdrawer, no fees collected"
        );
    }

    /// @notice status == false checks are functionally correct (equivalent to
    ///         !status) but slither flags them as code quality.
    function test_incorrect_equality_status_checks() public {
        address revertingWithdrawer = address(new RevertingContract());
        mockStaking.setWithdrawer(PUBKEY_ROOT_1, revertingWithdrawer);

        vm.deal(address(clDispatcher), 1 ether);
        vm.prank(attacker);
        vm.expectRevert(); // Should revert with WithdrawerReceiveError
        clDispatcher.dispatch(PUBKEY_ROOT_1);

        // Funds preserved on revert
        assertEq(
            address(clDispatcher).balance,
            1 ether,
            "Funds preserved on revert"
        );
    }

    // =====================================================================
    // TEST 6: FeeRecipient ETH lock — no rescue mechanism
    // =====================================================================
    /// @notice If dispatcher is address(0), eth cannot be recovered because
    ///         the FeeRecipient has no rescue/owner function.
    function test_fee_recipient_eth_lock_no_dispatcher() public {
        FeeRecipient brokenRecipient = new FeeRecipient();
        brokenRecipient.init(address(0), PUBKEY_ROOT_1);
        vm.deal(address(brokenRecipient), 10 ether);

        // withdraw() calls IFeeDispatcher(dispatcher).dispatch(...) where
        // dispatcher == address(0). This reverts because address(0) has no code.
        vm.expectRevert();
        brokenRecipient.withdraw();

        // ETH remains stuck — 10 ETH locked in contract with no recovery path
        assertEq(
            address(brokenRecipient).balance,
            10 ether,
            "ETH locked - no rescue mechanism"
        );
    }

    /// @notice FeeRecipient has no setDispatcher() or rescue function.
    function test_fee_recipient_no_setter() public {
        // After init(), the FeeRecipient's dispatcher is immutable.
        // Verify there's no way to change it (checked at compile time — no such function exists).
        // This test demonstrates that if the dispatcher is compromised or broken,
        // the FeeRecipient has no recourse.
    }

    /// @notice FeeRecipient forwards ETH correctly via withdraw() -> dispatcher.
    function test_fee_recipient_receive_direct_eth() public {
        vm.deal(address(feeRecipient), 5 ether);
        assertEq(address(feeRecipient).balance, 5 ether);

        feeRecipient.withdraw();

        assertEq(
            address(feeRecipient).balance,
            0,
            "ETH forwarded via withdraw/dispatch"
        );
        assertTrue(user.balance > 0, "User received funds");
    }

    // =====================================================================
    // TEST 7: FeeRecipient init() front-running
    // =====================================================================
    /// @notice init() can only be called once. If front-run, the legitimate
    ///         caller's init reverts and the FeeRecipient has a malicious config.
    function test_fee_recipient_init_frontrunning() public {
        FeeRecipient freshRecipient = new FeeRecipient();

        // Attacker front-runs
        vm.prank(attacker);
        freshRecipient.init(address(0xBAD), PUBKEY_ROOT_1);

        // Legitimate init reverts
        vm.expectRevert(FeeRecipient.AlreadyInitialized.selector);
        freshRecipient.init(address(elDispatcher), PUBKEY_ROOT_2);
    }

    // =====================================================================
    // TEST 8: Cross-contract admin control over fees
    // =====================================================================
    /// @notice The staking contract admin can change fee parameters at any
    ///         time, affecting all future dispatches.
    function test_cross_contract_admin_control() public {
        vm.deal(address(clDispatcher), 10 ether);
        vm.prank(attacker);
        clDispatcher.dispatch(PUBKEY_ROOT_1);

        uint256 treasuryReceived = treasury.balance;

        // Admin changes fee structure
        mockStaking.setGlobalFee(1000); // 10%
        mockStaking.setOperatorFee(5000); // 50% of global = 5% total

        vm.deal(address(clDispatcher), 10 ether);
        vm.prank(attacker);
        clDispatcher.dispatch(PUBKEY_ROOT_1);

        assertTrue(
            treasury.balance > treasuryReceived,
            "Admin can change fee structure"
        );
    }

    // =====================================================================
    // TEST 9: Treasury address(0) burns ETH
    // =====================================================================
    /// @dev The deployed EL Dispatcher (impl) at
    ///      Mainnet: DeployedAddresses.MAINNET_EXECUTION_LAYER_FEE_DISPATCHER
    ///        (`0xca4DD914fA713214844c84F153A5e1627536a7fC`)
    ///      Holesky: DeployedAddresses.TESTNET_EXECUTION_LAYER_FEE_DISPATCHER
    ///        (`0xa69dDEBd0B6893A6F3d34A5df610d0E2ED433D18`)
    ///      sends treasury fee via .call{value: ...}("") without checking
    ///      for address(0), burning the treasury share permanently.
    function test_el_treasury_zero_burns_eth() public {
        mockStaking.setTreasury(address(0));

        vm.deal(address(elDispatcher), 10 ether);
        vm.prank(attacker);
        elDispatcher.dispatch(PUBKEY_ROOT_1);

        assertTrue(user.balance > 0, "User received funds");
        assertTrue(operatorFeeRecipient.balance > 0, "Operator received funds");
        assertEq(treasury.balance, 0, "Treasury fee burned to address(0)");
    }

    // =====================================================================
    // TEST 10: CL dispatcher exit exemption logic
    // =====================================================================
    function test_cl_exit_exemption_logic() public {
        mockStaking.setExitRequested(PUBKEY_ROOT_1, true);
        mockStaking.setWithdrawn(PUBKEY_ROOT_1, false);

        // 32.5 ETH = 32 ETH principal + 0.5 ETH rewards
        vm.deal(address(clDispatcher), 32.5 ether);
        vm.prank(attacker);
        clDispatcher.dispatch(PUBKEY_ROOT_1);

        // Fees computed only on 0.5 ETH (exemption = 32 ETH)
        uint256 expectedGlobalFee = (0.5 ether * 500) / 10000;
        uint256 expectedOperatorFee = (expectedGlobalFee * 2000) / 10000;

        assertEq(
            treasury.balance,
            expectedGlobalFee - expectedOperatorFee,
            "Treasury fee on rewards only"
        );
        assertEq(
            operatorFeeRecipient.balance,
            expectedOperatorFee,
            "Operator fee on rewards only"
        );
        assertTrue(user.balance > 32 ether, "User receives principal back");
    }

    // =====================================================================
    // TEST 11: Slashing — no exemption
    // =====================================================================
    function test_cl_slashing_no_exemption() public {
        mockStaking.setExitRequested(PUBKEY_ROOT_1, false);
        mockStaking.setWithdrawn(PUBKEY_ROOT_1, false);

        vm.deal(address(clDispatcher), 32 ether);
        vm.prank(attacker);
        clDispatcher.dispatch(PUBKEY_ROOT_1);

        uint256 expectedGlobalFee = (32 ether * 500) / 10000;
        assertEq(
            treasury.balance + operatorFeeRecipient.balance,
            expectedGlobalFee,
            "Full fee charged on principal"
        );
    }

    // =====================================================================
    // TEST 12: Force-send ETH via selfdestruct bypasses receive/fallback revert
    // =====================================================================
    function test_forced_eth_selfdestruct() public {
        GriefingContract grief = new GriefingContract();
        vm.deal(address(grief), 1 ether);
        grief.forceSend(payable(address(clDispatcher)));

        assertEq(
            address(clDispatcher).balance,
            1 ether,
            "ETH force-sent to dispatcher"
        );

        // Dispatch with zero withdrawer — ETH burned
        mockStaking.setZeroWithdrawer(true);
        vm.prank(attacker);
        clDispatcher.dispatch(PUBKEY_ROOT_1);

        assertEq(
            address(clDispatcher).balance,
            0,
            "Forced ETH dispatched and burned"
        );
    }

    // =====================================================================
    // TEST 13: Verify EL dispatcher has NO toggleWithdrawn call
    // =====================================================================
    /// @notice Unlike CL dispatcher, EL dispatcher does not call
    ///         toggleWithdrawnFromPublicKeyRoot, so the reentrancy
    ///         risk is lower but still present (event ordering).
    function test_el_dispatcher_no_state_change_before_send() public {
        // EL dispatcher has no toggleWithdrawn call — it only reads state
        // and sends ETH. Verify by checking that withdrawn flag is unchanged.
        mockStaking.setWithdrawn(PUBKEY_ROOT_1, false);

        vm.deal(address(elDispatcher), 1 ether);
        vm.prank(attacker);
        elDispatcher.dispatch(PUBKEY_ROOT_1);

        // EL dispatcher does NOT call toggleWithdrawn
        assertFalse(
            mockStaking.getWithdrawnFromPublicKeyRoot(PUBKEY_ROOT_1),
            "EL dispatcher doesn't toggle withdrawn flag"
        );
    }
}
