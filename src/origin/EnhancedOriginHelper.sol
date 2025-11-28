// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";
import {IEnhancedOriginHelper} from "../interfaces/IEnhancedOriginHelper.sol";

/// @title EnhancedOriginHelper
/// @author Reactive Oracle Team
/// @notice Origin chain helper that enriches Chainlink events with complete round data
/// @dev Fetches round data from Chainlink and emits events for reactive contract consumption
contract EnhancedOriginHelper is IEnhancedOriginHelper {
    // ============ Errors ============

    /// @notice Caller is not the callback proxy or wrong tx.origin
    error EnhancedOriginHelper__UnauthorizedCaller();

    /// @notice Chainlink returned invalid or mismatched round data
    error EnhancedOriginHelper__InvalidRoundData();

    /// @notice Data older than staleness threshold
    error EnhancedOriginHelper__StaleData();

    /// @notice Round ID not greater than lastProcessedRound (covers duplicate and backwards cases)
    error EnhancedOriginHelper__StaleRound();

    /// @notice Constructor received zero address for required parameter
    error EnhancedOriginHelper__ZeroAddress();

    // ============ Constants ============

    /// @dev Maximum age of data before considered stale (2 hours)
    uint256 private constant STALENESS_THRESHOLD = 2 hours;

    // ============ State Variables ============

    /// @dev Chainlink price feed aggregator
    AggregatorV3Interface private immutable i_chainlinkFeed;

    /// @dev Address of the callback proxy contract
    address private immutable i_callbackProxy;

    /// @dev Address of the reactive contract authorized to call this helper
    address private immutable i_reactiveContract;

    /// @dev Last successfully processed round ID for duplicate/sequential tracking
    uint80 private s_lastProcessedRound;

    // ============ Modifiers ============

    /// @notice Restricts access to authorized reactive callbacks only
    modifier onlyReactiveCallback() {
        if (msg.sender != i_callbackProxy) {
            revert EnhancedOriginHelper__UnauthorizedCaller();
        }
        if (tx.origin != i_reactiveContract) {
            revert EnhancedOriginHelper__UnauthorizedCaller();
        }
        _;
    }

    // ============ Constructor ============

    /// @notice Initializes the helper with required addresses
    /// @param chainlinkFeed Address of the Chainlink aggregator
    /// @param callbackProxy Address of the callback proxy contract
    /// @param reactiveContract Address of the authorized reactive contract
    constructor(address chainlinkFeed, address callbackProxy, address reactiveContract) {
        if (chainlinkFeed == address(0)) revert EnhancedOriginHelper__ZeroAddress();
        if (callbackProxy == address(0)) revert EnhancedOriginHelper__ZeroAddress();
        if (reactiveContract == address(0)) revert EnhancedOriginHelper__ZeroAddress();

        i_chainlinkFeed = AggregatorV3Interface(chainlinkFeed);
        i_callbackProxy = callbackProxy;
        i_reactiveContract = reactiveContract;
    }

    // ============ External Functions ============

    /// @inheritdoc IEnhancedOriginHelper
    function enrichRoundData(uint80 roundId) external onlyReactiveCallback {
        // Check sequential ordering (covers duplicate and backwards cases)
        if (roundId <= s_lastProcessedRound) {
            revert EnhancedOriginHelper__StaleRound();
        }

        // Fetch round data from Chainlink (try-catch for graceful error handling)
        try i_chainlinkFeed.getRoundData(roundId) returns (
            uint80 fetchedRoundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) {
            // Validate returned data
            if (fetchedRoundId != roundId || updatedAt == 0) {
                revert EnhancedOriginHelper__InvalidRoundData();
            }

            // Validate freshness
            if (block.timestamp - updatedAt > STALENESS_THRESHOLD) {
                revert EnhancedOriginHelper__StaleData();
            }

            // Update state (CEI pattern)
            s_lastProcessedRound = roundId;

            // Emit event for reactive contract
            emit RoundDataReceived(roundId, answer, startedAt, updatedAt, answeredInRound);
        } catch {
            revert EnhancedOriginHelper__InvalidRoundData();
        }
    }

    /// @notice Fetches and emits the latest round data (for cron fallback support)
    /// @dev Idempotent - returns early if round already processed
    function enrichLatestRound() external onlyReactiveCallback {
        // Fetch latest round data from Chainlink
        try i_chainlinkFeed.latestRoundData() returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) {
            // Validate returned data
            if (updatedAt == 0) {
                revert EnhancedOriginHelper__InvalidRoundData();
            }

            // Validate freshness
            if (block.timestamp - updatedAt > STALENESS_THRESHOLD) {
                revert EnhancedOriginHelper__StaleData();
            }

            // Idempotent check - return early if already processed
            if (roundId <= s_lastProcessedRound) {
                return;
            }

            // Update state (CEI pattern)
            s_lastProcessedRound = roundId;

            // Emit event for reactive contract
            emit RoundDataReceived(roundId, answer, startedAt, updatedAt, answeredInRound);
        } catch {
            revert EnhancedOriginHelper__InvalidRoundData();
        }
    }

    // ============ View Functions ============

    /// @notice Returns the Chainlink feed address
    /// @return The address of the Chainlink aggregator
    function getChainlinkFeed() external view returns (address) {
        return address(i_chainlinkFeed);
    }

    /// @notice Returns the callback proxy address
    /// @return The address of the callback proxy
    function getCallbackProxy() external view returns (address) {
        return i_callbackProxy;
    }

    /// @notice Returns the reactive contract address
    /// @return The address of the authorized reactive contract
    function getReactiveContract() external view returns (address) {
        return i_reactiveContract;
    }

    /// @notice Returns the last processed round ID
    /// @return The last successfully processed round ID
    function getLastProcessedRound() external view returns (uint80) {
        return s_lastProcessedRound;
    }
}
