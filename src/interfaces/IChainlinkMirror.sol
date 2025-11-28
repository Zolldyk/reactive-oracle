// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IChainlinkMirror
/// @notice Interface for the destination chain FeedProxy callback
/// @dev Implemented by contracts that receive mirrored Chainlink data
interface IChainlinkMirror {
    /// @notice Updates round data received from the reactive contract
    /// @dev Called by RVM via callback proxy - must verify msg.sender
    /// @param roundId The round identifier from Chainlink
    /// @param answer The price answer with 8 decimals
    /// @param startedAt When the round started
    /// @param updatedAt When the answer was submitted
    /// @param answeredInRound The round when answer was computed
    function updateRoundData(
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) external;
}
