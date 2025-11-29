# ============================================
# Reactive Oracle - Makefile
# ============================================
# Deployment and development targets for the Reactive Oracle project
#
# Prerequisites:
# - Foundry installed (forge, cast)
# - Environment variables set (copy .env.example to .env)
# - Encrypted wallet imported (see wallet-import target)

# Include environment variables if .env exists
-include .env

# ============ Build & Test ============

.PHONY: build
build: ## Build all contracts
	forge build

.PHONY: test
test: ## Run all tests
	forge test

.PHONY: test-fork
test-fork: ## Run fork tests against Sepolia
	forge test --match-path "test/fork/*" -vvv

.PHONY: coverage
coverage: ## Generate test coverage report
	forge coverage

.PHONY: clean
clean: ## Clean build artifacts
	forge clean

# ============ Wallet Management ============

.PHONY: wallet-import
wallet-import: ## Import deployer wallet with encryption (interactive)
	@echo "Importing deployer wallet..."
	@echo "You will be prompted for your private key and a password."
	cast wallet import deployer --interactive

.PHONY: wallet-list
wallet-list: ## List imported wallets
	cast wallet list

# ============ Deployment Scripts ============

# Note: These targets require the following:
# 1. Encrypted wallet imported (run `make wallet-import` first)
# 2. Sufficient balance on target chain (ETH on Sepolia/Lasna, REACT on Reactive)
# 3. Environment variables set in .env file

.PHONY: deploy-plan
deploy-plan: ## Show deployment plan with predicted addresses
	forge script script/DeployAll.s.sol -vvv

.PHONY: deploy-feedproxy
deploy-feedproxy: ## Deploy FeedProxy to Lasna (requires REACTIVE_CONTRACT address)
ifndef REACTIVE_CONTRACT
	$(error REACTIVE_CONTRACT is not set. Compute address with `make deploy-plan` first)
endif
	forge script script/DeployFeedProxy.s.sol \
		--rpc-url $(LASNA_RPC_URL) \
		--account deployer \
		--broadcast \
		--sig "run(address)" $(REACTIVE_CONTRACT) \
		-vvv

.PHONY: deploy-helper
deploy-helper: ## Deploy EnhancedOriginHelper to Sepolia with verification
ifndef REACTIVE_CONTRACT
	$(error REACTIVE_CONTRACT is not set. Compute address with `make deploy-plan` first)
endif
ifndef ETHERSCAN_API_KEY
	$(error ETHERSCAN_API_KEY is not set for verification)
endif
	forge script script/DeployEnhancedOriginHelper.s.sol \
		--rpc-url $(SEPOLIA_RPC_URL) \
		--account deployer \
		--broadcast \
		--verify \
		--etherscan-api-key $(ETHERSCAN_API_KEY) \
		--sig "run(address)" $(REACTIVE_CONTRACT) \
		-vvv

.PHONY: deploy-reactive
deploy-reactive: ## Deploy ChainlinkMirrorReactive to Lasna
ifndef ENHANCED_ORIGIN_HELPER
	$(error ENHANCED_ORIGIN_HELPER is not set. Deploy EnhancedOriginHelper first)
endif
ifndef FEED_PROXY
	$(error FEED_PROXY is not set. Deploy FeedProxy first)
endif
	forge script script/DeployChainlinkMirrorReactive.s.sol \
		--rpc-url $(LASNA_RPC_URL) \
		--account deployer \
		--broadcast \
		--sig "run(address,address)" $(ENHANCED_ORIGIN_HELPER) $(FEED_PROXY) \
		-vvv

.PHONY: deploy-all
deploy-all: ## Full deployment sequence (interactive - follow prompts)
	@echo "============================================"
	@echo "Reactive Oracle - Full Deployment Sequence"
	@echo "============================================"
	@echo ""
	@echo "This is a multi-chain deployment requiring 3 separate transactions."
	@echo "Each step must complete before proceeding to the next."
	@echo ""
	@echo "Step 1: Compute deployment addresses"
	@echo "  make deploy-plan"
	@echo ""
	@echo "Step 2: Deploy FeedProxy to Lasna"
	@echo "  Set REACTIVE_CONTRACT in .env with predicted address"
	@echo "  make deploy-feedproxy"
	@echo ""
	@echo "Step 3: Deploy EnhancedOriginHelper to Sepolia"
	@echo "  make deploy-helper"
	@echo ""
	@echo "Step 4: Deploy ChainlinkMirrorReactive to Lasna"
	@echo "  Set ENHANCED_ORIGIN_HELPER and FEED_PROXY in .env with actual addresses"
	@echo "  make deploy-reactive"
	@echo ""
	@echo "Step 5: Verify deployments"
	@echo "  make verify-deployments"
	@echo ""
	@echo "============================================"

# ============ Verification ============

.PHONY: verify-deployments
verify-deployments: ## Verify deployed contract configurations
ifndef FEED_PROXY
	$(error FEED_PROXY is not set)
endif
ifndef ENHANCED_ORIGIN_HELPER
	$(error ENHANCED_ORIGIN_HELPER is not set)
endif
ifndef REACTIVE_CONTRACT
	$(error REACTIVE_CONTRACT is not set)
endif
	@echo "Verifying FeedProxy on Lasna..."
	cast call $(FEED_PROXY) "getReactiveContract()(address)" --rpc-url $(LASNA_RPC_URL)
	@echo ""
	@echo "Verifying EnhancedOriginHelper on Sepolia..."
	cast call $(ENHANCED_ORIGIN_HELPER) "getReactiveContract()(address)" --rpc-url $(SEPOLIA_RPC_URL)
	@echo ""
	@echo "Verifying ChainlinkMirrorReactive on Lasna..."
	cast call $(REACTIVE_CONTRACT) "getConfiguration()(uint256,uint256,address,address,address)" --rpc-url $(LASNA_RPC_URL)

# ============ Help ============

.PHONY: help
help: ## Show this help message
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
