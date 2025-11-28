// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AbstractReactive} from "@reactive/abstract-base/AbstractReactive.sol";
import {IReactive} from "@reactive/interfaces/IReactive.sol";
import {REACTIVE_CHAIN_ID, ORIGIN_CALLBACK_GAS, DESTINATION_CALLBACK_GAS} from "../Constants.sol";

/// @title ChainlinkMirrorReactive
/// @author Reactive Oracle Team
/// @notice Reactive contract that orchestrates cross-chain price mirroring from Chainlink to FeedProxy
/// @dev Extends AbstractReactive to subscribe to events and emit callbacks for cross-chain execution
contract ChainlinkMirrorReactive is AbstractReactive {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Received event does not match any subscription
    error ChainlinkMirrorReactive__UnknownEvent();

    /// @notice Insufficient gas allocated for callback
    error ChainlinkMirrorReactive__InsufficientGas();

    /*//////////////////////////////////////////////////////////////
                           TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Pending round awaiting RoundDataReceived event
    /// @param roundId The round identifier from Chainlink
    /// @param timestamp When the round processing started
    /// @param pending Whether the round is currently pending
    struct PendingRound {
        uint80 roundId;
        uint256 timestamp;
        bool pending;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Chainlink AnswerUpdated event signature
    bytes32 public constant ANSWER_UPDATED_TOPIC = keccak256("AnswerUpdated(int256,uint256,uint256)");

    /// @notice EnhancedOriginHelper RoundDataReceived event signature
    bytes32 public constant ROUND_DATA_RECEIVED_TOPIC = keccak256("RoundDataReceived(uint80,int256,uint256,uint256,uint80)");

    /// @notice Cron100 heartbeat topic for ~12 minute intervals
    bytes32 public constant CRON_100_TOPIC = bytes32(uint256(0x64));

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Origin chain ID where Chainlink feeds exist
    uint256 private immutable i_originChainId;

    /// @notice Destination chain ID where FeedProxy is deployed
    uint256 private immutable i_destinationChainId;

    /// @notice Chainlink aggregator address on origin chain
    address private immutable i_chainlinkFeed;

    /// @notice EnhancedOriginHelper address on origin chain
    address private immutable i_originHelper;

    /// @notice FeedProxy address on destination chain
    address private immutable i_feedProxy;

    /// @notice Last processed round ID for deduplication
    uint80 private s_lastProcessedRound;

    /// @notice Mapping of round IDs to their pending state
    mapping(uint80 => PendingRound) private s_pendingRounds;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a round starts processing
    /// @param roundId The round ID being processed
    event RoundProcessingStarted(uint80 indexed roundId);

    /// @notice Emitted when a round is successfully mirrored
    /// @param roundId The round ID that was mirrored
    /// @param answer The price answer that was mirrored
    event RoundMirrored(uint80 indexed roundId, int256 answer);

    /// @notice Emitted when a duplicate round is skipped
    /// @param roundId The round ID that was skipped
    event DuplicateRoundSkipped(uint80 indexed roundId);

    /// @notice Emitted when cron fallback triggers
    /// @param timestamp The timestamp of the cron trigger
    event CronFallbackTriggered(uint256 timestamp);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the reactive contract with chain and contract configuration
    /// @param originChainId Origin chain ID where Chainlink feeds exist
    /// @param destinationChainId Destination chain ID where FeedProxy is deployed
    /// @param chainlinkFeed Chainlink aggregator address on origin chain
    /// @param originHelper EnhancedOriginHelper address on origin chain
    /// @param feedProxy FeedProxy address on destination chain
    constructor(
        uint256 originChainId,
        uint256 destinationChainId,
        address chainlinkFeed,
        address originHelper,
        address feedProxy
    ) {
        i_originChainId = originChainId;
        i_destinationChainId = destinationChainId;
        i_chainlinkFeed = chainlinkFeed;
        i_originHelper = originHelper;
        i_feedProxy = feedProxy;

        // Subscribe to Chainlink AnswerUpdated events on origin chain
        service.subscribe(
            originChainId,
            chainlinkFeed,
            uint256(ANSWER_UPDATED_TOPIC),
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );

        // Subscribe to RoundDataReceived events from EnhancedOriginHelper
        service.subscribe(
            originChainId,
            originHelper,
            uint256(ROUND_DATA_RECEIVED_TOPIC),
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );

        // Subscribe to Cron100 heartbeat for fallback checks
        service.subscribe(
            REACTIVE_CHAIN_ID,
            address(0),
            uint256(CRON_100_TOPIC),
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Entry point for handling new event notifications
    /// @param log Data structure containing the information about the intercepted log record
    function react(LogRecord calldata log) external override vmOnly {
        bytes32 topic0 = bytes32(log.topic_0);
        address origin = log._contract;

        if (topic0 == ANSWER_UPDATED_TOPIC && origin == i_chainlinkFeed) {
            _handleAnswerUpdated(log);
        } else if (topic0 == ROUND_DATA_RECEIVED_TOPIC && origin == i_originHelper) {
            _handleRoundDataReceived(log);
        } else if (topic0 == CRON_100_TOPIC) {
            _handleCronHeartbeat();
        } else {
            revert ChainlinkMirrorReactive__UnknownEvent();
        }
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Handles Chainlink AnswerUpdated events
    /// @param log The log record containing the event data
    function _handleAnswerUpdated(LogRecord calldata log) internal {
        // Extract roundId from topic_2 (second indexed parameter)
        uint80 roundId = uint80(log.topic_2);

        // Check deduplication: skip if already processed
        if (roundId <= s_lastProcessedRound) {
            emit DuplicateRoundSkipped(roundId);
            return;
        }

        // Check if round is already pending
        if (s_pendingRounds[roundId].pending) {
            emit DuplicateRoundSkipped(roundId);
            return;
        }

        // Mark round as pending
        s_pendingRounds[roundId] = PendingRound({
            roundId: roundId,
            timestamp: block.timestamp,
            pending: true
        });

        emit RoundProcessingStarted(roundId);

        // Emit callback to EnhancedOriginHelper to enrich the round data
        emit Callback(
            i_originChainId,
            i_originHelper,
            uint64(ORIGIN_CALLBACK_GAS),
            abi.encodeWithSignature("enrichRoundData(uint80)", roundId)
        );
    }

    /// @notice Handles RoundDataReceived events from EnhancedOriginHelper
    /// @param log The log record containing the event data
    function _handleRoundDataReceived(LogRecord calldata log) internal {
        // Extract roundId from topic_1 (first indexed parameter)
        uint80 roundId = uint80(log.topic_1);

        // Decode non-indexed data: (answer, startedAt, updatedAt, answeredInRound)
        (int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            abi.decode(log.data, (int256, uint256, uint256, uint80));

        // Clear pending state
        delete s_pendingRounds[roundId];

        // Update last processed round if this is newer
        if (roundId > s_lastProcessedRound) {
            s_lastProcessedRound = roundId;
        }

        emit RoundMirrored(roundId, answer);

        // Emit callback to FeedProxy to update round data
        emit Callback(
            i_destinationChainId,
            i_feedProxy,
            uint64(DESTINATION_CALLBACK_GAS),
            abi.encodeWithSignature(
                "updateRoundData(uint80,int256,uint256,uint256,uint80)",
                roundId,
                answer,
                startedAt,
                updatedAt,
                answeredInRound
            )
        );
    }

    /// @notice Handles Cron100 heartbeat events for fallback checks
    function _handleCronHeartbeat() internal {
        emit CronFallbackTriggered(block.timestamp);

        // Emit callback to EnhancedOriginHelper to enrich latest round
        emit Callback(
            i_originChainId,
            i_originHelper,
            uint64(ORIGIN_CALLBACK_GAS),
            abi.encodeWithSignature("enrichLatestRound()")
        );
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the last processed round ID
    /// @return The last processed round ID
    function getLastProcessedRound() external view returns (uint80) {
        return s_lastProcessedRound;
    }

    /// @notice Checks if a round is currently pending
    /// @param roundId The round ID to check
    /// @return True if the round is pending, false otherwise
    function isRoundPending(uint80 roundId) external view returns (bool) {
        return s_pendingRounds[roundId].pending;
    }

    /// @notice Returns the contract configuration
    /// @return originChainId Origin chain ID
    /// @return destinationChainId Destination chain ID
    /// @return chainlinkFeed Chainlink aggregator address
    /// @return originHelper EnhancedOriginHelper address
    /// @return feedProxy FeedProxy address
    function getConfiguration()
        external
        view
        returns (
            uint256 originChainId,
            uint256 destinationChainId,
            address chainlinkFeed,
            address originHelper,
            address feedProxy
        )
    {
        return (
            i_originChainId,
            i_destinationChainId,
            i_chainlinkFeed,
            i_originHelper,
            i_feedProxy
        );
    }
}
