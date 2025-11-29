# Reactive Oracle

Cross-chain Chainlink price feed mirroring using the Reactive Network.

## Overview

Reactive Oracle mirrors Chainlink price feeds from Ethereum Sepolia to Reactive Lasna using the Reactive Network's cross-chain messaging capabilities. This enables DeFi applications on Lasna to access reliable Chainlink price data.

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (forge, cast, anvil)
- Node.js (optional, for scripts)

## Installation

```shell
# Clone the repository
git clone <repository-url>
cd reactive-oracle

# Install dependencies
forge install
```

## Setup

1. Copy the environment template:
```shell
cp .env.example .env
```

2. Configure your RPC URLs and private keys in `.env`

## Usage

### Build

```shell
forge build
```

### Test

```shell
forge test
```

### Format

```shell
forge fmt
```

## Deployed Contracts (Testnet)

| Contract | Chain | Address | Explorer |
|----------|-------|---------|----------|
| EnhancedOriginHelper | Sepolia (11155111) | `0xE77b96691CFC9547D9979579F91996ef812AB13c` | [Etherscan](https://sepolia.etherscan.io/address/0xE77b96691CFC9547D9979579F91996ef812AB13c) |
| FeedProxy | Lasna (5318007) | `0x96b86F9106Ec53BA0Aa5264FDa9AEA83CFe2aFD7` | [Reactscan](https://lasna.reactscan.net/address/0x96b86F9106Ec53BA0Aa5264FDa9AEA83CFe2aFD7) |
| ChainlinkMirrorReactive | Sepolia (11155111) | `0x67882916AbF31B4E5557a8A956b203708b5fcD6d` | [Etherscan](https://sepolia.etherscan.io/address/0x67882916AbF31B4E5557a8A956b203708b5fcD6d) |

### Deployment Transaction Hashes

- **FeedProxy**: `0x8f23112febd619bf02bcfa4e20c5c17c1df3ed0a90be4d6d33f0658f1d75bf58`
- **EnhancedOriginHelper**: `0x3edaddabeda77074e4f1579e155312faa1ed242346dce604effc170f4e1e5ec9`
- **ChainlinkMirrorReactive**: `0x89bb2f6f439ab9b9fecad1fb7a5d66bf077541953e5d60fe1b0b43173e01dc5d`

## Project Structure

```
src/
├── interfaces/     # Contract interfaces
├── origin/         # Origin chain contracts (Sepolia)
├── destination/    # Destination chain contracts (Lasna)
└── reactive/       # Reactive Network contracts

test/
├── unit/           # Unit tests
├── integration/    # Integration tests
├── fork/           # Fork tests
└── mocks/          # Mock contracts

script/             # Deployment scripts
```

## Deployment

See `make help` for available deployment commands:

```bash
make deploy-plan       # Show deployment plan with predicted addresses
make deploy-feedproxy  # Deploy FeedProxy to Lasna
make deploy-helper     # Deploy EnhancedOriginHelper to Sepolia
make deploy-reactive   # Deploy ChainlinkMirrorReactive
```

## License

MIT
