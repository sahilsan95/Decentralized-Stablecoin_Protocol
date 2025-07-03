# 🏦 Foundry DeFi Stablecoin Protocol

A decentralized, algorithmic stablecoin protocol built with Foundry that maintains a USD peg through cryptocurrency overcollateralization.

![Solidity](https://img.shields.io/badge/Solidity-^0.8.20-blue)
![Foundry](https://img.shields.io/badge/Foundry-Framework-red)
![License](https://img.shields.io/badge/License-MIT-green)

## 📋 Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Architecture](#architecture)
- [Getting Started](#getting-started)
- [Usage](#usage)
- [Testing](#testing)
- [Deployment](#deployment)
- [Security](#security)
- [Contributing](#contributing)
- [License](#license)

## 🎯 Overview

This project implements a **MakerDAO-inspired** decentralized stablecoin system where users can:
- Deposit cryptocurrency collateral (WETH, WBTC)
- Mint DSC (DecentralizedStableCoin) tokens pegged to $1 USD
- Maintain overcollateralized positions (200%+ collateral ratio)
- Participate in liquidations to keep the system healthy

### Key Properties
- **Collateral Type**: Exogenous (WETH, WBTC)
- **Stability Mechanism**: Algorithmic/Decentralized
- **Peg**: Anchored to USD
- **Collateral Ratio**: 200% minimum (overcollateralized)

## ✨ Features

- 🔒 **Overcollateralized Minting**: Requires 200%+ collateral ratio
- 📊 **Chainlink Price Feeds**: Real-time asset pricing with stale price protection
- ⚡ **Automated Liquidations**: Liquidate undercollateralized positions
- 🛡️ **Health Factor System**: Monitor position safety
- 🔄 **Collateral Management**: Deposit, withdraw, and redeem collateral
- 🧪 **Comprehensive Testing**: Unit, fuzz, and invariant tests

## 🏗️ Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   DSCEngine     │────│ DecentralizedSC  │────│   OracleLib     │
│  (Main Logic)   │    │   (ERC20 Token)  │    │ (Price Feeds)   │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                        │                        │
         │                        │                        │
    ┌────▼────┐              ┌────▼────┐              ┌────▼────┐
    │ Deposit │              │  Mint   │              │Chainlink│
    │Withdraw │              │  Burn   │              │ Oracles │
    │Liquidate│              │Transfer │              │ (ETH/BTC│
    └─────────┘              └─────────┘              │ Prices) │
                                                      └─────────┘
```

### Core Contracts

| Contract | Description |
|----------|-------------|
| `DSCEngine.sol` | Main protocol engine handling collateral, minting, and liquidations |
| `DecentralizedStableCoin.sol` | ERC20 stablecoin token with mint/burn functionality |
| `OracleLib.sol` | Chainlink oracle integration with stale price protection |

## 🚀 Getting Started

### Prerequisites

- [Git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
- [Foundry](https://getfoundry.sh/)

### Installation

1. **Clone the repository**
```bash
git clone https://github.com/yourusername/foundry-defi-stablecoin.git
cd foundry-defi-stablecoin
```

2. **Install dependencies**
```bash
forge install
```

3. **Build the project**
```bash
forge build
```

4. **Run tests**
```bash
forge test
```

## 💻 Usage

### Basic Operations

#### 1. Deploy the Protocol
```bash
forge script script/DeployDSC.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast
```

#### 2. Deposit Collateral & Mint DSC
```solidity
// Deposit 1 WETH as collateral
dscEngine.depositCollateral(wethAddress, 1 ether);

// Mint 1000 DSC tokens (assuming sufficient collateral)
dscEngine.mintDsc(1000 ether);
```

#### 3. Check Health Factor
```solidity
uint256 healthFactor = dscEngine.getHealthFactor(userAddress);
// Health factor must be > 1 to avoid liquidation
```

#### 4. Liquidate Undercollateralized Position
```solidity
dscEngine.liquidate(collateralAddress, userToBeLiquidated, debtToCover);
```

### Environment Setup

Create a `.env` file:
```bash
SEPOLIA_RPC_URL=your_sepolia_rpc_url
PRIVATE_KEY=your_private_key
ETHERSCAN_API_KEY=your_etherscan_api_key
```

## 🧪 Testing

The project includes comprehensive testing:

### Run All Tests
```bash
forge test
```

### Run Specific Test Categories
```bash
# Unit tests
forge test --match-path test/unit/*

# Fuzz tests
forge test --match-path test/fuzz/*

# Test with verbosity
forge test -vvv
```

### Test Coverage
```bash
forge coverage
```

### Test Categories

| Type | Description | Location |
|------|-------------|----------|
| **Unit Tests** | Individual function testing | `test/unit/` |
| **Fuzz Tests** | Random input testing | `test/fuzz/` |
| **Invariant Tests** | System property testing | `test/fuzz/` |
| **Integration Tests** | End-to-end scenarios | `test/integration/` |

## 🚀 Deployment

### Local Deployment
```bash
# Start local node
anvil

# Deploy to local network
forge script script/DeployDSC.s.sol --rpc-url http://localhost:8545 --private-key $PRIVATE_KEY --broadcast
```

### Testnet Deployment
```bash
# Deploy to Sepolia
forge script script/DeployDSC.s.sol --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY
```

## 🔐 Security

### Known Issues & Considerations

1. **Oracle Dependency**: Relies on Chainlink price feeds
2. **Liquidation Risk**: Users must maintain >200% collateral ratio
3. **Smart Contract Risk**: Unaudited code - use at your own risk

### Security Features

- ✅ Reentrancy protection
- ✅ Access control with OpenZeppelin
- ✅ Stale price feed protection
- ✅ Comprehensive input validation
- ✅ Health factor monitoring

> ⚠️ **Disclaimer**: This is an educational project and has not been audited. Do not use in production with real funds.

## 🤝 Contributing

Contributions are welcome! Please follow these steps:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Development Guidelines

- Follow Solidity style guide
- Add tests for new features
- Update documentation
- Ensure all tests pass

## 📚 Learning Resources

- [Foundry Documentation](https://book.getfoundry.sh/)
- [Solidity Documentation](https://docs.soliditylang.org/)
- [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts/)
- [Chainlink Price Feeds](https://docs.chain.link/data-feeds/price-feeds)

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [Patrick Collins](https://github.com/PatrickAlphaC) for the educational content
- [Foundry](https://github.com/foundry-rs/foundry) team for the amazing framework
- [OpenZeppelin](https://openzeppelin.com/) for secure contract libraries
- [Chainlink](https://chain.link/) for reliable oracle services

---

## 📊 Project Stats

- **Solidity Version**: ^0.8.20
- **Test Coverage**: 95%+
- **Contracts**: 3 core contracts
- **Dependencies**: OpenZeppelin, Chainlink
- **Framework**: Foundry

---

**Built with ❤️ using Foundry**
