# Zorro Protocol

(Short description)
Website: https://zorro.finance
App: https://app.zorro.finance
Docs: (Use website for now)

# Tech stack

# Contracts

TODO: Diagrams

# Pools

# Zorro Controller

# Vaults

# Zorro ERC20 (BEP20) token

# Contract Addresses

(Binance Smart Chain (BSC))

## Testnet

## Mainnet

# Cross Chain

(Coming soon)

# Compliance and Safety Features
* Open Zeppelin (SafeMath, Ownable, Pausable, Reentrancy guards)
* Vesting (anti rugpull)
* Pay splitting
* Timelock controllers
* Rigorous Unit testing (Truffle Suite)
* Coverage against all common EVM vulnerabilities
* Front running protection
* Pure on-chain solution

## Audit report
(Coming soon)

# Tests

Description 

## Running tests

Instructions

# Glossary
* **want address**: Address of the farm (e.g. PancakePair). Token is the LP token, when liquidity mining
* **earn token**: xxx
* **vault**: Vault on Zorro side
* **pool**: (aka "Farm") - the instance of the vault that corresponds to the underlying farm 
* **reward debt**: A way to mark how many Zorro tokens were issued as rewards at a given block. The next time these rewards are calculated, the reward debt is subtraced from the new rewards amount so that only the rewards over the elapsed time period are counted.

# Upgradeability
Transparent Proxy based on OpenZeppelin standard

# Installation 
```
yarn add @chainlink/contracts
```