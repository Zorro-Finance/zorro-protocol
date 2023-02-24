// Upgrades
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
// Get key params
const {
  getSynthNetwork,
  isTestNetwork,
} = require('../helpers/chains');
const { chains, zeroAddress, vaultFees } = require('../helpers/constants');

// Vaults
const VaultAlpacaBNB = artifacts.require("VaultAlpacaBNB");
// Actions
const VaultActionsAlpaca = artifacts.require('VaultActionsAlpaca');
// Price feeds
const ZORPriceFeed = artifacts.require('ZORPriceFeed');
// Other contracts
const ZorroController = artifacts.require("ZorroController");
const ZorroControllerXChain = artifacts.require("ZorroControllerXChain");
const Zorro = artifacts.require("Zorro");
const VaultZorro = artifacts.require('VaultZorro');
const VaultTimelock = artifacts.require('VaultTimelock');
const PoolTreasury = artifacts.require('PoolTreasury');
const IUniswapV2Factory = artifacts.require('IUniswapV2Factory');

module.exports = async function (deployer, network, accounts) {
  // Chain check 
  if (isTestNetwork(network)) {
    console.log('On Testnet. Skipping...');
    return;
  }

  // Deployed contracts
  const zorroController = await ZorroController.deployed();
  const zorroControllerXChain = await ZorroControllerXChain.deployed();
  const zorro = await Zorro.deployed();
  const vaultTimelock = await VaultTimelock.deployed();
  const poolTreasury = await PoolTreasury.deployed();

  
  if (getSynthNetwork(network) === 'bnb') {
    // Unpack keyParams
    const { bnb } = chains;
    const {
      tokens,
      priceFeeds,
      infra,
      protocols,
    } = bnb;

    // Deployed contracts
    const zorPriceFeed = await ZORPriceFeed.deployed();
    const vaultZorro = await VaultZorro.deployed();

    // Get Zorro LP pool
    const iUniswapV2Factory = await IUniswapV2Factory.at(infra.uniFactoryAddress);
    const ZORBNBLPPool = await iUniswapV2Factory.getPair.call(zorro.address, tokens.wbnb);

    // Deploy actions contract
    const vaultActionsAlpaca = await deployProxy(VaultActionsAlpaca, [infra.uniRouterAddress], { deployer });

    // Init values 
    const initVal = {
      baseInit: {
        config: {
          pid: 0,
          isHomeChain: true,
        },
        keyAddresses: {
          govAddress: vaultTimelock.address,
          zorroControllerAddress: zorroController.address,
          zorroXChainController: zorroControllerXChain.address,
          ZORROAddress: zorro.address,
          zorroStakingVault: vaultZorro.address,
          wantAddress: tokens.wbnb,
          token0Address: tokens.wbnb,
          token1Address: zeroAddress,
          earnedAddress: protocols.alpaca.alpaca,
          farmContractAddress: protocols.alpaca.fairLaunch,
          treasury: poolTreasury.address,
          poolAddress: protocols.alpaca.levPoolBNB,
          uniRouterAddress: infra.uniRouterAddress,
          zorroLPPool: ZORBNBLPPool,
          zorroLPPoolOtherToken: tokens.wbnb,
          defaultStablecoin: tokens.busd,
          vaultActions: vaultActionsAlpaca.address,
        },
        swapPaths: {
          earnedToZORROPath: [protocols.alpaca.alpaca, tokens.busd, tokens.wbnb, zorro.address],
          earnedToToken0Path: [protocols.alpaca.alpaca, tokens.busd, tokens.wbnb],
          earnedToToken1Path: [],
          stablecoinToToken0Path: [tokens.busd, tokens.wbnb],
          stablecoinToToken1Path: [],
          earnedToZORLPPoolOtherTokenPath: [protocols.alpaca.alpaca, tokens.wbnb],
          earnedToStablecoinPath: [protocols.alpaca.alpaca, tokens.busd],
          stablecoinToZORROPath: [tokens.busd, tokens.wbnb, zorro.address],
          stablecoinToLPPoolOtherTokenPath: [tokens.busd, tokens.wbnb],
        },
        fees: vaultFees,
        priceFeeds: {
          token0PriceFeed: zorPriceFeed.address,
          token1PriceFeed: zeroAddress,
          earnTokenPriceFeed: zeroAddress,
          ZORPriceFeed: zorPriceFeed.address,
          lpPoolOtherTokenPriceFeed: priceFeeds.bnb,
          stablecoinPriceFeed: priceFeeds.busd,
        },
        dstGasForEarningsCall: 100000,
      },
      // TODO: fill in with real address
      lendingToken: zeroAddress,
    };

    // Deploy
    await deployProxy(VaultAlpacaBNB,
      [
        vaultTimelock.address,
        initVal,
      ],
      {
        deployer,
      }
    );
  } else {
    console.log('Not BNB chain. Skipping vault creation');
  }
};