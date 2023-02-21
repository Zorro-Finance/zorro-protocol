// Upgrades
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
// Get key params
const {
  getSynthNetwork,
  isTestNetwork,
} = require('../helpers/chains');
const { chains, zeroAddress, vaultFees } = require('../helpers/constants');
// Migration
const Migrations = artifacts.require("Migrations");

// Vaults
const VaultApeLendingETH = artifacts.require("VaultApeLendingETH");
// Actions
const VaultActionsApeLending = artifacts.require('VaultActionsApeLending');
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

  // Web3
  const adapter = Migrations.interfaceAdapter;
  const { web3 } = adapter;

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
    const vaultActionsApeLending = await deployProxy(VaultActionsApeLending, [infra.uniRouterAddress], { deployer });

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
          earnedAddress: protocols.apeswap.banana,
          farmContractAddress: protocols.apeswap.unitroller,
          treasury: poolTreasury.address,
          poolAddress: protocols.apeswap.ethLendingPool,
          uniRouterAddress: infra.uniRouterAddress,
          zorroLPPool: ZORBNBLPPool,
          zorroLPPoolOtherToken: tokens.wbnb,
          defaultStablecoin: tokens.busd,
          vaultActions: vaultActionsApeLending.address,
        },
        swapPaths: {
          earnedToZORROPath: [protocols.apeswap.banana, tokens.wbnb, zorro.address],
          earnedToToken0Path: [protocols.apeswap.banana, tokens.wbnb, tokens.eth],
          earnedToToken1Path: [],
          stablecoinToToken0Path: [tokens.busd, tokens.eth],
          stablecoinToToken1Path: [],
          earnedToZORLPPoolOtherTokenPath: [protocols.apeswap.banana, tokens.wbnb],
          earnedToStablecoinPath: [protocols.apeswap.banana, tokens.wbnb, tokens.busd],
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
      },
      targetBorrowLimit: web3.utils.toWei('700', 'milli'), // 1% = 1e16
      targetBorrowLimitHysteresis: web3.utils.toWei('10', 'milli'), // 1% = 1e16
      comptrollerAddress: protocols.apeswap.unitroller,
      lendingToken: protocols.apeswap.ethLendingPool,
    };

    // Deploy
    await deployProxy(VaultApeLendingETH,
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