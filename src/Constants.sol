// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Constants - System-wide constants for the Reactive Oracle project

// Chain IDs
uint256 constant SEPOLIA_CHAIN_ID = 11155111;
uint256 constant LASNA_CHAIN_ID = 5318007;
uint256 constant REACTIVE_CHAIN_ID = 5318007;

// Chainlink Addresses (Sepolia)
address constant CHAINLINK_ETH_USD = 0x694AA1769357215DE4FAC081bf1f309aDC325306;

// Reactive Network System Contracts
address constant SYSTEM_CONTRACT = 0x0000000000000000000000000000000000fffFfF;

// Callback Proxy Addresses (per chain)
// Sepolia: 0xc9f36411C9897e7F959D99ffca2a0Ba7ee0D7bDA
// Lasna: 0x0000000000000000000000000000000000fffFfF (same as system contract)
address constant CALLBACK_PROXY_SEPOLIA = 0xc9f36411C9897e7F959D99ffca2a0Ba7ee0D7bDA;

// Gas Constants
uint256 constant ORIGIN_CALLBACK_GAS = 200000;
uint256 constant DESTINATION_CALLBACK_GAS = 300000;
