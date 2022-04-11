# Zorro Protocol

Next-gen cross-chain yield aggregation.

The Zorro protcol is a true cross-chain yield aggregator that allows one to take advantage of yield farming opportunities cross-chain without ever leaving your home chain, and features dynamic, market adjusted tokenomics to maximize returns to investors. 

**Website:** https://zorro.finance
**App:** https://app.zorro.finance (Coming soon)
**Docs:** Gitbook (Coming soon)

# Tech stack

* Solidity ^0.8.0
* Truffle Suite
* OpenZeppelin libraries
* Timelock architecture
* Upgradeable contracts via compliant proxies
* Chainlink Oracle

# Mainnet Contracts

The Zorro protocol is deployed on multiple chains, and AVAX is the so called "home chain" of the protocol. The 
home chain is where ZORRO tokens are originally minted and is the source of all rewardsn for users. 

_NOTE: Addresses coming soon, and will be updated below once contracts are deployed._

## Avalanche (AVAX)

* Zorro token: `0x0`
* Controller contract: `0x0`
* Zorro staking vault contract: `0x0`
* Public pool: `0x0`
* Treasury pool: `0x0`

## Binance Smart Chain (BSC)

* Zorro token: `0x0`
* Controller contract: `0x0`
* Zorro staking vault contract: `0x0`
* Treasury pool: `0x0`

## Coming soon

* Fantom
* Terra
* Solana

# How to navigate this repo

We follow standard file organization conventions as used by TruffleSuite and common Solidity community conventions.

# File organization

```
build # Compiled code and abi JSON files
contracts # Directory of all contract code
--/controllers # All sub contracts that comprise the controller contract
--/finance # All contracts related to finance (vesting, etc.)
--/interfaces # All interfaces that all contracts conform to
--/libraries # Solidity libraries
--/timelock # Timelock contracts that own the controller and vault contracts
--/tokens # The ZOR ERC20 contract and any future tokens that we release
--/vaults # All vaults (aka investment strategies) that Zorro offers
--Migrations.sol # Truffle migrations file
migrations # Directory of all migrations applied (i.e. deployed contracts)
test # Directory of all tests
truffle-config.js # Truffle config
package.json # NPM packages that we import from remote
```

## Conventions

All contracts beginning with underscores (e.g. `_ZorroControllerBase`) are not deployed contracts, but rather "pieces" 
that we inherit from for the contracts that we DO deploy (e.g. `ZorroController`). This helps keep code more readable
and organized. 

Local variables tend to begin with underscores by convention (e.g. `amountUSDC`) to reduce confusion with global storage 
variables and increase safety. 

# Code explanations

This section outlines each contract, their purpose, and any other important details. 

## Zorro Controller (and subcontracts)

The `ZorroController` contract actually inherits from all the "partial" contracts below. Together, this contract 
controls nearly all on-chain and cross-chain investment activity. Almost all external activity must go through the controller.
Some examples of the controller's responsibilities:

* Deposits + withdrawals
* Updating pool rewards
* Sending and receiving cross chain transactions
* ...and much more!

### ZorroControllerBase

`ZorroControllerBase` declares most common state variables, constants, and shared functions used by other partial contracts 
below. This base contract also contains a lot of shared logic for distributing rewards. 

### ZorroControllerAnalytics

`ZorroControllerAnalytics` contains view-only functions that are used for the frontend/UI to display stats for the user.

### ZorroControllerInvestment

`ZorrocontrollerInvestment` contains most of the core investment functions (deposits, withdrawals, etc.). This contract
also performs a lot of rewards logic and distribution.

### ZorroControllerPoolMgmt

`ZorroControllerPoolMgmt` is used to add and set values for new and existing pools.

## ZorroControllerXChain (and subcontracts)

The `ZorroControllerXChain` contract is the counterpart contract to `ZorroController` and as the name implies, is the interface for
all cross-chain activity. Its logic is composed of the follow contracts below, which it inherits from.

### ZorroControllerXChainBase

`ZorroControllerXChainBase` declares most common state variables, constants, and shared functions used by other partial contracts 
below. This base contract also contains a lot of shared logic for distributing rewards. 

* `ZorroControllerXChainDeposit` contains all functions for sending/receiving deposits across chains.
* `ZorroControllerXChainEarn` contains all functions for cross chain autocompounding and distributing rewards (aka "earnings").
* `ZorroControllerXChainWithdrawal` contains all functions for triggering and receiving withdrawals across chains.
* `ZorroControllerXChainReceiver` implements receiving logic for LayerZero/Stargate fro cross chain bridging and messaging.

## Vaults

