// Upgrades
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
// Get key params
const {
  getSynthNetwork,
} = require('../helpers/chains');
const { chains, zeroAddress, vaultFees } = require('../helpers/constants');

// Vaults
const PCS_ZOR_BNB = artifacts.require("PCS_ZOR_BNB");
// Actions
const VaultActionsStandardAMM = artifacts.require('VaultActionsStandardAMM');
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
  /* Production */

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
    const zorroLPPool = await iUniswapV2Factory.getPair.call(zorro.address, tokens.wbnb);

    // Deploy actions contract
    const vaultActionsStandardAMM = await deployProxy(VaultActionsStandardAMM, [infra.uniRouterAddress], { deployer });

    // TODO: Need to fund the pool? Or rather, check to see if exchange rate can be calculated with zero pool?

    // Init values 
    const initVal = {
      baseInit: {
        config: {
          // TODO: Use correct PID from created pool above
          pid: 0,
          isHomeChain: true,
        },
        keyAddresses: {
          govAddress: vaultTimelock.address,
          zorroControllerAddress: zorroController.address,
          zorroXChainController: zorroControllerXChain.address,
          ZORROAddress: zorro.address,
          zorroStakingVault: vaultZorro.address,
          wantAddress: zorroLPPool,
          token0Address: zorro.address,
          token1Address: tokens.wbnb,
          earnedAddress: protocols.pancakeswap.cake,
          farmContractAddress: protocols.pancakeswap.masterChef,
          treasury: poolTreasury.address,
          poolAddress: zorroLPPool,
          uniRouterAddress: infra.uniRouterAddress,
          zorroLPPool: zorroLPPool,
          zorroLPPoolOtherToken: tokens.wbnb,
          defaultStablecoin: tokens.busd,
          vaultActions: vaultActionsStandardAMM.address,
        },
        swapPaths: {
          earnedToZORROPath: [protocols.pancakeswap.cake, tokens.wbnb, zorro.address],
          earnedToToken0Path: [protocols.pancakeswap.cake, tokens.wbnb, zorro.address],
          earnedToToken1Path: [protocols.pancakeswap.cake, tokens.wbnb],
          stablecoinToToken0Path: [tokens.busd, tokens.wbnb, zorro.address],
          stablecoinToToken1Path: [tokens.busd, tokens.wbnb],
          earnedToZORLPPoolOtherTokenPath: [protocols.pancakeswap.cake, tokens.wbnb],
          earnedToStablecoinPath: [protocols.pancakeswap.cake, tokens.wbnb, tokens.busd],
          stablecoinToZORROPath: [tokens.busd, tokens.wbnb, zorro.address],
          stablecoinToLPPoolOtherTokenPath: [tokens.busd, tokens.wbnb],
        },
        fees: vaultFees,
        priceFeeds: {
          token0PriceFeed: zorPriceFeed.address,
          token1PriceFeed: priceFeeds.bnb,
          earnTokenPriceFeed: priceFeeds.cake,
          ZORPriceFeed: zorPriceFeed.address,
          lpPoolOtherTokenPriceFeed: priceFeeds.bnb,
          stablecoinPriceFeed: priceFeeds.busd,
        },
      },
      isLPFarmable: false,
    };

    // Deploy
    await deployProxy(PCS_ZOR_BNB,
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

// TODO: For all vaults!: call the addVault() func with appropriate multiplier