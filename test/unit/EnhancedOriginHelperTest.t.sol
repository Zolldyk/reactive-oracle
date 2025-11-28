// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {EnhancedOriginHelper} from "../../src/origin/EnhancedOriginHelper.sol";
import {IEnhancedOriginHelper} from "../../src/interfaces/IEnhancedOriginHelper.sol";
import {MockChainlinkAggregator} from "../mocks/MockChainlinkAggregator.sol";

contract EnhancedOriginHelperTest is Test {
    EnhancedOriginHelper private s_helper;
    MockChainlinkAggregator private s_mockAggregator;
    address private s_callbackProxy;
    address private s_reactiveContract;

    uint8 private constant DECIMALS = 8;
    string private constant DESCRIPTION = "ETH / USD";
    uint256 private constant STALENESS_THRESHOLD = 2 hours;

    // Sample round data
    uint80 private constant ROUND_ID_1 = 1;
    uint80 private constant ROUND_ID_2 = 2;
    uint80 private constant ROUND_ID_3 = 3;
    int256 private constant ANSWER_1 = 2000_00000000; // $2000.00 with 8 decimals
    int256 private constant ANSWER_2 = 2050_00000000; // $2050.00 with 8 decimals

    function setUp() public {
        // Warp to a reasonable timestamp to avoid underflow in staleness tests
        vm.warp(1700000000); // Nov 2023 timestamp

        s_mockAggregator = new MockChainlinkAggregator(DECIMALS, DESCRIPTION);
        s_callbackProxy = makeAddr("callbackProxy");
        s_reactiveContract = makeAddr("reactiveContract");

        s_helper = new EnhancedOriginHelper(
            address(s_mockAggregator),
            s_callbackProxy,
            s_reactiveContract
        );
    }

    // ============ Constructor Tests (Task 10) ============

    function test_Constructor_SetsChainlinkFeed() public view {
        assertEq(s_helper.getChainlinkFeed(), address(s_mockAggregator));
    }

    function test_Constructor_SetsCallbackProxy() public view {
        assertEq(s_helper.getCallbackProxy(), s_callbackProxy);
    }

    function test_Constructor_SetsReactiveContract() public view {
        assertEq(s_helper.getReactiveContract(), s_reactiveContract);
    }

    function test_Constructor_RevertsOnZeroChainlinkFeed() public {
        vm.expectRevert(EnhancedOriginHelper.EnhancedOriginHelper__ZeroAddress.selector);
        new EnhancedOriginHelper(address(0), s_callbackProxy, s_reactiveContract);
    }

    function test_Constructor_RevertsOnZeroCallbackProxy() public {
        vm.expectRevert(EnhancedOriginHelper.EnhancedOriginHelper__ZeroAddress.selector);
        new EnhancedOriginHelper(address(s_mockAggregator), address(0), s_reactiveContract);
    }

    function test_Constructor_RevertsOnZeroReactiveContract() public {
        vm.expectRevert(EnhancedOriginHelper.EnhancedOriginHelper__ZeroAddress.selector);
        new EnhancedOriginHelper(address(s_mockAggregator), s_callbackProxy, address(0));
    }

    // ============ Authorization Tests (Task 11) ============

    function test_EnrichRoundData_RevertsIfNotCallbackProxy() public {
        _setupValidRoundData(ROUND_ID_1);
        address unauthorized = makeAddr("unauthorized");

        // Wrong msg.sender, correct tx.origin
        vm.prank(unauthorized, s_reactiveContract);
        vm.expectRevert(EnhancedOriginHelper.EnhancedOriginHelper__UnauthorizedCaller.selector);
        s_helper.enrichRoundData(ROUND_ID_1);
    }

    function test_EnrichRoundData_RevertsIfWrongTxOrigin() public {
        _setupValidRoundData(ROUND_ID_1);
        address wrongOrigin = makeAddr("wrongOrigin");

        // Correct msg.sender, wrong tx.origin
        vm.prank(s_callbackProxy, wrongOrigin);
        vm.expectRevert(EnhancedOriginHelper.EnhancedOriginHelper__UnauthorizedCaller.selector);
        s_helper.enrichRoundData(ROUND_ID_1);
    }

    function test_EnrichRoundData_SucceedsFromAuthorizedCaller() public {
        _setupValidRoundData(ROUND_ID_1);

        vm.prank(s_callbackProxy, s_reactiveContract);
        s_helper.enrichRoundData(ROUND_ID_1);

        assertEq(s_helper.getLastProcessedRound(), ROUND_ID_1);
    }

    // ============ Successful Enrichment Tests (Task 12) ============

    function test_EnrichRoundData_FetchesAndEmitsRoundData() public {
        uint256 timestamp = block.timestamp;
        s_mockAggregator.setRoundData(ROUND_ID_1, ANSWER_1, timestamp, timestamp, ROUND_ID_1);

        vm.expectEmit(true, false, false, true);
        emit IEnhancedOriginHelper.RoundDataReceived(ROUND_ID_1, ANSWER_1, timestamp, timestamp, ROUND_ID_1);

        vm.prank(s_callbackProxy, s_reactiveContract);
        s_helper.enrichRoundData(ROUND_ID_1);
    }

    function test_EnrichRoundData_UpdatesLastProcessedRound() public {
        _setupValidRoundData(ROUND_ID_1);

        assertEq(s_helper.getLastProcessedRound(), 0);

        vm.prank(s_callbackProxy, s_reactiveContract);
        s_helper.enrichRoundData(ROUND_ID_1);

        assertEq(s_helper.getLastProcessedRound(), ROUND_ID_1);
    }

    // ============ Duplicate/Sequential Rejection Tests (Task 13) ============

    function test_EnrichRoundData_RevertsOnDuplicateRound() public {
        _setupValidRoundData(ROUND_ID_1);

        // First call succeeds
        vm.prank(s_callbackProxy, s_reactiveContract);
        s_helper.enrichRoundData(ROUND_ID_1);

        // Second call with same round should revert
        vm.prank(s_callbackProxy, s_reactiveContract);
        vm.expectRevert(EnhancedOriginHelper.EnhancedOriginHelper__StaleRound.selector);
        s_helper.enrichRoundData(ROUND_ID_1);
    }

    function test_EnrichRoundData_RevertsOnLowerRound() public {
        _setupValidRoundData(ROUND_ID_1);
        _setupValidRoundData(ROUND_ID_2);

        // First add round 2
        vm.prank(s_callbackProxy, s_reactiveContract);
        s_helper.enrichRoundData(ROUND_ID_2);

        // Try to add round 1 (lower ID)
        vm.prank(s_callbackProxy, s_reactiveContract);
        vm.expectRevert(EnhancedOriginHelper.EnhancedOriginHelper__StaleRound.selector);
        s_helper.enrichRoundData(ROUND_ID_1);
    }

    function test_EnrichRoundData_AcceptsSequentialRounds() public {
        _setupValidRoundData(ROUND_ID_1);
        _setupValidRoundData(ROUND_ID_2);
        _setupValidRoundData(ROUND_ID_3);

        vm.startPrank(s_callbackProxy, s_reactiveContract);

        s_helper.enrichRoundData(ROUND_ID_1);
        assertEq(s_helper.getLastProcessedRound(), ROUND_ID_1);

        s_helper.enrichRoundData(ROUND_ID_2);
        assertEq(s_helper.getLastProcessedRound(), ROUND_ID_2);

        s_helper.enrichRoundData(ROUND_ID_3);
        assertEq(s_helper.getLastProcessedRound(), ROUND_ID_3);

        vm.stopPrank();
    }

    // ============ Staleness Rejection Tests (Task 14) ============

    function test_EnrichRoundData_RevertsOnStaleData() public {
        uint256 staleTimestamp = block.timestamp - STALENESS_THRESHOLD - 1;
        s_mockAggregator.setRoundData(ROUND_ID_1, ANSWER_1, staleTimestamp, staleTimestamp, ROUND_ID_1);

        vm.prank(s_callbackProxy, s_reactiveContract);
        vm.expectRevert(EnhancedOriginHelper.EnhancedOriginHelper__StaleData.selector);
        s_helper.enrichRoundData(ROUND_ID_1);
    }

    function test_EnrichRoundData_AcceptsFreshData() public {
        uint256 freshTimestamp = block.timestamp - 1 hours;
        s_mockAggregator.setRoundData(ROUND_ID_1, ANSWER_1, freshTimestamp, freshTimestamp, ROUND_ID_1);

        vm.prank(s_callbackProxy, s_reactiveContract);
        s_helper.enrichRoundData(ROUND_ID_1);

        assertEq(s_helper.getLastProcessedRound(), ROUND_ID_1);
    }

    function test_EnrichRoundData_AcceptsDataAtThreshold() public {
        uint256 thresholdTimestamp = block.timestamp - STALENESS_THRESHOLD;
        s_mockAggregator.setRoundData(ROUND_ID_1, ANSWER_1, thresholdTimestamp, thresholdTimestamp, ROUND_ID_1);

        vm.prank(s_callbackProxy, s_reactiveContract);
        s_helper.enrichRoundData(ROUND_ID_1);

        assertEq(s_helper.getLastProcessedRound(), ROUND_ID_1);
    }

    // ============ Chainlink Error Handling Tests (Task 15) ============

    function test_EnrichRoundData_RevertsOnInvalidRoundData() public {
        // Set mismatched round ID (roundId != fetchedRoundId)
        s_mockAggregator.setInvalidRoundData(ROUND_ID_1, ROUND_ID_2);

        vm.prank(s_callbackProxy, s_reactiveContract);
        vm.expectRevert(EnhancedOriginHelper.EnhancedOriginHelper__InvalidRoundData.selector);
        s_helper.enrichRoundData(ROUND_ID_1);
    }

    function test_EnrichRoundData_RevertsOnZeroUpdatedAt() public {
        // Set round data with zero updatedAt
        s_mockAggregator.setRoundData(ROUND_ID_1, ANSWER_1, block.timestamp, 0, ROUND_ID_1);

        vm.prank(s_callbackProxy, s_reactiveContract);
        vm.expectRevert(EnhancedOriginHelper.EnhancedOriginHelper__InvalidRoundData.selector);
        s_helper.enrichRoundData(ROUND_ID_1);
    }

    function test_EnrichRoundData_HandlesChainlinkRevert() public {
        s_mockAggregator.setRevertOnGetRoundData(true);

        vm.prank(s_callbackProxy, s_reactiveContract);
        vm.expectRevert(EnhancedOriginHelper.EnhancedOriginHelper__InvalidRoundData.selector);
        s_helper.enrichRoundData(ROUND_ID_1);
    }

    // ============ enrichLatestRound Tests (Task 16) ============

    function test_EnrichLatestRound_FetchesAndEmitsData() public {
        uint256 timestamp = block.timestamp;
        s_mockAggregator.setLatestRoundData(ROUND_ID_1, ANSWER_1, timestamp, timestamp, ROUND_ID_1);

        vm.expectEmit(true, false, false, true);
        emit IEnhancedOriginHelper.RoundDataReceived(ROUND_ID_1, ANSWER_1, timestamp, timestamp, ROUND_ID_1);

        vm.prank(s_callbackProxy, s_reactiveContract);
        s_helper.enrichLatestRound();

        assertEq(s_helper.getLastProcessedRound(), ROUND_ID_1);
    }

    function test_EnrichLatestRound_SkipsAlreadyProcessedRound() public {
        uint256 timestamp = block.timestamp;
        s_mockAggregator.setLatestRoundData(ROUND_ID_1, ANSWER_1, timestamp, timestamp, ROUND_ID_1);

        // First call processes the round
        vm.prank(s_callbackProxy, s_reactiveContract);
        s_helper.enrichLatestRound();

        // Second call should skip (no revert, idempotent)
        vm.prank(s_callbackProxy, s_reactiveContract);
        s_helper.enrichLatestRound(); // Should not revert

        // Verify still at round 1
        assertEq(s_helper.getLastProcessedRound(), ROUND_ID_1);
    }

    function test_EnrichLatestRound_RevertsIfUnauthorized() public {
        uint256 timestamp = block.timestamp;
        s_mockAggregator.setLatestRoundData(ROUND_ID_1, ANSWER_1, timestamp, timestamp, ROUND_ID_1);

        address unauthorized = makeAddr("unauthorized");

        vm.prank(unauthorized, s_reactiveContract);
        vm.expectRevert(EnhancedOriginHelper.EnhancedOriginHelper__UnauthorizedCaller.selector);
        s_helper.enrichLatestRound();
    }

    function test_EnrichLatestRound_RevertsOnStaleData() public {
        uint256 staleTimestamp = block.timestamp - STALENESS_THRESHOLD - 1;
        s_mockAggregator.setLatestRoundData(ROUND_ID_1, ANSWER_1, staleTimestamp, staleTimestamp, ROUND_ID_1);

        vm.prank(s_callbackProxy, s_reactiveContract);
        vm.expectRevert(EnhancedOriginHelper.EnhancedOriginHelper__StaleData.selector);
        s_helper.enrichLatestRound();
    }

    function test_EnrichLatestRound_RevertsOnZeroUpdatedAt() public {
        s_mockAggregator.setLatestRoundData(ROUND_ID_1, ANSWER_1, block.timestamp, 0, ROUND_ID_1);

        vm.prank(s_callbackProxy, s_reactiveContract);
        vm.expectRevert(EnhancedOriginHelper.EnhancedOriginHelper__InvalidRoundData.selector);
        s_helper.enrichLatestRound();
    }

    function test_EnrichLatestRound_HandlesChainlinkRevert() public {
        s_mockAggregator.setRevertOnLatestRoundData(true);

        vm.prank(s_callbackProxy, s_reactiveContract);
        vm.expectRevert(EnhancedOriginHelper.EnhancedOriginHelper__InvalidRoundData.selector);
        s_helper.enrichLatestRound();
    }

    // ============ Getter Function Tests (Task 17) ============

    function test_GetChainlinkFeed_ReturnsAddress() public view {
        assertEq(s_helper.getChainlinkFeed(), address(s_mockAggregator));
    }

    function test_GetCallbackProxy_ReturnsAddress() public view {
        assertEq(s_helper.getCallbackProxy(), s_callbackProxy);
    }

    function test_GetReactiveContract_ReturnsAddress() public view {
        assertEq(s_helper.getReactiveContract(), s_reactiveContract);
    }

    function test_GetLastProcessedRound_ReturnsZeroInitially() public view {
        assertEq(s_helper.getLastProcessedRound(), 0);
    }

    function test_GetLastProcessedRound_ReturnsUpdatedValue() public {
        _setupValidRoundData(ROUND_ID_1);

        vm.prank(s_callbackProxy, s_reactiveContract);
        s_helper.enrichRoundData(ROUND_ID_1);

        assertEq(s_helper.getLastProcessedRound(), ROUND_ID_1);
    }

    // ============ Fuzz Tests (Task 18) ============

    function testFuzz_EnrichRoundData_HandlesValidData(
        uint80 roundId,
        int256 answer,
        uint256 startedAtSeed,
        uint80 answeredInRound
    ) public {
        // Bound inputs to valid ranges
        roundId = uint80(bound(uint256(roundId), 1, type(uint80).max));

        // updatedAt must be within staleness threshold of current block.timestamp
        uint256 updatedAt = bound(startedAtSeed, block.timestamp - STALENESS_THRESHOLD, block.timestamp);
        uint256 startedAt = bound(startedAtSeed, 0, updatedAt);

        s_mockAggregator.setRoundData(roundId, answer, startedAt, updatedAt, answeredInRound);

        vm.prank(s_callbackProxy, s_reactiveContract);
        s_helper.enrichRoundData(roundId);

        assertEq(s_helper.getLastProcessedRound(), roundId);
    }

    function testFuzz_EnrichRoundData_RejectsStaleRounds(uint80 current, uint80 stale) public {
        // Ensure current > 0 and stale <= current
        current = uint80(bound(uint256(current), 1, type(uint80).max));
        stale = uint80(bound(uint256(stale), 0, current));

        _setupValidRoundData(current);

        // First process the current round
        vm.prank(s_callbackProxy, s_reactiveContract);
        s_helper.enrichRoundData(current);

        // Setup stale round data
        _setupValidRoundData(stale);

        // Try to process stale round - should revert
        vm.prank(s_callbackProxy, s_reactiveContract);
        vm.expectRevert(EnhancedOriginHelper.EnhancedOriginHelper__StaleRound.selector);
        s_helper.enrichRoundData(stale);
    }

    // ============ Helper Functions ============

    function _setupValidRoundData(uint80 roundId) internal {
        uint256 timestamp = block.timestamp;
        s_mockAggregator.setRoundData(roundId, ANSWER_1, timestamp, timestamp, roundId);
    }
}
