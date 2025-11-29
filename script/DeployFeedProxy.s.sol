// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ============ Imports ============

import {Script, console} from "forge-std/Script.sol";
import {FeedProxy} from "../src/destination/FeedProxy.sol";

/// @title DeployFeedProxy
/// @author Reactive Oracle Team
/// @notice Deployment script for FeedProxy contract on Lasna (destination chain)
/// @dev Uses encrypted keystore - run with --account flag
/// @dev FeedProxy acts as a Chainlink-compatible price feed that receives data from Reactive Network
contract DeployFeedProxy is Script {
    // ============ Constants ============

    /// @notice Number of decimals for price data (matches Chainlink ETH/USD)
    uint8 private constant DECIMALS = 8;

    /// @notice Human-readable description of the price feed
    string private constant DESCRIPTION = "ETH / USD";

    // ============ External Functions ============

    /// @notice Main deployment function for FeedProxy
    /// @dev Deploys FeedProxy to Lasna chain with the specified reactive contract address
    /// @param reactiveContract The address of the ChainlinkMirrorReactive contract (pre-computed or deployed)
    /// @return feedProxy The deployed FeedProxy contract instance
    function run(address reactiveContract) external returns (FeedProxy feedProxy) {
        require(reactiveContract != address(0), "DeployFeedProxy: Invalid reactive contract address");

        console.log("=== DeployFeedProxy ===");
        console.log("Deploying FeedProxy to Lasna...");
        console.log("Reactive Contract:", reactiveContract);
        console.log("Decimals:", DECIMALS);
        console.log("Description:", DESCRIPTION);

        vm.startBroadcast();
        feedProxy = new FeedProxy(reactiveContract, DECIMALS, DESCRIPTION);
        vm.stopBroadcast();

        console.log("FeedProxy deployed at:", address(feedProxy));
        console.log("=== Deployment Complete ===");

        return feedProxy;
    }
}
