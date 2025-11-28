// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title AggregatorV3Interface
/// @notice Chainlink's standard price feed interface
/// @dev Used for reading price data from Chainlink oracles
interface AggregatorV3Interface {
    /// @notice Returns the number of decimals in the response
    /// @return The number of decimals
    function decimals() external view returns (uint8);

    /// @notice Returns a description of the aggregator
    /// @return The description string
    function description() external view returns (string memory);

    /// @notice Returns the version number of the aggregator
    /// @return The version number
    function version() external view returns (uint256);

    /// @notice Returns round data for a specific round
    /// @param _roundId The round ID to retrieve data for
    /// @return roundId The round ID
    /// @return answer The price answer
    /// @return startedAt When the round started
    /// @return updatedAt When the answer was submitted
    /// @return answeredInRound The round when the answer was computed
    function getRoundData(uint80 _roundId)
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

    /// @notice Returns the latest round data
    /// @return roundId The round ID
    /// @return answer The price answer
    /// @return startedAt When the round started
    /// @return updatedAt When the answer was submitted
    /// @return answeredInRound The round when the answer was computed
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}
