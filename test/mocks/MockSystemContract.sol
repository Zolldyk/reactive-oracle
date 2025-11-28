// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISystemContract} from "@reactive/interfaces/ISystemContract.sol";

/// @title MockSystemContract
/// @notice Mock implementation of ISystemContract for testing reactive contracts
contract MockSystemContract is ISystemContract {
    struct Subscription {
        uint256 chainId;
        address contractAddr;
        uint256 topic0;
        uint256 topic1;
        uint256 topic2;
        uint256 topic3;
    }

    Subscription[] public subscriptions;
    uint256 public subscriptionCount;

    /// @notice Returns all subscriptions for verification
    function getSubscriptions() external view returns (Subscription[] memory) {
        return subscriptions;
    }

    /// @notice Subscribe to events (mock implementation)
    function subscribe(
        uint256 chain_id,
        address _contract,
        uint256 topic_0,
        uint256 topic_1,
        uint256 topic_2,
        uint256 topic_3
    ) external override {
        subscriptions.push(Subscription({
            chainId: chain_id,
            contractAddr: _contract,
            topic0: topic_0,
            topic1: topic_1,
            topic2: topic_2,
            topic3: topic_3
        }));
        subscriptionCount++;
    }

    /// @notice Unsubscribe from events (mock implementation)
    function unsubscribe(
        uint256,
        address,
        uint256,
        uint256,
        uint256,
        uint256
    ) external override {
        // No-op for testing
    }

    /// @notice Allows contracts to pay their debts (mock implementation)
    receive() external payable override {
        // No-op for testing
    }

    /// @notice Returns debt for a contract (mock implementation)
    function debt(address) external pure override returns (uint256) {
        return 0;
    }
}
