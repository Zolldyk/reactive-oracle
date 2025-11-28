// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IEnhancedOriginHelper
/// @notice Interface for the origin chain helper contract that enriches Chainlink data
/// @dev Emits events when round data is fetched from Chainlink feeds
interface IEnhancedOriginHelper {
    /// @notice Emitted when complete round data is fetched from Chainlink
    /// @param roundId The round identifier from Chainlink
    /// @param answer The price answer with 8 decimals
    /// @param startedAt When the round started
    /// @param updatedAt When the answer was submitted
    /// @param answeredInRound The round when answer was computed
    event RoundDataReceived(
        uint80 indexed roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );

    /// @notice Fetches and emits enriched round data from Chainlink
    /// @param roundId The round ID to fetch data for
    function enrichRoundData(uint80 roundId) external;
}
