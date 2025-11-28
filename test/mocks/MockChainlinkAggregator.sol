// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AggregatorV3Interface} from "../../src/interfaces/AggregatorV3Interface.sol";

/// @title MockChainlinkAggregator
/// @notice Mock implementation of Chainlink AggregatorV3Interface for testing
contract MockChainlinkAggregator is AggregatorV3Interface {
    uint8 private immutable i_decimals;
    string private s_description;

    struct RoundData {
        uint80 roundId;
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;
        bool exists;
    }

    mapping(uint80 => RoundData) private s_rounds;
    uint80 private s_latestRoundId;
    bool private s_shouldRevert;
    bool private s_shouldRevertLatest;

    constructor(uint8 decimals_, string memory description_) {
        i_decimals = decimals_;
        s_description = description_;
    }

    /// @notice Set round data for testing
    function setRoundData(
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) external {
        s_rounds[roundId] = RoundData({
            roundId: roundId,
            answer: answer,
            startedAt: startedAt,
            updatedAt: updatedAt,
            answeredInRound: answeredInRound,
            exists: true
        });

        if (roundId > s_latestRoundId) {
            s_latestRoundId = roundId;
        }
    }

    /// @notice Set latest round data directly for testing
    function setLatestRoundData(
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) external {
        s_rounds[roundId] = RoundData({
            roundId: roundId,
            answer: answer,
            startedAt: startedAt,
            updatedAt: updatedAt,
            answeredInRound: answeredInRound,
            exists: true
        });
        s_latestRoundId = roundId;
    }

    /// @notice Configure mock to revert on getRoundData calls
    function setRevertOnGetRoundData(bool shouldRevert) external {
        s_shouldRevert = shouldRevert;
    }

    /// @notice Configure mock to revert on latestRoundData calls
    function setRevertOnLatestRoundData(bool shouldRevert) external {
        s_shouldRevertLatest = shouldRevert;
    }

    /// @notice Set invalid data (mismatched roundId) for testing
    function setInvalidRoundData(uint80 roundId, uint80 mismatchedRoundId) external {
        s_rounds[roundId] = RoundData({
            roundId: mismatchedRoundId,
            answer: 100000000,
            startedAt: block.timestamp,
            updatedAt: block.timestamp,
            answeredInRound: mismatchedRoundId,
            exists: true
        });
    }

    function decimals() external view override returns (uint8) {
        return i_decimals;
    }

    function description() external view override returns (string memory) {
        return s_description;
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function getRoundData(uint80 _roundId)
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        if (s_shouldRevert) {
            revert("MockChainlinkAggregator: revert enabled");
        }

        RoundData memory data = s_rounds[_roundId];
        if (!data.exists) {
            revert("MockChainlinkAggregator: round not found");
        }

        return (data.roundId, data.answer, data.startedAt, data.updatedAt, data.answeredInRound);
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        if (s_shouldRevertLatest) {
            revert("MockChainlinkAggregator: revert enabled");
        }

        RoundData memory data = s_rounds[s_latestRoundId];
        if (!data.exists) {
            revert("MockChainlinkAggregator: no round data");
        }

        return (data.roundId, data.answer, data.startedAt, data.updatedAt, data.answeredInRound);
    }
}
