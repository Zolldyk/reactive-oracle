// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ============ Imports ============

import {Script, console} from "forge-std/Script.sol";
import {EnhancedOriginHelper} from "../src/origin/EnhancedOriginHelper.sol";
import {CHAINLINK_ETH_USD, CALLBACK_PROXY_SEPOLIA} from "../src/Constants.sol";

/// @title DeployEnhancedOriginHelper
/// @author Reactive Oracle Team
/// @notice Deployment script for EnhancedOriginHelper contract on Sepolia (origin chain)
/// @dev Uses encrypted keystore - run with --account flag
/// @dev EnhancedOriginHelper enriches Chainlink events with complete round data for the reactive contract
contract DeployEnhancedOriginHelper is Script {
    // ============ External Functions ============

    /// @notice Main deployment function for EnhancedOriginHelper
    /// @dev Deploys EnhancedOriginHelper to Sepolia chain with the specified reactive contract address
    /// @param reactiveContract The address of the ChainlinkMirrorReactive contract (pre-computed or deployed)
    /// @return originHelper The deployed EnhancedOriginHelper contract instance
    function run(address reactiveContract) external returns (EnhancedOriginHelper originHelper) {
        require(reactiveContract != address(0), "DeployEnhancedOriginHelper: Invalid reactive contract address");

        console.log("=== DeployEnhancedOriginHelper ===");
        console.log("Deploying EnhancedOriginHelper to Sepolia...");
        console.log("Chainlink ETH/USD Feed:", CHAINLINK_ETH_USD);
        console.log("Callback Proxy:", CALLBACK_PROXY_SEPOLIA);
        console.log("Reactive Contract:", reactiveContract);

        vm.startBroadcast();
        originHelper = new EnhancedOriginHelper(CHAINLINK_ETH_USD, CALLBACK_PROXY_SEPOLIA, reactiveContract);
        vm.stopBroadcast();

        console.log("EnhancedOriginHelper deployed at:", address(originHelper));
        console.log("=== Deployment Complete ===");

        return originHelper;
    }
}
