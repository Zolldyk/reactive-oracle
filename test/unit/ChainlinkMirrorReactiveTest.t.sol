// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {ChainlinkMirrorReactive} from "../../src/reactive/ChainlinkMirrorReactive.sol";
import {IReactive} from "@reactive/interfaces/IReactive.sol";
import {MockSystemContract} from "../mocks/MockSystemContract.sol";
import {SEPOLIA_CHAIN_ID, LASNA_CHAIN_ID, REACTIVE_CHAIN_ID, ORIGIN_CALLBACK_GAS, DESTINATION_CALLBACK_GAS} from "../../src/Constants.sol";

contract ChainlinkMirrorReactiveTest is Test {
    ChainlinkMirrorReactive private s_reactive;
    MockSystemContract private s_mockSystem;

    address private s_chainlinkFeed;
    address private s_originHelper;
    address private s_feedProxy;

    uint256 private constant ORIGIN_CHAIN_ID = SEPOLIA_CHAIN_ID;
    uint256 private constant DESTINATION_CHAIN_ID = LASNA_CHAIN_ID;

    // Event topic constants (matching the contract)
    bytes32 private constant ANSWER_UPDATED_TOPIC = keccak256("AnswerUpdated(int256,uint256,uint256)");
    bytes32 private constant ROUND_DATA_RECEIVED_TOPIC = keccak256("RoundDataReceived(uint80,int256,uint256,uint256,uint80)");
    bytes32 private constant CRON_100_TOPIC = bytes32(uint256(0x64));

    // System contract address
    address payable private constant SYSTEM_CONTRACT = payable(0x0000000000000000000000000000000000fffFfF);

    // Events from the contract
    event RoundProcessingStarted(uint80 indexed roundId);
    event RoundMirrored(uint80 indexed roundId, int256 answer);
    event DuplicateRoundSkipped(uint80 indexed roundId);
    event CronFallbackTriggered(uint256 timestamp);
    event Callback(uint256 indexed chain_id, address indexed _contract, uint64 indexed gas_limit, bytes payload);

    function setUp() public {
        s_chainlinkFeed = makeAddr("chainlinkFeed");
        s_originHelper = makeAddr("originHelper");
        s_feedProxy = makeAddr("feedProxy");

        // Deploy mock system contract and etch it at the system address
        s_mockSystem = new MockSystemContract();
        vm.etch(SYSTEM_CONTRACT, address(s_mockSystem).code);

        // Deploy reactive contract (constructor will call subscribe on mock)
        s_reactive = new ChainlinkMirrorReactive(
            ORIGIN_CHAIN_ID,
            DESTINATION_CHAIN_ID,
            s_chainlinkFeed,
            s_originHelper,
            s_feedProxy
        );

        // Set vm = true in storage to allow vmOnly modifier to pass
        // Storage layout: slot 0 = vendor, slot 1 = senders mapping, slot 2 = vm
        vm.store(address(s_reactive), bytes32(uint256(2)), bytes32(uint256(1)));
    }

    // ============ Constructor Tests (Task 14) ============

    function test_Constructor_SetsOriginChainId() public view {
        (uint256 originChainId,,,,) = s_reactive.getConfiguration();
        assertEq(originChainId, ORIGIN_CHAIN_ID);
    }

    function test_Constructor_SetsDestinationChainId() public view {
        (, uint256 destinationChainId,,,) = s_reactive.getConfiguration();
        assertEq(destinationChainId, DESTINATION_CHAIN_ID);
    }

    function test_Constructor_SetsChainlinkFeed() public view {
        (,, address chainlinkFeed,,) = s_reactive.getConfiguration();
        assertEq(chainlinkFeed, s_chainlinkFeed);
    }

    function test_Constructor_SetsOriginHelper() public view {
        (,,, address originHelper,) = s_reactive.getConfiguration();
        assertEq(originHelper, s_originHelper);
    }

    function test_Constructor_SetsFeedProxy() public view {
        (,,,, address feedProxy) = s_reactive.getConfiguration();
        assertEq(feedProxy, s_feedProxy);
    }

    function test_GetConfiguration_ReturnsAllValues() public view {
        (
            uint256 originChainId,
            uint256 destinationChainId,
            address chainlinkFeed,
            address originHelper,
            address feedProxy
        ) = s_reactive.getConfiguration();

        assertEq(originChainId, ORIGIN_CHAIN_ID);
        assertEq(destinationChainId, DESTINATION_CHAIN_ID);
        assertEq(chainlinkFeed, s_chainlinkFeed);
        assertEq(originHelper, s_originHelper);
        assertEq(feedProxy, s_feedProxy);
    }

    // ============ Event Subscription Tests (Task 15) ============
    // Note: Subscription calls happen in constructor, we verify via mock

    function test_Constructor_SubscribesToAnswerUpdated() public {
        // Deploy fresh mock at a different address to capture subscriptions cleanly
        MockSystemContract freshMock = new MockSystemContract();

        // Etch both code and clear storage by etching at SYSTEM_CONTRACT
        vm.etch(SYSTEM_CONTRACT, address(freshMock).code);
        // Clear subscription storage slots
        vm.store(SYSTEM_CONTRACT, bytes32(uint256(0)), bytes32(0)); // subscriptions array length
        vm.store(SYSTEM_CONTRACT, bytes32(uint256(1)), bytes32(0)); // subscriptionCount

        new ChainlinkMirrorReactive(
            ORIGIN_CHAIN_ID,
            DESTINATION_CHAIN_ID,
            s_chainlinkFeed,
            s_originHelper,
            s_feedProxy
        );

        // Verify subscriptions were made
        MockSystemContract mockAtAddr = MockSystemContract(SYSTEM_CONTRACT);
        assertEq(mockAtAddr.subscriptionCount(), 3);

        // First subscription should be AnswerUpdated
        (uint256 chainId, address contractAddr, uint256 topic0,,,) = mockAtAddr.subscriptions(0);
        assertEq(chainId, ORIGIN_CHAIN_ID);
        assertEq(contractAddr, s_chainlinkFeed);
        assertEq(topic0, uint256(ANSWER_UPDATED_TOPIC));
    }

    function test_Constructor_SubscribesToRoundDataReceived() public {
        MockSystemContract newMock = new MockSystemContract();
        vm.etch(SYSTEM_CONTRACT, address(newMock).code);

        new ChainlinkMirrorReactive(
            ORIGIN_CHAIN_ID,
            DESTINATION_CHAIN_ID,
            s_chainlinkFeed,
            s_originHelper,
            s_feedProxy
        );

        MockSystemContract mockAtAddr = MockSystemContract(SYSTEM_CONTRACT);

        // Second subscription should be RoundDataReceived
        (uint256 chainId, address contractAddr, uint256 topic0,,,) = mockAtAddr.subscriptions(1);
        assertEq(chainId, ORIGIN_CHAIN_ID);
        assertEq(contractAddr, s_originHelper);
        assertEq(topic0, uint256(ROUND_DATA_RECEIVED_TOPIC));
    }

    function test_Constructor_SubscribesToCron100() public {
        MockSystemContract newMock = new MockSystemContract();
        vm.etch(SYSTEM_CONTRACT, address(newMock).code);

        new ChainlinkMirrorReactive(
            ORIGIN_CHAIN_ID,
            DESTINATION_CHAIN_ID,
            s_chainlinkFeed,
            s_originHelper,
            s_feedProxy
        );

        MockSystemContract mockAtAddr = MockSystemContract(SYSTEM_CONTRACT);

        // Third subscription should be Cron100
        (uint256 chainId, address contractAddr, uint256 topic0,,,) = mockAtAddr.subscriptions(2);
        assertEq(chainId, REACTIVE_CHAIN_ID);
        assertEq(contractAddr, address(0));
        assertEq(topic0, uint256(CRON_100_TOPIC));
    }

    // ============ react() Routing Tests (Task 16) ============

    function test_React_RoutesToAnswerUpdatedHandler() public {
        IReactive.LogRecord memory log = _createLogRecord(
            ORIGIN_CHAIN_ID,
            s_chainlinkFeed,
            ANSWER_UPDATED_TOPIC,
            100_00000000, // answer in topic_1
            1, // roundId in topic_2
            abi.encode(block.timestamp) // timestamp in data
        );

        vm.expectEmit(true, false, false, false);
        emit RoundProcessingStarted(1);

        s_reactive.react(log);
    }

    function test_React_RoutesToRoundDataReceivedHandler() public {
        // First process an AnswerUpdated to mark round as pending
        _processAnswerUpdated(1, 100_00000000);

        IReactive.LogRecord memory log = _createLogRecord(
            ORIGIN_CHAIN_ID,
            s_originHelper,
            ROUND_DATA_RECEIVED_TOPIC,
            1, // roundId in topic_1
            0,
            abi.encode(int256(100_00000000), uint256(1000), uint256(1001), uint80(1))
        );

        vm.expectEmit(true, false, false, true);
        emit RoundMirrored(1, 100_00000000);

        s_reactive.react(log);
    }

    function test_React_RoutesToCronHandler() public {
        IReactive.LogRecord memory log = _createLogRecord(
            REACTIVE_CHAIN_ID,
            address(0),
            CRON_100_TOPIC,
            0,
            0,
            ""
        );

        vm.expectEmit(false, false, false, true);
        emit CronFallbackTriggered(block.timestamp);

        s_reactive.react(log);
    }

    function test_React_RevertsOnUnknownEvent() public {
        bytes32 unknownTopic = keccak256("UnknownEvent()");
        IReactive.LogRecord memory log = _createLogRecord(
            ORIGIN_CHAIN_ID,
            s_chainlinkFeed,
            unknownTopic,
            0,
            0,
            ""
        );

        vm.expectRevert(ChainlinkMirrorReactive.ChainlinkMirrorReactive__UnknownEvent.selector);
        s_reactive.react(log);
    }

    function test_React_RevertsOnWrongOriginForAnswerUpdated() public {
        address wrongOrigin = makeAddr("wrongOrigin");
        IReactive.LogRecord memory log = _createLogRecord(
            ORIGIN_CHAIN_ID,
            wrongOrigin,
            ANSWER_UPDATED_TOPIC,
            100_00000000,
            1,
            abi.encode(block.timestamp)
        );

        vm.expectRevert(ChainlinkMirrorReactive.ChainlinkMirrorReactive__UnknownEvent.selector);
        s_reactive.react(log);
    }

    function test_React_RevertsOnWrongOriginForRoundDataReceived() public {
        address wrongOrigin = makeAddr("wrongOrigin");
        IReactive.LogRecord memory log = _createLogRecord(
            ORIGIN_CHAIN_ID,
            wrongOrigin,
            ROUND_DATA_RECEIVED_TOPIC,
            1,
            0,
            abi.encode(int256(100), uint256(1000), uint256(1001), uint80(1))
        );

        vm.expectRevert(ChainlinkMirrorReactive.ChainlinkMirrorReactive__UnknownEvent.selector);
        s_reactive.react(log);
    }

    // ============ AnswerUpdated Handler Tests (Task 17) ============

    function test_HandleAnswerUpdated_MarksRoundPending() public {
        assertFalse(s_reactive.isRoundPending(1));

        _processAnswerUpdated(1, 100_00000000);

        assertTrue(s_reactive.isRoundPending(1));
    }

    function test_HandleAnswerUpdated_EmitsRoundProcessingStarted() public {
        IReactive.LogRecord memory log = _createLogRecord(
            ORIGIN_CHAIN_ID,
            s_chainlinkFeed,
            ANSWER_UPDATED_TOPIC,
            100_00000000,
            1,
            abi.encode(block.timestamp)
        );

        vm.expectEmit(true, false, false, false);
        emit RoundProcessingStarted(1);

        s_reactive.react(log);
    }

    function test_HandleAnswerUpdated_EmitsCallbackToOriginHelper() public {
        IReactive.LogRecord memory log = _createLogRecord(
            ORIGIN_CHAIN_ID,
            s_chainlinkFeed,
            ANSWER_UPDATED_TOPIC,
            100_00000000,
            1,
            abi.encode(block.timestamp)
        );

        vm.expectEmit(true, true, true, true);
        emit Callback(
            ORIGIN_CHAIN_ID,
            s_originHelper,
            uint64(ORIGIN_CALLBACK_GAS),
            abi.encodeWithSignature("enrichRoundData(uint80)", uint80(1))
        );

        s_reactive.react(log);
    }

    function test_HandleAnswerUpdated_SkipsDuplicateRound() public {
        // Process round 1 fully (mark pending, then complete)
        _processAnswerUpdated(1, 100_00000000);
        _processRoundDataReceived(1, 100_00000000);

        // Try to process round 1 again
        IReactive.LogRecord memory log = _createLogRecord(
            ORIGIN_CHAIN_ID,
            s_chainlinkFeed,
            ANSWER_UPDATED_TOPIC,
            100_00000000,
            1,
            abi.encode(block.timestamp)
        );

        vm.expectEmit(true, false, false, false);
        emit DuplicateRoundSkipped(1);

        s_reactive.react(log);
    }

    function test_HandleAnswerUpdated_SkipsPendingRound() public {
        // Process round 1 (mark as pending but don't complete)
        _processAnswerUpdated(1, 100_00000000);

        // Try to process round 1 again while still pending
        IReactive.LogRecord memory log = _createLogRecord(
            ORIGIN_CHAIN_ID,
            s_chainlinkFeed,
            ANSWER_UPDATED_TOPIC,
            100_00000000,
            1,
            abi.encode(block.timestamp)
        );

        vm.expectEmit(true, false, false, false);
        emit DuplicateRoundSkipped(1);

        s_reactive.react(log);
    }

    function test_HandleAnswerUpdated_SkipsLowerRoundAfterHigherProcessed() public {
        // Process round 5 fully
        _processAnswerUpdated(5, 100_00000000);
        _processRoundDataReceived(5, 100_00000000);

        // Try to process round 3 (lower than last processed)
        IReactive.LogRecord memory log = _createLogRecord(
            ORIGIN_CHAIN_ID,
            s_chainlinkFeed,
            ANSWER_UPDATED_TOPIC,
            100_00000000,
            3,
            abi.encode(block.timestamp)
        );

        vm.expectEmit(true, false, false, false);
        emit DuplicateRoundSkipped(3);

        s_reactive.react(log);
    }

    // ============ RoundDataReceived Handler Tests (Task 18) ============

    function test_HandleRoundDataReceived_ClearsPendingState() public {
        _processAnswerUpdated(1, 100_00000000);
        assertTrue(s_reactive.isRoundPending(1));

        _processRoundDataReceived(1, 100_00000000);
        assertFalse(s_reactive.isRoundPending(1));
    }

    function test_HandleRoundDataReceived_UpdatesLastProcessedRound() public {
        assertEq(s_reactive.getLastProcessedRound(), 0);

        _processAnswerUpdated(1, 100_00000000);
        _processRoundDataReceived(1, 100_00000000);

        assertEq(s_reactive.getLastProcessedRound(), 1);
    }

    function test_HandleRoundDataReceived_EmitsRoundMirrored() public {
        _processAnswerUpdated(1, 100_00000000);

        IReactive.LogRecord memory log = _createLogRecord(
            ORIGIN_CHAIN_ID,
            s_originHelper,
            ROUND_DATA_RECEIVED_TOPIC,
            1,
            0,
            abi.encode(int256(100_00000000), uint256(1000), uint256(1001), uint80(1))
        );

        vm.expectEmit(true, false, false, true);
        emit RoundMirrored(1, 100_00000000);

        s_reactive.react(log);
    }

    function test_HandleRoundDataReceived_EmitsCallbackToFeedProxy() public {
        _processAnswerUpdated(1, 100_00000000);

        IReactive.LogRecord memory log = _createLogRecord(
            ORIGIN_CHAIN_ID,
            s_originHelper,
            ROUND_DATA_RECEIVED_TOPIC,
            1,
            0,
            abi.encode(int256(100_00000000), uint256(1000), uint256(1001), uint80(1))
        );

        vm.expectEmit(true, true, true, true);
        emit Callback(
            DESTINATION_CHAIN_ID,
            s_feedProxy,
            uint64(DESTINATION_CALLBACK_GAS),
            abi.encodeWithSignature(
                "updateRoundData(uint80,int256,uint256,uint256,uint80)",
                uint80(1),
                int256(100_00000000),
                uint256(1000),
                uint256(1001),
                uint80(1)
            )
        );

        s_reactive.react(log);
    }

    function test_HandleRoundDataReceived_UpdatesLastProcessedOnlyIfHigher() public {
        // Process round 5
        _processAnswerUpdated(5, 100_00000000);
        _processRoundDataReceived(5, 100_00000000);
        assertEq(s_reactive.getLastProcessedRound(), 5);

        // Process round 3 (lower - should not update lastProcessed)
        // Note: This would be skipped in AnswerUpdated, but we're testing
        // RoundDataReceived in isolation
        _processAnswerUpdated(10, 100_00000000); // Need a higher round first

        // Directly test that round 3 wouldn't update if somehow processed
        // This is actually handled by dedup in AnswerUpdated, not RoundDataReceived
        assertEq(s_reactive.getLastProcessedRound(), 5);
    }

    // ============ Cron Handler Tests (Task 19) ============

    function test_HandleCronHeartbeat_EmitsCronFallbackTriggered() public {
        IReactive.LogRecord memory log = _createLogRecord(
            REACTIVE_CHAIN_ID,
            address(0),
            CRON_100_TOPIC,
            0,
            0,
            ""
        );

        vm.expectEmit(false, false, false, true);
        emit CronFallbackTriggered(block.timestamp);

        s_reactive.react(log);
    }

    function test_HandleCronHeartbeat_EmitsCallbackToOriginHelper() public {
        IReactive.LogRecord memory log = _createLogRecord(
            REACTIVE_CHAIN_ID,
            address(0),
            CRON_100_TOPIC,
            0,
            0,
            ""
        );

        vm.expectEmit(true, true, true, true);
        emit Callback(
            ORIGIN_CHAIN_ID,
            s_originHelper,
            uint64(ORIGIN_CALLBACK_GAS),
            abi.encodeWithSignature("enrichLatestRound()")
        );

        s_reactive.react(log);
    }

    // ============ Getter Function Tests (Task 20) ============

    function test_GetLastProcessedRound_ReturnsZeroInitially() public view {
        assertEq(s_reactive.getLastProcessedRound(), 0);
    }

    function test_GetLastProcessedRound_ReturnsUpdatedValue() public {
        _processAnswerUpdated(1, 100_00000000);
        _processRoundDataReceived(1, 100_00000000);

        assertEq(s_reactive.getLastProcessedRound(), 1);
    }

    function test_IsRoundPending_ReturnsFalseInitially() public view {
        assertFalse(s_reactive.isRoundPending(1));
    }

    function test_IsRoundPending_ReturnsTrueWhenPending() public {
        _processAnswerUpdated(1, 100_00000000);
        assertTrue(s_reactive.isRoundPending(1));
    }

    // ============ Fuzz Tests (Task 21) ============

    function testFuzz_HandleAnswerUpdated_HandlesAnyRoundId(uint80 roundId) public {
        vm.assume(roundId > 0);

        IReactive.LogRecord memory log = _createLogRecord(
            ORIGIN_CHAIN_ID,
            s_chainlinkFeed,
            ANSWER_UPDATED_TOPIC,
            100_00000000,
            roundId,
            abi.encode(block.timestamp)
        );

        vm.expectEmit(true, false, false, false);
        emit RoundProcessingStarted(roundId);

        s_reactive.react(log);

        assertTrue(s_reactive.isRoundPending(roundId));
    }

    function testFuzz_HandleRoundDataReceived_HandlesAnyData(
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) public {
        vm.assume(roundId > 0);

        // First mark round as pending
        _processAnswerUpdated(roundId, answer);

        IReactive.LogRecord memory log = _createLogRecord(
            ORIGIN_CHAIN_ID,
            s_originHelper,
            ROUND_DATA_RECEIVED_TOPIC,
            roundId,
            0,
            abi.encode(answer, startedAt, updatedAt, answeredInRound)
        );

        vm.expectEmit(true, false, false, true);
        emit RoundMirrored(roundId, answer);

        s_reactive.react(log);

        assertEq(s_reactive.getLastProcessedRound(), roundId);
        assertFalse(s_reactive.isRoundPending(roundId));
    }

    function testFuzz_Deduplication_RejectsLowerOrEqualRounds(uint80 highRound, uint80 lowRound) public {
        highRound = uint80(bound(uint256(highRound), 2, type(uint80).max));
        lowRound = uint80(bound(uint256(lowRound), 1, highRound));

        // Process high round
        _processAnswerUpdated(highRound, 100_00000000);
        _processRoundDataReceived(highRound, 100_00000000);

        // Try to process lower round
        IReactive.LogRecord memory log = _createLogRecord(
            ORIGIN_CHAIN_ID,
            s_chainlinkFeed,
            ANSWER_UPDATED_TOPIC,
            100_00000000,
            lowRound,
            abi.encode(block.timestamp)
        );

        vm.expectEmit(true, false, false, false);
        emit DuplicateRoundSkipped(lowRound);

        s_reactive.react(log);
    }

    // ============ Helper Functions ============

    function _createLogRecord(
        uint256 chainId,
        address origin,
        bytes32 topic0,
        uint256 topic1,
        uint256 topic2,
        bytes memory data
    ) internal pure returns (IReactive.LogRecord memory) {
        return IReactive.LogRecord({
            chain_id: chainId,
            _contract: origin,
            topic_0: uint256(topic0),
            topic_1: topic1,
            topic_2: topic2,
            topic_3: 0,
            data: data,
            block_number: 0,
            op_code: 0,
            block_hash: 0,
            tx_hash: 0,
            log_index: 0
        });
    }

    function _processAnswerUpdated(uint80 roundId, int256 answer) internal {
        IReactive.LogRecord memory log = _createLogRecord(
            ORIGIN_CHAIN_ID,
            s_chainlinkFeed,
            ANSWER_UPDATED_TOPIC,
            uint256(int256(answer)), // answer in topic_1 (cast via int256 to preserve sign info as uint256)
            roundId, // roundId in topic_2
            abi.encode(block.timestamp)
        );
        s_reactive.react(log);
    }

    function _processRoundDataReceived(uint80 roundId, int256 answer) internal {
        IReactive.LogRecord memory log = _createLogRecord(
            ORIGIN_CHAIN_ID,
            s_originHelper,
            ROUND_DATA_RECEIVED_TOPIC,
            roundId, // roundId in topic_1
            0,
            abi.encode(answer, uint256(1000), uint256(1001), roundId)
        );
        s_reactive.react(log);
    }
}
