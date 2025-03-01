## Gas Killer Smart Contracts 

Gas Killer is an AVS that uses BLS signature verification to securely simulate a transaction off chain and write back the storage slot updates to save gas associated with read and compute operations.

Our intentionally "dumb" voting contract loops through a large array of voters to calculate voting power to help us show gas saving potential.

# How It Works

1. **Traditional Approach**: All computation happens on-chain, requiring gas for every operation.
2. **Optimized Approach**: 
   - Computation happens off-chain (simulated by the operator)
   - Only storage updates are applied on-chain
   - BLS signatures verify the integrity of the updates

This pattern can be applied to any computation-heavy smart contract to significantly reduce gas costs.

# Features 
- **BLS Signature Verification**: Uses BLS signature aggregation for efficient multi-party consensus
- **Slashing Mechanism**: Implements objective on chain slashing
- **State Transition Management**: Tracks state transitions for consistent voting power calculation. Reverting if another write operation occurs first within same block before operator updates storage

# Gas Savings 

The optimized approach of running complex calculations off-chain and only applying storage updates on-chain demonstrates substantial gas savings:

- With 3000 voters: ~99% gas reduction
- With 1000 voters: ~97% gas reduction
- With 100 voters: ~81% gas reduction
- With 40 voters: ~63% gas reduction
- With 15 voters: ~38% gas reduction

As the number of voters increases, the gas savings become more pronounced, making this approach highly scalable for applications with large data sets.

# Running Tests

## Basic Functionality Tests

Verify the contract functionality with standard tests:

```shell
# Run all tests
forge test

# Run a specific test
forge test --match-test testAddVoter -vvv
```

## Gas Benchmarking

Compare gas usage between traditional and optimized approaches:

```shell
# Run the gas benchmark test
forge test --match-test testGasComparison -vvv

# Increase the gas limit if needed for large voter tests
forge test --match-test testGasComparison --gas-limit 1000000000 -vvv
```

## On-chain Benchmarking

For a real-world comparison, deploy and run benchmarks on a testnet:

```shell
# Set up environment (replace with your values)
export PRIVATE_KEY=your_private_key
export RPC_URL=your_rpc_url

# Deploy and run benchmark
forge script script/BenchmarkComparison.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast -vvv
```

## Computational Equivalence Testing

Verify that both the on chain and off chain approaches produce identical results:

```shell
forge test --match-test testComputationalEquivalence -vvv
```

## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
