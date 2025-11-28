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

## License

MIT
