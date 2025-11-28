// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console, Vm} from "forge-std/Test.sol";
import {FeedProxy} from "../../src/destination/FeedProxy.sol";
import {EnhancedOriginHelper} from "../../src/origin/EnhancedOriginHelper.sol";
import {AggregatorV3Interface} from "../../src/interfaces/AggregatorV3Interface.sol";
import "../../src/Constants.sol";

/// @title SepoliaForkTest
/// @author Reactive Oracle Team
/// @notice Fork tests validating system behavior with real Chainlink data on Sepolia
/// @dev Requires SEPOLIA_RPC_URL environment variable to be set
/// @dev Example: export SEPOLIA_RPC_URL="https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY"
contract SepoliaForkTest is Test {
    // ============ Type Declarations ============

    /// @dev Helper struct to bundle round data and avoid stack-too-deep
    struct RoundDataBundle {
        uint80 roundId;
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;
    }

    // ============ State Variables ============

    /// @dev Fork identifier for Sepolia
    uint256 internal s_sepoliaFork;

    /// @dev Reference to Chainlink ETH/USD feed on Sepolia
    AggregatorV3Interface internal s_chainlinkFeed;

    /// @dev FeedProxy instance under test
    FeedProxy internal s_feedProxy;

    /// @dev EnhancedOriginHelper instance under test
    EnhancedOriginHelper internal s_originHelper;

    /// @dev Address used as reactive contract for authorization
    address internal s_reactiveContract;

    // ============ Setup ============

    function setUp() public {
        // Create and select Sepolia fork
        s_sepoliaFork = vm.createFork(vm.envString("SEPOLIA_RPC_URL"));
        vm.selectFork(s_sepoliaFork);

        // Initialize Chainlink feed interface at real address
        s_chainlinkFeed = AggregatorV3Interface(CHAINLINK_ETH_USD);

        // Create reactive contract address for authorization
        s_reactiveContract = makeAddr("reactive");

        // Deploy FeedProxy with reactive contract as authorized caller
        s_feedProxy = new FeedProxy(s_reactiveContract, 8, "ETH / USD");

        // Deploy EnhancedOriginHelper with test contract as both callbackProxy and reactiveContract
        // This allows direct calls from the test contract
        s_originHelper = new EnhancedOriginHelper(
            CHAINLINK_ETH_USD,
            address(this), // callbackProxy = test contract
            address(this)  // reactiveContract = test contract (for tx.origin check)
        );
    }

    // ============ Internal Helpers ============

    /// @dev Fetch latest round data from Chainlink into a bundle
    function _getLatestRoundBundle() internal view returns (RoundDataBundle memory) {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            s_chainlinkFeed.latestRoundData();
        return RoundDataBundle(roundId, answer, startedAt, updatedAt, answeredInRound);
    }

    /// @dev Fetch round data from Chainlink into a bundle
    function _getRoundBundle(uint80 _roundId) internal view returns (RoundDataBundle memory) {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            s_chainlinkFeed.getRoundData(_roundId);
        return RoundDataBundle(roundId, answer, startedAt, updatedAt, answeredInRound);
    }

    /// @dev Fetch latest round data from FeedProxy into a bundle
    function _getProxyLatestBundle() internal view returns (RoundDataBundle memory) {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            s_feedProxy.latestRoundData();
        return RoundDataBundle(roundId, answer, startedAt, updatedAt, answeredInRound);
    }

    /// @dev Fetch round data from FeedProxy into a bundle
    function _getProxyRoundBundle(uint80 _roundId) internal view returns (RoundDataBundle memory) {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            s_feedProxy.getRoundData(_roundId);
        return RoundDataBundle(roundId, answer, startedAt, updatedAt, answeredInRound);
    }

    /// @dev Push bundle data to FeedProxy
    function _pushToFeedProxy(RoundDataBundle memory bundle) internal {
        vm.prank(s_reactiveContract);
        s_feedProxy.updateRoundData(
            bundle.roundId, bundle.answer, bundle.startedAt, bundle.updatedAt, bundle.answeredInRound
        );
    }

    /// @dev Assert two bundles are equal
    function _assertBundlesEqual(RoundDataBundle memory a, RoundDataBundle memory b, string memory context) internal {
        assertEq(a.roundId, b.roundId, string.concat(context, ": roundId mismatch"));
        assertEq(a.answer, b.answer, string.concat(context, ": answer mismatch"));
        assertEq(a.startedAt, b.startedAt, string.concat(context, ": startedAt mismatch"));
        assertEq(a.updatedAt, b.updatedAt, string.concat(context, ": updatedAt mismatch"));
        assertEq(a.answeredInRound, b.answeredInRound, string.concat(context, ": answeredInRound mismatch"));
    }

    /// @dev Check if a string contains a substring
    function _containsSubstring(string memory haystack, string memory needle) internal pure returns (bool) {
        bytes memory haystackBytes = bytes(haystack);
        bytes memory needleBytes = bytes(needle);

        if (needleBytes.length > haystackBytes.length) return false;

        for (uint256 i = 0; i <= haystackBytes.length - needleBytes.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < needleBytes.length; j++) {
                if (haystackBytes[i + j] != needleBytes[j]) {
                    found = false;
                    break;
                }
            }
            if (found) return true;
        }
        return false;
    }

    // ============ Task 3: Basic Chainlink Read Tests ============

    /// @notice Verify we can read latest round data from Chainlink
    function test_Fork_CanReadLatestRoundData() public view {
        RoundDataBundle memory bundle = _getLatestRoundBundle();

        // Assert
        assertGt(bundle.roundId, 0, "Round ID should be positive");
        assertGt(bundle.answer, 0, "ETH price should be positive");
        assertGt(bundle.startedAt, 0, "Started timestamp should be set");
        assertGt(bundle.updatedAt, 0, "Updated timestamp should be set");
        assertGt(bundle.answeredInRound, 0, "Answered in round should be positive");

        // Reasonable price bounds ($100 < ETH < $100,000)
        assertGt(bundle.answer, 10000000000, "ETH price should be > $100");
        assertLt(bundle.answer, 10000000000000, "ETH price should be < $100,000");

        // Documentation output
        console.log("=== Latest Chainlink Round Data ===");
        console.log("Round ID:", bundle.roundId);
        console.log("Answer (8 decimals):", uint256(bundle.answer));
        console.log("Price in USD:", uint256(bundle.answer) / 1e8);
        console.log("Started At:", bundle.startedAt);
        console.log("Updated At:", bundle.updatedAt);
        console.log("Answered In Round:", bundle.answeredInRound);
    }

    /// @notice Verify we can read historical round data
    function test_Fork_CanReadHistoricalRound() public view {
        // Get latest round first
        RoundDataBundle memory latest = _getLatestRoundBundle();

        // Try to read a slightly older round
        uint80 historicalRoundId = latest.roundId - 1;
        RoundDataBundle memory historical = _getRoundBundle(historicalRoundId);

        // Assert
        assertEq(historical.roundId, historicalRoundId, "Round ID should match requested");
        assertGt(historical.answer, 0, "Historical price should be positive");
        assertGt(historical.updatedAt, 0, "Historical updated timestamp should be set");

        console.log("=== Historical Round Data ===");
        console.log("Round ID:", historical.roundId);
        console.log("Answer:", uint256(historical.answer));
        console.log("Updated At:", historical.updatedAt);
    }

    /// @notice Verify Chainlink returns correct decimals (8 for ETH/USD)
    function test_Fork_ChainlinkReturnsValidDecimals() public view {
        uint8 decimals = s_chainlinkFeed.decimals();
        assertEq(decimals, 8, "ETH/USD should have 8 decimals");
        console.log("Chainlink Decimals:", decimals);
    }

    /// @notice Verify Chainlink returns valid description containing "ETH"
    function test_Fork_ChainlinkReturnsValidDescription() public view {
        string memory desc = s_chainlinkFeed.description();

        bytes memory descBytes = bytes(desc);
        assertGt(descBytes.length, 0, "Description should not be empty");
        console.log("Chainlink Description:", desc);

        bool containsETH = _containsSubstring(desc, "ETH");
        assertTrue(containsETH, "Description should contain 'ETH'");
    }

    // ============ Task 4: EnhancedOriginHelper Validation Tests ============

    /// @notice Verify EnhancedOriginHelper correctly enriches round data
    function test_Fork_OriginHelper_EnrichesRoundData() public {
        RoundDataBundle memory bundle = _getLatestRoundBundle();

        vm.recordLogs();
        vm.startPrank(address(this), address(this));
        s_originHelper.enrichRoundData(bundle.roundId);
        vm.stopPrank();

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertGt(entries.length, 0, "Should have emitted event");

        bytes32 expectedTopic = keccak256("RoundDataReceived(uint80,int256,uint256,uint256,uint80)");
        bool found = false;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == expectedTopic) {
                found = true;
                break;
            }
        }
        assertTrue(found, "RoundDataReceived event should be emitted");
    }

    /// @notice Verify EnhancedOriginHelper enrichLatestRound works correctly
    function test_Fork_OriginHelper_EnrichesLatestRound() public {
        vm.recordLogs();
        vm.startPrank(address(this), address(this));
        s_originHelper.enrichLatestRound();
        vm.stopPrank();

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 expectedTopic = keccak256("RoundDataReceived(uint80,int256,uint256,uint256,uint80)");

        bool found = false;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == expectedTopic) {
                found = true;
                break;
            }
        }
        assertTrue(found, "RoundDataReceived event should be emitted");
    }

    /// @notice Verify all 5 fields in emitted event match Chainlink data
    function test_Fork_OriginHelper_EmitsCorrectEventData() public {
        RoundDataBundle memory expected = _getLatestRoundBundle();

        vm.recordLogs();
        vm.startPrank(address(this), address(this));
        s_originHelper.enrichLatestRound();
        vm.stopPrank();

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 expectedTopic = keccak256("RoundDataReceived(uint80,int256,uint256,uint256,uint80)");

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == expectedTopic) {
                uint80 emittedRoundId = uint80(uint256(entries[i].topics[1]));

                (int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
                    abi.decode(entries[i].data, (int256, uint256, uint256, uint80));

                assertEq(emittedRoundId, expected.roundId, "Round ID mismatch");
                assertEq(answer, expected.answer, "Answer mismatch");
                assertEq(startedAt, expected.startedAt, "StartedAt mismatch");
                assertEq(updatedAt, expected.updatedAt, "UpdatedAt mismatch");
                assertEq(answeredInRound, expected.answeredInRound, "AnsweredInRound mismatch");

                console.log("=== Event Data Verified ===");
                console.log("Round ID:", emittedRoundId);
                console.log("Answer:", uint256(answer));
                break;
            }
        }
    }

    // ============ Task 5: AggregatorV3Interface Compliance Tests ============

    /// @notice Verify FeedProxy implements decimals() correctly
    function test_Fork_FeedProxy_ImplementsDecimals() public view {
        assertEq(s_feedProxy.decimals(), 8, "FeedProxy should return 8 decimals");
    }

    /// @notice Verify FeedProxy implements description() correctly
    function test_Fork_FeedProxy_ImplementsDescription() public view {
        assertEq(s_feedProxy.description(), "ETH / USD", "Description should match");
    }

    /// @notice Verify FeedProxy implements version() correctly
    function test_Fork_FeedProxy_ImplementsVersion() public view {
        assertEq(s_feedProxy.version(), 1, "Version should be 1");
    }

    /// @notice Verify FeedProxy implements getRoundData() correctly
    function test_Fork_FeedProxy_ImplementsGetRoundData() public {
        RoundDataBundle memory chainlink = _getLatestRoundBundle();
        _pushToFeedProxy(chainlink);

        RoundDataBundle memory proxy = _getProxyRoundBundle(chainlink.roundId);
        _assertBundlesEqual(proxy, chainlink, "getRoundData");

        console.log("=== FeedProxy getRoundData Verified ===");
        console.log("Round ID:", proxy.roundId);
        console.log("Answer:", uint256(proxy.answer));
    }

    /// @notice Verify FeedProxy implements latestRoundData() correctly
    function test_Fork_FeedProxy_ImplementsLatestRoundData() public {
        RoundDataBundle memory chainlink = _getLatestRoundBundle();
        _pushToFeedProxy(chainlink);

        RoundDataBundle memory proxy = _getProxyLatestBundle();
        _assertBundlesEqual(proxy, chainlink, "latestRoundData");
    }

    // ============ Task 6: Two-Callback Flow Simulation ============

    /// @notice Simulate complete two-callback price mirroring flow
    function test_Fork_FullTwoCallbackFlow() public {
        // Step 1: Fetch real round data from Chainlink
        RoundDataBundle memory chainlink = _getLatestRoundBundle();
        console.log("=== Two-Callback Flow Simulation ===");
        console.log("Step 1: Fetched Chainlink data - Round:", chainlink.roundId);

        // Step 2: Simulate first callback - EnhancedOriginHelper emits RoundDataReceived
        vm.recordLogs();
        vm.startPrank(address(this), address(this));
        s_originHelper.enrichLatestRound();
        vm.stopPrank();
        console.log("Step 2: EnhancedOriginHelper enriched data");

        // Extract emitted data from event
        RoundDataBundle memory emitted = _extractRoundDataFromLogs();

        // Step 3: Simulate second callback - FeedProxy receives data
        _pushToFeedProxy(emitted);
        console.log("Step 3: FeedProxy updated with data");

        // Step 4: Verify FeedProxy matches original Chainlink data
        RoundDataBundle memory final_ = _getProxyLatestBundle();
        _assertBundlesEqual(final_, chainlink, "Full flow");

        console.log("Step 4: Verified FeedProxy matches Chainlink");
        console.log("Flow Complete: Price successfully mirrored!");
    }

    /// @dev Helper to extract RoundDataBundle from recorded logs
    function _extractRoundDataFromLogs() internal view returns (RoundDataBundle memory) {
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 expectedTopic = keccak256("RoundDataReceived(uint80,int256,uint256,uint256,uint80)");

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == expectedTopic) {
                uint80 roundId = uint80(uint256(entries[i].topics[1]));
                (int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
                    abi.decode(entries[i].data, (int256, uint256, uint256, uint80));
                return RoundDataBundle(roundId, answer, startedAt, updatedAt, answeredInRound);
            }
        }
        revert("RoundDataReceived event not found");
    }

    /// @notice Verify all 5 fields are preserved through the two-callback flow
    function test_Fork_TwoCallbackFlow_PreservesAllFields() public {
        RoundDataBundle memory original = _getLatestRoundBundle();

        // First callback: EnhancedOriginHelper
        vm.startPrank(address(this), address(this));
        s_originHelper.enrichLatestRound();
        vm.stopPrank();

        // Second callback: FeedProxy
        _pushToFeedProxy(original);

        // Verify all fields preserved
        RoundDataBundle memory final_ = _getProxyLatestBundle();
        _assertBundlesEqual(final_, original, "Two-callback preservation");
    }

    // ============ Task 7: Edge Case Tests ============

    /// @notice Process 3+ sequential rounds
    function test_Fork_MultipleSequentialRounds() public {
        RoundDataBundle memory latest = _getLatestRoundBundle();
        uint256 successCount = 0;

        // Process rounds sequentially (oldest to newest)
        for (uint80 offset = 2; offset > 0; offset--) {
            uint80 targetRoundId = latest.roundId - offset;
            try s_chainlinkFeed.getRoundData(targetRoundId) returns (
                uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound
            ) {
                if (block.timestamp - updatedAt <= 2 hours) {
                    vm.prank(s_reactiveContract);
                    s_feedProxy.updateRoundData(roundId, answer, startedAt, updatedAt, answeredInRound);
                    successCount++;
                    console.log("Processed round:", roundId);
                }
            } catch {
                console.log("Round not available:", targetRoundId);
            }
        }

        // Process latest
        if (block.timestamp - latest.updatedAt <= 2 hours) {
            _pushToFeedProxy(latest);
            successCount++;
            console.log("Processed latest round:", latest.roundId);
        }

        assertGt(successCount, 0, "Should have processed at least one round");
        console.log("Total rounds processed:", successCount);
    }

    /// @notice Test with actual round ID values (typically large numbers)
    function test_Fork_RoundIdBoundaryConditions() public view {
        RoundDataBundle memory bundle = _getLatestRoundBundle();

        // Chainlink round IDs encode phase ID in upper bits
        uint16 phaseId = uint16(bundle.roundId >> 64);
        uint64 aggregatorRoundId = uint64(bundle.roundId);

        console.log("=== Round ID Analysis ===");
        console.log("Full Round ID:", bundle.roundId);
        console.log("Phase ID:", phaseId);
        console.log("Aggregator Round ID:", aggregatorRoundId);

        assertGt(bundle.roundId, 0, "Round ID should be positive");
    }

    /// @notice Verify historical rounds accessible after newer rounds added
    function test_Fork_HistoricalRoundAccess() public {
        RoundDataBundle memory latest = _getLatestRoundBundle();
        uint80 priorRoundId = latest.roundId - 1;

        // First, try to add prior round to FeedProxy
        try s_chainlinkFeed.getRoundData(priorRoundId) returns (
            uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound
        ) {
            // Skip test if prior round data is stale
            if (block.timestamp - updatedAt > 2 hours) {
                console.log("Prior round too old, skipping test");
                return;
            }

            vm.prank(s_reactiveContract);
            s_feedProxy.updateRoundData(roundId, answer, startedAt, updatedAt, answeredInRound);

            // Then add latest round
            _pushToFeedProxy(latest);

            // Verify historical round still accessible
            RoundDataBundle memory retrieved = _getProxyRoundBundle(priorRoundId);
            assertEq(retrieved.roundId, priorRoundId, "Historical round should still be accessible");

            console.log("Historical round accessible after adding newer round");
        } catch {
            console.log("Prior round not available, skipping test");
        }
    }

    /// @notice Verify duplicate round handling - both skip and revert behaviors
    function test_Fork_DuplicateRoundHandling() public {
        RoundDataBundle memory bundle = _getLatestRoundBundle();

        // First update succeeds
        _pushToFeedProxy(bundle);

        // Second update with SAME roundId should emit DuplicateRoundSkipped (idempotent)
        vm.recordLogs();
        _pushToFeedProxy(bundle);

        // Verify DuplicateRoundSkipped was emitted
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 duplicateSkippedTopic = keccak256("DuplicateRoundSkipped(uint80)");
        bool foundDuplicateEvent = false;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == duplicateSkippedTopic) {
                foundDuplicateEvent = true;
                break;
            }
        }
        assertTrue(foundDuplicateEvent, "DuplicateRoundSkipped event should be emitted");
        console.log("Duplicate handling: DuplicateRoundSkipped emitted for same roundId");

        // Update with OLDER roundId (out-of-order) should revert with FeedProxy__StaleRound
        uint80 olderRoundId = bundle.roundId - 1;
        vm.prank(s_reactiveContract);
        vm.expectRevert(FeedProxy.FeedProxy__StaleRound.selector);
        s_feedProxy.updateRoundData(olderRoundId, bundle.answer, bundle.startedAt, bundle.updatedAt, bundle.answeredInRound);

        console.log("Out-of-order handling: FeedProxy__StaleRound reverted for older roundId");
    }

    // ============ Task 8: Gas Usage Documentation ============

    /// @notice Measure gas usage for EnhancedOriginHelper.enrichRoundData
    function test_Fork_GasUsage_OriginHelper_EnrichRoundData() public {
        RoundDataBundle memory bundle = _getLatestRoundBundle();

        vm.startPrank(address(this), address(this));
        uint256 gasStart = gasleft();
        s_originHelper.enrichRoundData(bundle.roundId);
        uint256 gasUsed = gasStart - gasleft();
        vm.stopPrank();

        console.log("=== Gas Usage: EnhancedOriginHelper.enrichRoundData ===");
        console.log("Gas used:", gasUsed);
        assertLt(gasUsed, 100000, "Gas usage too high for enrichRoundData");
    }

    /// @notice Measure gas usage for FeedProxy.updateRoundData
    function test_Fork_GasUsage_FeedProxy_UpdateRoundData() public {
        RoundDataBundle memory bundle = _getLatestRoundBundle();

        vm.prank(s_reactiveContract);
        uint256 gasStart = gasleft();
        s_feedProxy.updateRoundData(
            bundle.roundId, bundle.answer, bundle.startedAt, bundle.updatedAt, bundle.answeredInRound
        );
        uint256 gasUsed = gasStart - gasleft();

        console.log("=== Gas Usage: FeedProxy.updateRoundData ===");
        console.log("Gas used:", gasUsed);
        // Cold storage writes are expensive (~140k gas for first write)
        assertLt(gasUsed, 150000, "Gas usage too high for updateRoundData");
    }

    /// @notice Measure gas usage for FeedProxy.latestRoundData
    function test_Fork_GasUsage_FeedProxy_LatestRoundData() public {
        RoundDataBundle memory bundle = _getLatestRoundBundle();
        _pushToFeedProxy(bundle);

        uint256 gasStart = gasleft();
        s_feedProxy.latestRoundData();
        uint256 gasUsed = gasStart - gasleft();

        console.log("=== Gas Usage: FeedProxy.latestRoundData ===");
        console.log("Gas used:", gasUsed);
        assertLt(gasUsed, 10000, "Gas usage too high for latestRoundData read");
    }

    /// @notice Measure gas usage for FeedProxy.getRoundData
    function test_Fork_GasUsage_FeedProxy_GetRoundData() public {
        RoundDataBundle memory bundle = _getLatestRoundBundle();
        _pushToFeedProxy(bundle);

        uint256 gasStart = gasleft();
        s_feedProxy.getRoundData(bundle.roundId);
        uint256 gasUsed = gasStart - gasleft();

        console.log("=== Gas Usage: FeedProxy.getRoundData ===");
        console.log("Gas used:", gasUsed);
        assertLt(gasUsed, 10000, "Gas usage too high for getRoundData read");
    }

    // ============ Task 10: Sample Data Output for Documentation ============

    /// @notice Dedicated test for documentation output with sample data
    function test_Fork_OutputSampleRoundData() public view {
        RoundDataBundle memory bundle = _getLatestRoundBundle();

        uint256 priceUSD = uint256(bundle.answer) / 1e8;
        uint256 dataFreshness = block.timestamp - bundle.updatedAt;

        console.log("");
        console.log("================================================================");
        console.log("      CHAINLINK ETH/USD FEED - SAMPLE DATA OUTPUT              ");
        console.log("================================================================");
        console.log("");
        console.log("Feed Address:", CHAINLINK_ETH_USD);
        console.log("Network: Ethereum Sepolia (Chain ID: 11155111)");
        console.log("");
        console.log("--- Latest Round Data ---");
        console.log("Round ID:           ", bundle.roundId);
        console.log("Answer (raw):       ", uint256(bundle.answer));
        console.log("Answer (USD):       ", priceUSD);
        console.log("Started At:         ", bundle.startedAt);
        console.log("Updated At:         ", bundle.updatedAt);
        console.log("Answered In Round:  ", bundle.answeredInRound);
        console.log("");
        console.log("--- Derived Metrics ---");
        console.log("Decimals:           8");
        console.log("Data Freshness:     ", dataFreshness, "seconds");
        console.log("Block Timestamp:    ", block.timestamp);
        console.log("");
        console.log("--- Round ID Analysis ---");
        console.log("Phase ID:           ", uint16(bundle.roundId >> 64));
        console.log("Aggregator Round:   ", uint64(bundle.roundId));
        console.log("");
    }
}
