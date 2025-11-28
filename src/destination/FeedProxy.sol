// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";
import {IChainlinkMirror} from "../interfaces/IChainlinkMirror.sol";

/// @title FeedProxy
/// @author Reactive Oracle Team
/// @notice Chainlink-compatible price feed proxy that receives data from Reactive Network
/// @dev Implements AggregatorV3Interface for seamless integration with existing DeFi protocols
contract FeedProxy is AggregatorV3Interface, IChainlinkMirror {
    // ============ Errors ============

    /// @notice Thrown when caller is not the authorized reactive contract
    error FeedProxy__UnauthorizedCaller();

    /// @notice Thrown when requested round data does not exist
    error FeedProxy__RoundNotFound();

    /// @notice Thrown when round ID is not greater than current latest
    error FeedProxy__StaleRound();

    /// @notice Thrown when data timestamp is older than staleness threshold
    error FeedProxy__StaleData();

    // ============ Type Declarations ============

    /// @notice Complete round data structure matching Chainlink's format
    /// @param answer Price with configured decimals
    /// @param startedAt Round start timestamp
    /// @param updatedAt Answer submission timestamp
    /// @param answeredInRound Round when answer was computed
    struct RoundData {
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;
    }

    // ============ Constants ============

    /// @notice Maximum age of data allowed for updates (2 hours)
    uint256 private constant STALENESS_THRESHOLD = 2 hours;

    // ============ Immutables ============

    /// @notice Address of the authorized reactive contract
    address private immutable i_reactiveContract;

    /// @notice Number of decimals for price data
    uint8 private immutable i_decimals;

    // ============ State Variables ============

    /// @notice Human-readable description of the price feed
    string private s_description;

    /// @notice Latest processed round ID
    uint80 private s_latestRoundId;

    /// @notice Mapping of round ID to round data
    mapping(uint80 => RoundData) private s_rounds;

    /// @notice Mapping to track processed rounds for duplicate prevention
    mapping(uint80 => bool) private s_processedRounds;

    // ============ Events ============

    /// @notice Emitted when a new round is successfully stored
    /// @param answer The price answer
    /// @param roundId The round identifier
    /// @param timestamp The update timestamp
    event AnswerUpdated(int256 indexed answer, uint256 indexed roundId, uint256 timestamp);

    /// @notice Emitted when a duplicate round is rejected
    /// @param roundId The duplicate round identifier
    event DuplicateRoundSkipped(uint80 indexed roundId);

    // ============ Modifiers ============

    /// @notice Restricts function access to the reactive contract only
    modifier onlyReactive() {
        if (msg.sender != i_reactiveContract) {
            revert FeedProxy__UnauthorizedCaller();
        }
        _;
    }

    // ============ Constructor ============

    /// @notice Initializes the FeedProxy with configuration parameters
    /// @param reactiveContract Address of the authorized reactive contract
    /// @param decimals_ Number of decimals for price data
    /// @param description_ Human-readable description of the feed
    constructor(address reactiveContract, uint8 decimals_, string memory description_) {
        i_reactiveContract = reactiveContract;
        i_decimals = decimals_;
        s_description = description_;
    }

    // ============ External Functions ============

    /// @inheritdoc IChainlinkMirror
    function updateRoundData(
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) external onlyReactive {
        // Check for duplicate round (idempotent handling)
        if (s_processedRounds[roundId]) {
            emit DuplicateRoundSkipped(roundId);
            return;
        }

        // Validate sequential round ordering
        if (roundId <= s_latestRoundId) {
            revert FeedProxy__StaleRound();
        }

        // Validate data freshness
        if (block.timestamp - updatedAt > STALENESS_THRESHOLD) {
            revert FeedProxy__StaleData();
        }

        // Store round data (Effects)
        s_rounds[roundId] = RoundData({
            answer: answer,
            startedAt: startedAt,
            updatedAt: updatedAt,
            answeredInRound: answeredInRound
        });

        // Mark round as processed
        s_processedRounds[roundId] = true;

        // Update latest round ID
        s_latestRoundId = roundId;

        // Emit event
        emit AnswerUpdated(answer, roundId, updatedAt);
    }

    // ============ View Functions ============

    /// @inheritdoc AggregatorV3Interface
    function decimals() external view returns (uint8) {
        return i_decimals;
    }

    /// @inheritdoc AggregatorV3Interface
    function description() external view returns (string memory) {
        return s_description;
    }

    /// @inheritdoc AggregatorV3Interface
    function version() external pure returns (uint256) {
        return 1;
    }

    /// @inheritdoc AggregatorV3Interface
    function getRoundData(uint80 _roundId)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        RoundData storage round = s_rounds[_roundId];

        // Check if round exists (answeredInRound will be 0 for non-existent rounds)
        if (!s_processedRounds[_roundId]) {
            revert FeedProxy__RoundNotFound();
        }

        return (_roundId, round.answer, round.startedAt, round.updatedAt, round.answeredInRound);
    }

    /// @inheritdoc AggregatorV3Interface
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        if (s_latestRoundId == 0) {
            revert FeedProxy__RoundNotFound();
        }

        RoundData storage round = s_rounds[s_latestRoundId];
        return (s_latestRoundId, round.answer, round.startedAt, round.updatedAt, round.answeredInRound);
    }

    /// @notice Returns the address of the authorized reactive contract
    /// @return The reactive contract address
    function getReactiveContract() external view returns (address) {
        return i_reactiveContract;
    }

    /// @notice Returns the latest processed round ID
    /// @return The latest round ID
    function getLatestRoundId() external view returns (uint80) {
        return s_latestRoundId;
    }

    /// @notice Checks if a round has been processed
    /// @param roundId The round ID to check
    /// @return True if the round has been processed
    function isRoundProcessed(uint80 roundId) external view returns (bool) {
        return s_processedRounds[roundId];
    }
}
