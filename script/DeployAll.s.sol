// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ============ Imports ============

import {Script, console} from "forge-std/Script.sol";
import {FeedProxy} from "../src/destination/FeedProxy.sol";
import {EnhancedOriginHelper} from "../src/origin/EnhancedOriginHelper.sol";
import {ChainlinkMirrorReactive} from "../src/reactive/ChainlinkMirrorReactive.sol";
import {
    SEPOLIA_CHAIN_ID,
    LASNA_CHAIN_ID,
    CHAINLINK_ETH_USD,
    CALLBACK_PROXY_SEPOLIA
} from "../src/Constants.sol";

/// @title DeployAll
/// @author Reactive Oracle Team
/// @notice Orchestrates the full deployment sequence with address prediction for circular dependencies
/// @dev This script handles the chicken-and-egg problem where:
///      - FeedProxy needs the reactive contract address at construction (immutable)
///      - EnhancedOriginHelper needs the reactive contract address at construction (immutable)
///      - ChainlinkMirrorReactive needs both FeedProxy and EnhancedOriginHelper addresses at construction
///
/// Solution: Deployer Nonce Prediction
/// ------------------------------------
/// Since we control the deployment sequence and use the same deployer address, we can predict
/// the future address of the reactive contract based on the deployer's nonce on the Reactive Network.
///
/// Deployment Sequence (3 separate chain transactions):
/// 1. Deploy FeedProxy to Lasna with predicted reactive contract address
/// 2. Deploy EnhancedOriginHelper to Sepolia with predicted reactive contract address
/// 3. Deploy ChainlinkMirrorReactive to Reactive Network with actual FeedProxy and EnhancedOriginHelper addresses
///
/// IMPORTANT: Each chain maintains its own nonce. The reactive contract address prediction is based
/// on the deployer's nonce on Reactive Network (chain ID 4488), not Sepolia or Lasna.
contract DeployAll is Script {
    // ============ Type Declarations ============

    /// @notice Struct containing predicted/deployed addresses for all contracts
    struct DeploymentAddresses {
        address feedProxy;
        address originHelper;
        address reactiveContract;
    }

    // ============ Constants ============

    /// @notice Number of decimals for FeedProxy (matches Chainlink ETH/USD)
    uint8 private constant DECIMALS = 8;

    /// @notice Human-readable description for FeedProxy
    string private constant DESCRIPTION = "ETH / USD";

    // ============ External Functions ============

    /// @notice Main entry point - computes addresses and logs deployment plan
    /// @dev Does not perform actual deployment; use individual deploy functions for that
    function run() external view {
        address deployer = msg.sender;

        console.log("=== DeployAll - Deployment Plan ===");
        console.log("Deployer:", deployer);
        console.log("");

        DeploymentAddresses memory addrs = computeAddresses(deployer);

        console.log("=== Computed Addresses ===");
        console.log("FeedProxy (Lasna):", addrs.feedProxy);
        console.log("EnhancedOriginHelper (Sepolia):", addrs.originHelper);
        console.log("ChainlinkMirrorReactive (Reactive):", addrs.reactiveContract);
        console.log("");

        console.log("=== Deployment Sequence ===");
        console.log("Step 1: Deploy FeedProxy to Lasna");
        console.log("  Command: forge script script/DeployFeedProxy.s.sol \\");
        console.log("    --rpc-url $LASNA_RPC_URL --account deployer --broadcast \\");
        console.log("    --sig 'run(address)' <REACTIVE_CONTRACT_ADDRESS>");
        console.log("");
        console.log("Step 2: Deploy EnhancedOriginHelper to Sepolia");
        console.log("  Command: forge script script/DeployEnhancedOriginHelper.s.sol \\");
        console.log("    --rpc-url $SEPOLIA_RPC_URL --account deployer --broadcast --verify \\");
        console.log("    --sig 'run(address)' <REACTIVE_CONTRACT_ADDRESS>");
        console.log("");
        console.log("Step 3: Deploy ChainlinkMirrorReactive to Reactive Network");
        console.log("  Command: forge script script/DeployChainlinkMirrorReactive.s.sol \\");
        console.log("    --rpc-url $REACTIVE_RPC_URL --account deployer --broadcast \\");
        console.log("    --sig 'run(address,address)' <ORIGIN_HELPER> <FEED_PROXY>");
        console.log("");
        console.log("=== Important Notes ===");
        console.log("1. Use the same deployer wallet on all chains");
        console.log("2. Reactive contract address depends on Reactive Network nonce");
        console.log("3. Verify nonce before each deployment step");
        console.log("4. Update .env with deployed addresses after completion");
    }

    /// @notice Computes predicted addresses for all contracts based on deployer's nonces
    /// @dev Uses RLP encoding to predict CREATE addresses
    /// @param deployer The deployer address (same on all chains)
    /// @return addrs Struct containing predicted addresses for all three contracts
    function computeAddresses(address deployer) public view returns (DeploymentAddresses memory addrs) {
        // Note: Each chain has independent nonces
        // We need to know the nonce on each chain to predict addresses accurately
        // For this script, we use vm.getNonce which returns nonce for current chain context

        uint256 currentNonce = vm.getNonce(deployer);

        console.log("=== Nonce Information ===");
        console.log("Current nonce (context-dependent):", currentNonce);
        console.log("Note: Actual nonces may differ per chain");
        console.log("");

        // Predict addresses assuming deployment starts at current nonce
        // In practice, user should verify nonces on each chain before deploying
        addrs.feedProxy = _computeCreateAddress(deployer, currentNonce);
        addrs.originHelper = _computeCreateAddress(deployer, currentNonce + 1);
        addrs.reactiveContract = _computeCreateAddress(deployer, currentNonce + 2);

        return addrs;
    }

    /// @notice Standalone deployment function for FeedProxy
    /// @param reactiveContract Pre-computed reactive contract address
    /// @return feedProxy The deployed FeedProxy contract
    function deployFeedProxy(address reactiveContract) external returns (FeedProxy feedProxy) {
        require(reactiveContract != address(0), "DeployAll: Invalid reactive contract address");

        console.log("=== Deploying FeedProxy ===");
        console.log("Reactive Contract:", reactiveContract);
        console.log("Decimals:", DECIMALS);
        console.log("Description:", DESCRIPTION);

        vm.startBroadcast();
        feedProxy = new FeedProxy(reactiveContract, DECIMALS, DESCRIPTION);
        vm.stopBroadcast();

        console.log("FeedProxy deployed at:", address(feedProxy));
        return feedProxy;
    }

    /// @notice Standalone deployment function for EnhancedOriginHelper
    /// @param reactiveContract Pre-computed reactive contract address
    /// @return originHelper The deployed EnhancedOriginHelper contract
    function deployOriginHelper(address reactiveContract) external returns (EnhancedOriginHelper originHelper) {
        require(reactiveContract != address(0), "DeployAll: Invalid reactive contract address");

        console.log("=== Deploying EnhancedOriginHelper ===");
        console.log("Chainlink Feed:", CHAINLINK_ETH_USD);
        console.log("Callback Proxy:", CALLBACK_PROXY_SEPOLIA);
        console.log("Reactive Contract:", reactiveContract);

        vm.startBroadcast();
        originHelper = new EnhancedOriginHelper(CHAINLINK_ETH_USD, CALLBACK_PROXY_SEPOLIA, reactiveContract);
        vm.stopBroadcast();

        console.log("EnhancedOriginHelper deployed at:", address(originHelper));
        return originHelper;
    }

    /// @notice Standalone deployment function for ChainlinkMirrorReactive
    /// @param originHelper Deployed EnhancedOriginHelper address
    /// @param feedProxy Deployed FeedProxy address
    /// @return reactiveContract The deployed ChainlinkMirrorReactive contract
    function deployReactive(
        address originHelper,
        address feedProxy
    ) external returns (ChainlinkMirrorReactive reactiveContract) {
        require(originHelper != address(0), "DeployAll: Invalid origin helper address");
        require(feedProxy != address(0), "DeployAll: Invalid feed proxy address");

        console.log("=== Deploying ChainlinkMirrorReactive ===");
        console.log("Origin Chain ID:", SEPOLIA_CHAIN_ID);
        console.log("Destination Chain ID:", LASNA_CHAIN_ID);
        console.log("Chainlink Feed:", CHAINLINK_ETH_USD);
        console.log("Origin Helper:", originHelper);
        console.log("Feed Proxy:", feedProxy);

        vm.startBroadcast();
        reactiveContract = new ChainlinkMirrorReactive(
            SEPOLIA_CHAIN_ID,
            LASNA_CHAIN_ID,
            CHAINLINK_ETH_USD,
            originHelper,
            feedProxy
        );
        vm.stopBroadcast();

        console.log("ChainlinkMirrorReactive deployed at:", address(reactiveContract));
        return reactiveContract;
    }

    // ============ Internal Functions ============

    /// @notice Computes the address of a contract deployed via CREATE
    /// @dev Uses RLP encoding: 0xd6 0x94 <address> <nonce>
    ///      This encoding is valid for nonces 0-127 (single byte representation)
    /// @param deployer The deploying address
    /// @param nonce The nonce at deployment time
    /// @return The predicted contract address
    function _computeCreateAddress(address deployer, uint256 nonce) internal pure returns (address) {
        // For nonces 0-127, we can use single byte RLP encoding
        // RLP encoding for address: 0x94 + 20 bytes = 21 bytes, prefix 0xd4 for 21 bytes would be wrong
        // Actually: [0xd6, 0x94, <20-byte address>, <1-byte nonce>] for 1+20+1 = 22 byte payload
        // 0xd6 = 0xc0 + 22 (list prefix for 22-byte payload)
        require(nonce < 128, "DeployAll: Nonce too large for simple encoding");

        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xd6),
                            bytes1(0x94),
                            deployer,
                            bytes1(uint8(nonce))
                        )
                    )
                )
            )
        );
    }
}
