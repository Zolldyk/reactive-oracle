// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {FeedProxy} from "../../src/destination/FeedProxy.sol";

contract FeedProxyTest is Test {
    FeedProxy private s_feedProxy;
    address private s_reactiveContract;

    uint8 private constant DECIMALS = 8;
    string private constant DESCRIPTION = "ETH / USD";
    uint256 private constant STALENESS_THRESHOLD = 2 hours;

    // Sample round data
    uint80 private constant ROUND_ID_1 = 1;
    uint80 private constant ROUND_ID_2 = 2;
    int256 private constant ANSWER_1 = 2000_00000000; // $2000.00 with 8 decimals
    int256 private constant ANSWER_2 = 2050_00000000; // $2050.00 with 8 decimals

    function setUp() public {
        // Warp to a reasonable timestamp to avoid underflow in staleness tests
        vm.warp(1700000000); // Nov 2023 timestamp

        s_reactiveContract = makeAddr("reactive");
        s_feedProxy = new FeedProxy(s_reactiveContract, DECIMALS, DESCRIPTION);
    }

    // ============ Constructor Tests (Task 10) ============

    function test_Constructor_SetsReactiveContract() public view {
        assertEq(s_feedProxy.getReactiveContract(), s_reactiveContract);
    }

    function test_Constructor_SetsDecimals() public view {
        assertEq(s_feedProxy.decimals(), DECIMALS);
    }

    function test_Constructor_SetsDescription() public view {
        assertEq(s_feedProxy.description(), DESCRIPTION);
    }

    // ============ Authorization Tests (Task 11) ============

    function test_UpdateRoundData_RevertsIfUnauthorized() public {
        address unauthorized = makeAddr("unauthorized");

        vm.prank(unauthorized);
        vm.expectRevert(FeedProxy.FeedProxy__UnauthorizedCaller.selector);
        s_feedProxy.updateRoundData(ROUND_ID_1, ANSWER_1, block.timestamp, block.timestamp, ROUND_ID_1);
    }

    function test_UpdateRoundData_SucceedsFromReactiveContract() public {
        vm.prank(s_reactiveContract);
        s_feedProxy.updateRoundData(ROUND_ID_1, ANSWER_1, block.timestamp, block.timestamp, ROUND_ID_1);

        assertEq(s_feedProxy.getLatestRoundId(), ROUND_ID_1);
    }

    // ============ Duplicate Rejection Tests (Task 12) ============

    function test_UpdateRoundData_SkipsDuplicateRound() public {
        // First update
        vm.prank(s_reactiveContract);
        s_feedProxy.updateRoundData(ROUND_ID_1, ANSWER_1, block.timestamp, block.timestamp, ROUND_ID_1);

        // Expect DuplicateRoundSkipped event on second attempt
        vm.expectEmit(true, false, false, false);
        emit FeedProxy.DuplicateRoundSkipped(ROUND_ID_1);

        vm.prank(s_reactiveContract);
        s_feedProxy.updateRoundData(ROUND_ID_1, ANSWER_2, block.timestamp, block.timestamp, ROUND_ID_1);
    }

    function test_UpdateRoundData_DuplicatePreservesOriginalData() public {
        uint256 originalTimestamp = block.timestamp;

        // First update
        vm.prank(s_reactiveContract);
        s_feedProxy.updateRoundData(ROUND_ID_1, ANSWER_1, originalTimestamp, originalTimestamp, ROUND_ID_1);

        // Second update with different data
        vm.prank(s_reactiveContract);
        s_feedProxy.updateRoundData(ROUND_ID_1, ANSWER_2, originalTimestamp + 100, originalTimestamp + 100, ROUND_ID_1);

        // Verify original data is preserved
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            s_feedProxy.getRoundData(ROUND_ID_1);

        assertEq(roundId, ROUND_ID_1);
        assertEq(answer, ANSWER_1);
        assertEq(startedAt, originalTimestamp);
        assertEq(updatedAt, originalTimestamp);
        assertEq(answeredInRound, ROUND_ID_1);
    }

    // ============ Sequential Enforcement Tests (Task 13) ============

    function test_UpdateRoundData_RevertsOnStaleRound() public {
        // First add round 2
        vm.prank(s_reactiveContract);
        s_feedProxy.updateRoundData(ROUND_ID_2, ANSWER_1, block.timestamp, block.timestamp, ROUND_ID_2);

        // Try to add round 1 (lower ID)
        vm.prank(s_reactiveContract);
        vm.expectRevert(FeedProxy.FeedProxy__StaleRound.selector);
        s_feedProxy.updateRoundData(ROUND_ID_1, ANSWER_1, block.timestamp, block.timestamp, ROUND_ID_1);
    }

    function test_UpdateRoundData_RevertsOnSameRound() public {
        // First add round 1
        vm.prank(s_reactiveContract);
        s_feedProxy.updateRoundData(ROUND_ID_1, ANSWER_1, block.timestamp, block.timestamp, ROUND_ID_1);

        // Advance time so it's not a duplicate check scenario
        vm.warp(block.timestamp + 1);

        // Try to add round 1 again with different timestamp (would be caught as duplicate first)
        // For this test, we need a scenario where round ID equals latest but hasn't been processed
        // This is actually impossible in our implementation - if s_latestRoundId == roundId,
        // then s_processedRounds[roundId] must be true (they're set together)
        // So this test verifies the duplicate handling path instead
        vm.expectEmit(true, false, false, false);
        emit FeedProxy.DuplicateRoundSkipped(ROUND_ID_1);

        vm.prank(s_reactiveContract);
        s_feedProxy.updateRoundData(ROUND_ID_1, ANSWER_2, block.timestamp, block.timestamp, ROUND_ID_1);
    }

    function test_UpdateRoundData_AcceptsSequentialRounds() public {
        vm.startPrank(s_reactiveContract);

        s_feedProxy.updateRoundData(ROUND_ID_1, ANSWER_1, block.timestamp, block.timestamp, ROUND_ID_1);
        assertEq(s_feedProxy.getLatestRoundId(), ROUND_ID_1);

        s_feedProxy.updateRoundData(ROUND_ID_2, ANSWER_2, block.timestamp, block.timestamp, ROUND_ID_2);
        assertEq(s_feedProxy.getLatestRoundId(), ROUND_ID_2);

        vm.stopPrank();
    }

    // ============ Staleness Validation Tests (Task 14) ============

    function test_UpdateRoundData_RevertsOnStaleData() public {
        uint256 staleTimestamp = block.timestamp - STALENESS_THRESHOLD - 1;

        vm.prank(s_reactiveContract);
        vm.expectRevert(FeedProxy.FeedProxy__StaleData.selector);
        s_feedProxy.updateRoundData(ROUND_ID_1, ANSWER_1, staleTimestamp, staleTimestamp, ROUND_ID_1);
    }

    function test_UpdateRoundData_AcceptsFreshData() public {
        uint256 freshTimestamp = block.timestamp - 1 hours;

        vm.prank(s_reactiveContract);
        s_feedProxy.updateRoundData(ROUND_ID_1, ANSWER_1, freshTimestamp, freshTimestamp, ROUND_ID_1);

        assertEq(s_feedProxy.getLatestRoundId(), ROUND_ID_1);
    }

    function test_UpdateRoundData_AcceptsDataAtThreshold() public {
        uint256 thresholdTimestamp = block.timestamp - STALENESS_THRESHOLD;

        vm.prank(s_reactiveContract);
        s_feedProxy.updateRoundData(ROUND_ID_1, ANSWER_1, thresholdTimestamp, thresholdTimestamp, ROUND_ID_1);

        assertEq(s_feedProxy.getLatestRoundId(), ROUND_ID_1);
    }

    // ============ Interface and Getter Function Tests (Task 15) ============

    function test_Decimals_ReturnsConfiguredValue() public view {
        assertEq(s_feedProxy.decimals(), DECIMALS);
    }

    function test_Description_ReturnsConfiguredValue() public view {
        assertEq(s_feedProxy.description(), DESCRIPTION);
    }

    function test_Version_ReturnsOne() public view {
        assertEq(s_feedProxy.version(), 1);
    }

    function test_GetRoundData_ReturnsStoredData() public {
        uint256 timestamp = block.timestamp;

        vm.prank(s_reactiveContract);
        s_feedProxy.updateRoundData(ROUND_ID_1, ANSWER_1, timestamp, timestamp, ROUND_ID_1);

        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            s_feedProxy.getRoundData(ROUND_ID_1);

        assertEq(roundId, ROUND_ID_1);
        assertEq(answer, ANSWER_1);
        assertEq(startedAt, timestamp);
        assertEq(updatedAt, timestamp);
        assertEq(answeredInRound, ROUND_ID_1);
    }

    function test_GetRoundData_RevertsForNonexistentRound() public {
        vm.expectRevert(FeedProxy.FeedProxy__RoundNotFound.selector);
        s_feedProxy.getRoundData(ROUND_ID_1);
    }

    function test_LatestRoundData_ReturnsLatestData() public {
        uint256 timestamp = block.timestamp;

        vm.startPrank(s_reactiveContract);
        s_feedProxy.updateRoundData(ROUND_ID_1, ANSWER_1, timestamp, timestamp, ROUND_ID_1);
        s_feedProxy.updateRoundData(ROUND_ID_2, ANSWER_2, timestamp, timestamp, ROUND_ID_2);
        vm.stopPrank();

        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            s_feedProxy.latestRoundData();

        assertEq(roundId, ROUND_ID_2);
        assertEq(answer, ANSWER_2);
        assertEq(startedAt, timestamp);
        assertEq(updatedAt, timestamp);
        assertEq(answeredInRound, ROUND_ID_2);
    }

    function test_LatestRoundData_RevertsWhenEmpty() public {
        vm.expectRevert(FeedProxy.FeedProxy__RoundNotFound.selector);
        s_feedProxy.latestRoundData();
    }

    function test_GetLatestRoundId_ReturnsZeroInitially() public view {
        assertEq(s_feedProxy.getLatestRoundId(), 0);
    }

    function test_IsRoundProcessed_ReturnsFalseForUnprocessed() public view {
        assertFalse(s_feedProxy.isRoundProcessed(ROUND_ID_1));
    }

    function test_IsRoundProcessed_ReturnsTrueAfterUpdate() public {
        vm.prank(s_reactiveContract);
        s_feedProxy.updateRoundData(ROUND_ID_1, ANSWER_1, block.timestamp, block.timestamp, ROUND_ID_1);

        assertTrue(s_feedProxy.isRoundProcessed(ROUND_ID_1));
    }

    // ============ Event Tests ============

    function test_UpdateRoundData_EmitsAnswerUpdated() public {
        uint256 timestamp = block.timestamp;

        vm.expectEmit(true, true, false, true);
        emit FeedProxy.AnswerUpdated(ANSWER_1, ROUND_ID_1, timestamp);

        vm.prank(s_reactiveContract);
        s_feedProxy.updateRoundData(ROUND_ID_1, ANSWER_1, timestamp, timestamp, ROUND_ID_1);
    }

    // ============ Fuzz Tests (Task 16) ============

    function testFuzz_UpdateRoundData_HandlesValidData(
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

        vm.prank(s_reactiveContract);
        s_feedProxy.updateRoundData(roundId, answer, startedAt, updatedAt, answeredInRound);

        (uint80 retRoundId, int256 retAnswer, uint256 retStartedAt, uint256 retUpdatedAt, uint80 retAnsweredInRound) =
            s_feedProxy.getRoundData(roundId);

        assertEq(retRoundId, roundId);
        assertEq(retAnswer, answer);
        assertEq(retStartedAt, startedAt);
        assertEq(retUpdatedAt, updatedAt);
        assertEq(retAnsweredInRound, answeredInRound);
    }

    function testFuzz_GetRoundData_ReturnsCorrectData(uint80 roundId) public {
        vm.assume(roundId > 0);

        uint256 timestamp = block.timestamp;
        int256 answer = int256(uint256(roundId)) * 1e8;

        vm.prank(s_reactiveContract);
        s_feedProxy.updateRoundData(roundId, answer, timestamp, timestamp, roundId);

        (uint80 retRoundId, int256 retAnswer, uint256 retStartedAt, uint256 retUpdatedAt, uint80 retAnsweredInRound) =
            s_feedProxy.getRoundData(roundId);

        assertEq(retRoundId, roundId);
        assertEq(retAnswer, answer);
        assertEq(retStartedAt, timestamp);
        assertEq(retUpdatedAt, timestamp);
        assertEq(retAnsweredInRound, roundId);
    }
}
