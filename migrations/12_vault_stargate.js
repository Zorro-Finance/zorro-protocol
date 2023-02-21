// Upgrades
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
// Get key params
const {
  getSynthNetwork,
  isTestNetwork,
} = require('../helpers/chains');
const { chains, zeroAddress, vaultFees } = require('../helpers/constants');

// Vaults
const StargateUSDTOnAVAX = artifacts.require("StargateUSDTOnAVAX");
const StargateBUSDOnBNB = artifacts.require("StargateBUSDOnBNB");
// Actions
const VaultActionsStargate = artifacts.require('VaultActionsStargate');
// Price feeds
const STGPriceFeed = artifacts.require('STGPriceFeed');
const ZORPriceFeed = artifacts.require('ZORPriceFeed');
// Other contracts
const Zorro = artifacts.require("Zorro");
const ZorroController = artifacts.require("ZorroController");
const ZorroControllerXChain = artifacts.require("ZorroControllerXChain");
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
  const vaultTimelock = await VaultTimelock.deployed();
  const poolTreasury = await PoolTreasury.deployed();

  /* AVAX Chain */

  if (getSynthNetwork(network) === 'avax') {
    // Unpack keyParams
    const { avax } = chains;
    const {
      tokens,
      priceFeeds,
      infra,
      protocols,
    } = avax;

    // Deploy contracts
    const vaultActionsStargate = await deployer.deploy(VaultActionsStargate, infra.uniRouterAddress);
    // Deploy contracts
    const stgPriceFeed = await deployer.deploy(
      STGPriceFeed, 
      infra.uniRouterAddress,
      tokens.stg,
      tokens.usdc
    );

    // Init values 
    const initVal = {
      baseInit: {
        config: {
          pid: 0, // TODO: Change to actual PID
          isHomeChain: false,
        },
        keyAddresses: {
          govAddress: vaultTimelock.address,
          zorroControllerAddress: zorroController.address,
          zorroXChainController: zorroControllerXChain.address,
          ZORROAddress: zeroAddress,
          zorroStakingVault: zeroAddress,
          wantAddress: tokens.usdt,
          token0Address: tokens.usdt,
          token1Address: zeroAddress,
          earnedAddress: tokens.stg,
          farmContractAddress: protocols.stargate.lpStaking,
          treasury: poolTreasury.address,
          poolAddress: protocols.stargate.poolUSDT,
          uniRouterAddress: infra.uniRouterAddress,
          zorroLPPool: zeroAddress,
          zorroLPPoolOtherToken: zeroAddress,
          defaultStablecoin: tokens.usdc,
          vaultActions: vaultActionsStargate.address,
        },
        swapPaths: {
          earnedToZORROPath: [],
          earnedToToken0Path: [tokens.stg, tokens.usdc, tokens.usdt],
          earnedToToken1Path: [],
          stablecoinToToken0Path: [tokens.usdc, tokens.usdt],
          stablecoinToToken1Path: [],
          earnedToZORLPPoolOtherTokenPath: [],
          earnedToStablecoinPath: [tokens.stg, tokens.usdc],
          stablecoinToZORROPath: [],
          stablecoinToLPPoolOtherTokenPath: [],
        },
        fees: vaultFees,
        priceFeeds: {
          token0PriceFeed: priceFeeds.usdt,
          token1PriceFeed: zeroAddress,
          earnTokenPriceFeed: stgPriceFeed.address,
          ZORPriceFeed: zeroAddress,
          lpPoolOtherTokenPriceFeed: zeroAddress,
          stablecoinPriceFeed: priceFeeds.usdc,
        },
      },
      stargateRouter: infra.stargateRouter,
      stargatePoolId: 2,
    };

    // Deploy
    await deployProxy(StargateUSDTOnAVAX,
      [
        vaultTimelock.address,
        initVal,
      ],
      {
        deployer,
      }
    );
  } else {
    console.log('Not AVAX chain. Skipping vault creation');
  }

  /* BNB Chain */

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
    const zorro = await Zorro.deployed();
    const vaultZorro = await VaultZorro.deployed();
    const zorPriceFeed = await ZORPriceFeed.deployed();
    // Deploy contracts
    const stgPriceFeed = await deployer.deploy(
      STGPriceFeed, 
      infra.uniRouterAddress,
      tokens.stg,
      tokens.usdc
    );

    // Get Zorro LP pool
    const iUniswapV2Factory = await IUniswapV2Factory.at(infra.uniFactoryAddress);
    const zorroLPPool = await iUniswapV2Factory.getPair.call(zorro.address, tokens.wbnb);

    // Deploy contracts
    const vaultActionsStargate = await deployer.deploy(VaultActionsStargate, infra.uniRouterAddress);

    // Init values 
    const initVal = {
      baseInit: {
        config: {
          pid: 0, // TODO: Change to actual PID
          isHomeChain: true,
        },
        keyAddresses: {
          govAddress: vaultTimelock.address,
          zorroControllerAddress: zorroController.address,
          zorroXChainController: zorroControllerXChain.address,
          ZORROAddress: zorro.address,
          zorroStakingVault: vaultZorro.address,
          wantAddress: tokens.busd,
          token0Address: tokens.busd,
          token1Address: zeroAddress,
          earnedAddress: protocols.stargate.stg,
          farmContractAddress: protocols.stargate.lpStaking,
          treasury: poolTreasury.address,
          poolAddress: protocols.stargate.poolBUSD,
          uniRouterAddress: infra.uniRouterAddress,
          zorroLPPool: zorroLPPool,
          zorroLPPoolOtherToken: tokens.wbnb,
          defaultStablecoin: tokens.busd,
          vaultActions: vaultActionsStargate.address,
        },
        swapPaths: {
          earnedToZORROPath: [protocols.stargate.stg, tokens.busd, tokens.wbnb, zorro.address],
          earnedToToken0Path: [protocols.stargate.stg, tokens.busd],
          earnedToToken1Path: [],
          stablecoinToToken0Path: [],
          stablecoinToToken1Path: [],
          earnedToZORLPPoolOtherTokenPath: [protocols.stargate.stg, tokens.busd, tokens.wbnb],
          earnedToStablecoinPath: [protocols.stargate.stg, tokens.busd],
          stablecoinToZORROPath: [tokens.busd, tokens.wbnb, zorro.address],
          stablecoinToLPPoolOtherTokenPath: [tokens.busd, tokens.wbnb],
        },
        fees: vaultFees,
        priceFeeds: {
          token0PriceFeed: priceFeeds.busd,
          token1PriceFeed: zeroAddress,
          earnTokenPriceFeed: stgPriceFeed.address,
          ZORPriceFeed: zorPriceFeed.address,
          lpPoolOtherTokenPriceFeed: priceFeeds.bnb,
          stablecoinPriceFeed: priceFeeds.busd,
        },
      },
      stargateRouter: infra.stargateRouter,
      stargatePoolId: 5,
    };

    // Deploy
    await deployProxy(StargateBUSDOnBNB,
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