**Vaults** in Zorro terminology refer to contracts that perform yield aggregation/farming operations upon existing DeFi pools
and assets. Vaults always operate upon an underlying "pool" (aka "Defi asset"), such as a Sushiswap pool, a staking vault on 
another protocol, or other yield farming "lego blocks."

Thus, a Vault subclass inheriting from the `VaultBase` contract and conforming to `IVault` is required for every new type of 
pool/protocol added to Zorro. Examples of Vaults (each corresponding to a pool/protocol type) that are already deployed can 
be seen in the contracts/vaults folder here: 

* `VaultAcryptosSingle`
* `VaultStandardAMM`
* `VaultZorro` << Zorro's staking vault!

# Financial Pools

As can be seen in our [Tokenomics paper](https://www.zorro.finance/tokenomics/), we have three types of financial pools
where ZOR funds flow between: **Public pool, Treasury, and Team**. 

## Public pool

The public pool only exists on the home chain (AVAX), and is where the original and sole ZOR token is minted and distributed.
NOTE: "Wrapped" ZOR still exists on other chains, but its value is still pegged to the original, home chain ZOR token.

A finite amount of ZOR tokens are minted at inception for investors of the Zorro protocol. The ZOR tokens ar rewarded with an exponentially-decay function that responds to market conditions, in order to optimize emissions while keeping inflation 
in check, and to never run out of tokens to distribute. 

Other ZOR tokens (at inception) are sent to the Treasury and Team with vesting controls (see below) in accordance with 
our tokenomics.

The public pool is owned by a timelock contract.

## Treasury pool

The treasury contract is an instance of the `ModifiedVestingWallet`, which in turn is an instance of OpenZeppelin's 
[VestingWallet](https://docs.openzeppelin.com/contracts/4.x/api/finance#VestingWallet). This helps protect the value
of the ZOR token and keep incentives aligned for the long term.

## Team 

The "Team" consists of the original founding team, along with other team members. Each of these members get their own
`ModifiedVestingWallet` as per above. For more information, consult our [tokenomics](https://www.zorro.finance/tokenomics/) page.

# Zorro ERC20 token

The ZOR token is minted by the `PublicPool` contract as an ERC20 compliant token. This done on the home chain (AVAX) ONLY, 
however, synthetic (aka "wrapped") versions of ZOR are available on other chains, which are pegged to the home chain ZOR's
value. 

# Compliance and Safety Features

* Open Zeppelin access control (SafeMath, Ownable, Pausable, Reentrancy guards)
* OpenZeppelin Vesting contract (trustless finance)
* Timelock controllers (anti-rugpull)
* Rigorous Unit testing (Truffle Suite)
* Coverage against all common EVM vulnerabilities
* Front running protection
* Pure trustless protocol

## Audit report
(Coming soon)

# Concepts

## Cross chain identity

Zorro protocol has the unique ability to maintain multiple identities of investors as they perform investment activities 
across chains. For example, a user can deposit funds in a Terra vault while making the request on the AVAX chain. To withdraw,
they have two options: 1) Send a withdrawal request from the origin chain and have the funds repatriated, or 2) Connect
with their Terra wallet and withdraw the funds directly on the remote chain. This allows for maximal flexibility. 

## Home chain

The Zorro protocol is truly cross chain. Unlike several yield aggregators that simply clone their protocol on multiple chains,
Zorro allows for full interopability and bridging between different chains, and mints ZOR tokens from a single chain, the home chain, to maximize the value and utility of the ZOR token. All other chains still get ZOR rewards, but they are pegged 
to the home chain, and the supply is kept constant across all chains via the protocol. 

# Installation 

```bash
yarn
```

# Tests

Unit tests are run using Truffle/Mocha. 

```bash
truffle test
```

# Upgradeability

To allow for more features and fixes, we implement a _Transparent Proxy_ based on OpenZeppelin Upgradeability standard. 
[Upgradeable Contracts](https://docs.openzeppelin.com/upgrades-plugins/1.x/proxies)

# Glossary

* **want address**: Address of the farm (e.g. PancakePair). Token is the LP token, when liquidity mining
* **earn token**: Address of the farm token (e.g. Cake)
* **vault**: Contract responsible for farming the pool
* **pool**: Contract (usually a 3rd party) providing the investment opportunity (e.g. an LP pool)
* **reward debt**: A way to mark how many Zorro tokens were issued as rewards at a given block. The next time these rewards are calculated, the reward debt is subtraced from the new rewards amount so that only the rewards over the elapsed time period are counted.
* **foreign account**: Account on the origin chain that made the cross chain deposit
* **local account**: On chain account that is associated with a deposit

# Contact

[@deltakilomilo](https://twitter.com/deltakilomilo/)

[@zorroappcrypto](https://twitter.com/zorroappcrypto)
