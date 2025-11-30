// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ============ Imports ============

import {Script, console} from "forge-std/Script.sol";
import {ChainlinkMirrorReactive} from "../src/reactive/ChainlinkMirrorReactive.sol";
import {SEPOLIA_CHAIN_ID, LASNA_CHAIN_ID, CHAINLINK_ETH_USD, CHAINLINK_ETH_USD_AGGREGATOR} from "../src/Constants.sol";

/// @title DeployChainlinkMirrorReactive
/// @author Reactive Oracle Team
/// @notice Deployment script for ChainlinkMirrorReactive contract on Reactive Network
/// @dev Uses encrypted keystore - run with --account flag
/// @dev ChainlinkMirrorReactive orchestrates cross-chain price mirroring from Chainlink to FeedProxy
contract DeployChainlinkMirrorReactive is Script {
    // ============ External Functions ============

    /// @notice Main deployment function for ChainlinkMirrorReactive
    /// @dev Deploys ChainlinkMirrorReactive to Reactive Network with references to origin and destination contracts
    /// @param originHelper The address of the EnhancedOriginHelper contract on Sepolia
    /// @param feedProxy The address of the FeedProxy contract on Lasna
    /// @return reactiveContract The deployed ChainlinkMirrorReactive contract instance
    function run(address originHelper, address feedProxy) external returns (ChainlinkMirrorReactive reactiveContract) {
        require(originHelper != address(0), "DeployChainlinkMirrorReactive: Invalid origin helper address");
        require(feedProxy != address(0), "DeployChainlinkMirrorReactive: Invalid feed proxy address");

        console.log("=== DeployChainlinkMirrorReactive ===");
        console.log("Deploying ChainlinkMirrorReactive to Reactive Network...");
        console.log("Origin Chain ID (Sepolia):", SEPOLIA_CHAIN_ID);
        console.log("Destination Chain ID (Lasna):", LASNA_CHAIN_ID);
        console.log("Chainlink ETH/USD Proxy:", CHAINLINK_ETH_USD);
        console.log("Chainlink ETH/USD Aggregator:", CHAINLINK_ETH_USD_AGGREGATOR);
        console.log("Origin Helper:", originHelper);
        console.log("Feed Proxy:", feedProxy);

        vm.startBroadcast();
        reactiveContract = new ChainlinkMirrorReactive(
            SEPOLIA_CHAIN_ID,
            LASNA_CHAIN_ID,
            CHAINLINK_ETH_USD,
            CHAINLINK_ETH_USD_AGGREGATOR,
            originHelper,
            feedProxy
        );
        vm.stopBroadcast();

        console.log("ChainlinkMirrorReactive deployed at:", address(reactiveContract));
        console.log("=== Deployment Complete ===");

        return reactiveContract;
    }
}
