# Reactive Oracle

Cross-chain Chainlink price feed mirroring using the Reactive Network.

## Presentation

🎥 [Watch the Project Presentation](https://www.loom.com/share/4fb7aacc426c4a5bbf62b593eaa0dc4e)

## Problem Statement

**The Reactive Lasna network does not have native access to Chainlink price oracles.** DeFi applications on Lasna requiring reliable price data cannot function without oracle access.

Reactive Oracle solves this by mirroring Chainlink price feeds from Ethereum Sepolia to Reactive Lasna using the Reactive Network's cross-chain event-driven architecture. Applications on Lasna can consume price data via a standard `AggregatorV3Interface`, identical to how they would use Chainlink directly.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              REACTIVE NETWORK                                │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                         ReactVM (Per-Deployer)                       │   │
│  │  ┌─────────────────────────────────────────────────────────────┐   │   │
│  │  │              ChainlinkMirrorReactive Contract                │   │   │
│  │  │  • Subscribes to AnswerUpdated events (Sepolia)             │   │   │
│  │  │  • Subscribes to RoundDataReceived events (Sepolia)         │   │   │
│  │  │  • Processes Cron100 heartbeat (~12 min)                    │   │   │
│  │  │  • Emits callbacks to origin and destination chains         │   │   │
│  │  └─────────────────────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
            │                                           │
            │ Callback 1: enrichRoundData()             │ Callback 2: updateRoundData()
            ▼                                           ▼
┌───────────────────────────┐               ┌───────────────────────────┐
│     ETHEREUM SEPOLIA      │               │      REACTIVE LASNA       │
│  Chain ID: 11155111       │               │     Chain ID: 5318007     │
│  ┌─────────────────────┐  │               │  ┌─────────────────────┐  │
│  │ Chainlink Aggregator│  │               │  │     FeedProxy       │  │
│  │  (ETH/USD Feed)     │  │               │  │ (AggregatorV3)      │  │
│  └─────────────────────┘  │               │  └─────────────────────┘  │
│            │              │               │            ▲              │
│  ┌─────────────────────┐  │               │            │              │
│  │ EnhancedOriginHelper│  │               │            │              │
│  │  • Enriches events  │──┼───────────────┼────────────┘              │
│  └─────────────────────┘  │               │                           │
└───────────────────────────┘               └───────────────────────────┘
```

### Contract Responsibilities

| Contract | Chain | Responsibility |
|----------|-------|----------------|
| **EnhancedOriginHelper** | Sepolia | Fetches complete round data from Chainlink, emits `RoundDataReceived` event |
| **ChainlinkMirrorReactive** | Lasna | Subscribes to events, coordinates two-callback flow, handles cron fallback |
| **FeedProxy** | Lasna | Stores mirrored data, implements `AggregatorV3Interface`, validates updates |

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (forge, cast, anvil)
- Node.js v18+ (optional, for scripts)
- Testnet ETH on Sepolia (for deploying EnhancedOriginHelper)
- Testnet REACT on Lasna (for deploying FeedProxy and ChainlinkMirrorReactive)

### Getting Testnet Tokens

- **Sepolia ETH**: Use [Alchemy Sepolia Faucet](https://sepoliafaucet.com/) or [Infura Sepolia Faucet](https://www.infura.io/faucet/sepolia)
- **Lasna REACT**: Use [Reactive Network Faucet](https://faucet.rnk.dev/)

## Installation

```bash
# Clone the repository
git clone https://github.com/your-org/reactive-oracle.git
cd reactive-oracle

# Install Foundry dependencies
forge install

# Copy environment template
cp .env.example .env

# Edit .env with your configuration (optional for local testing)
```

## Usage

### Build

```bash
forge build
```

### Test

```bash
# Run all tests (95 unit tests)
forge test

# Run with verbosity
forge test -vvv

# Run fork tests against Sepolia
forge test --match-path "test/fork/*" -vvv

# Generate coverage report
forge coverage
```

### Deployment

The deployment requires 3 contracts across 2 chains. Use the Makefile for guided deployment:

```bash
# Show deployment plan with predicted addresses
make deploy-plan

# Full deployment sequence (follow prompts)
make deploy-all
```

**Individual deployment targets:**

```bash
make deploy-feedproxy   # Deploy FeedProxy to Lasna
make deploy-helper      # Deploy EnhancedOriginHelper to Sepolia (with verification)
make deploy-reactive    # Deploy ChainlinkMirrorReactive to Lasna
```

**Expected output from `make deploy-plan`:**

```
Predicted addresses for deployer 0xYourAddress:
  FeedProxy:               0x...
  EnhancedOriginHelper:    0x...
  ChainlinkMirrorReactive: 0x...
```

### Verification Commands

After deployment, verify the system is configured correctly:

```bash
# Check FeedProxy configuration (Lasna)
cast call 0x21Bd1Ec9C419B09423BD813D6F20Ac872ED39EDd "getReactiveContract()(address)" --rpc-url https://lasna-rpc.rnk.dev

# Check FeedProxy decimals and description (Lasna)
cast call 0x21Bd1Ec9C419B09423BD813D6F20Ac872ED39EDd "decimals()(uint8)" --rpc-url https://lasna-rpc.rnk.dev
cast call 0x21Bd1Ec9C419B09423BD813D6F20Ac872ED39EDd "description()(string)" --rpc-url https://lasna-rpc.rnk.dev

# Check EnhancedOriginHelper configuration (Sepolia)
cast call 0x3e4391d52696824794C961f7Fd71DC882f69B0C4 "getReactiveContract()(address)" --rpc-url https://ethereum-sepolia.publicnode.com

# Check ChainlinkMirrorReactive last processed round (Lasna)
cast call 0xE8E514E105E5472AbA008bE55702B2668b41a1b0 "getLastProcessedRound()(uint80)" --rpc-url https://lasna-rpc.rnk.dev

# Compare with Chainlink source (Sepolia)
cast call 0x694AA1769357215DE4FAC081bf1f309aDC325306 "latestRoundData()(uint80,int256,uint256,uint256,uint80)" --rpc-url https://ethereum-sepolia.publicnode.com

# Check FeedProxy latest round data (Lasna)
cast call 0x21Bd1Ec9C419B09423BD813D6F20Ac872ED39EDd "latestRoundData()(uint80,int256,uint256,uint256,uint80)" --rpc-url https://lasna-rpc.rnk.dev
```

## Deployed Contracts (Testnet v5)

| Contract | Chain | Address | Explorer |
|----------|-------|---------|----------|
| EnhancedOriginHelper | Sepolia (11155111) | `0x3e4391d52696824794C961f7Fd71DC882f69B0C4` | [Etherscan](https://sepolia.etherscan.io/address/0x3e4391d52696824794C961f7Fd71DC882f69B0C4) |
| FeedProxy | Lasna (5318007) | `0x21Bd1Ec9C419B09423BD813D6F20Ac872ED39EDd` | [Reactscan](https://lasna.reactscan.net/address/0x21Bd1Ec9C419B09423BD813D6F20Ac872ED39EDd) |
| ChainlinkMirrorReactive | Lasna (5318007) | `0xE8E514E105E5472AbA008bE55702B2668b41a1b0` | [Reactscan](https://lasna.reactscan.net/address/0xE8E514E105E5472AbA008bE55702B2668b41a1b0) |

### Deployment Transaction Hashes

- **EnhancedOriginHelper**: [`0x472f49575fff8f242a6e032575981a21ee46e51a9c6cc737632189dd89b20801`](https://sepolia.etherscan.io/tx/0x472f49575fff8f242a6e032575981a21ee46e51a9c6cc737632189dd89b20801)
- **FeedProxy**: [`0x5781c036252454dfee1520a87536fc850d181eeb99ad2a0a2b248b41d53bf489`](https://lasna.reactscan.net/tx/0x5781c036252454dfee1520a87536fc850d181eeb99ad2a0a2b248b41d53bf489)
- **ChainlinkMirrorReactive**: [`0x581dc3d0eecb0e096ef76530e638a074375564788e548211c32d14491b9c1016`](https://lasna.reactscan.net/tx/0x581dc3d0eecb0e096ef76530e638a074375564788e548211c32d14491b9c1016)
- **initSubscriptions()**: [`0x6b98ac12195e8bca8c245c55d0be447ea3e3d3eb09da9dfc8260f6aaff253b2a`](https://lasna.reactscan.net/tx/0x6b98ac12195e8bca8c245c55d0be447ea3e3d3eb09da9dfc8260f6aaff253b2a)

## Project Structure

```
reactive-oracle/
├── docs/
│   ├── architecture.md      # System architecture details
│   ├── workflow.md          # End-to-end workflow documentation
│   ├── runbook.md           # Operations and troubleshooting
│   └── architecture/        # Sharded architecture docs (detailed)
├── src/
│   ├── Constants.sol        # System-wide constants
│   ├── interfaces/          # Contract interfaces
│   ├── destination/         # FeedProxy.sol
│   ├── origin/              # EnhancedOriginHelper.sol
│   └── reactive/            # ChainlinkMirrorReactive.sol
├── test/
│   ├── unit/                # 95 unit tests
│   ├── integration/         # Cross-contract flow tests
│   ├── fork/                # Sepolia fork tests
│   └── mocks/               # Mock contracts
├── script/                  # Deployment scripts
├── .env.example             # Environment template with deployed addresses
└── Makefile                 # Build automation
```

## Documentation

- **[Architecture](docs/architecture.md)** - System design, contract interactions, security model
- **[Workflow](docs/workflow.md)** - End-to-end flow with transaction examples
- **[Runbook](docs/runbook.md)** - Operations, troubleshooting, health checks

## Testing

The project includes comprehensive test coverage:

- **Unit Tests**: 95 tests covering all contract functions
- **Integration Tests**: Cross-contract flow validation
- **Fork Tests**: Tests against live Sepolia Chainlink feeds

```bash
# Quick test run
forge test

# Full test with gas reports
forge test -vvv --gas-report
```

## License

MIT
