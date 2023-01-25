// Upgrades
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
// Get key params
const {
  getSynthNetwork,
} = require('../helpers/chains');
const { chains, zeroAddress } = require('../helpers/constants');

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
    const { bnb, vaultFees } = chains;
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
    const zorroLPPool = iUniswapV2Factory.getPair.call(zorro.address, tokens.wbnb);

    // Deploy actions contract
    const vaultActionsApeLending = await deployProxy(VaultActionsApeLending, [infra.uniRouterAddress], { deployer });

    // Init values 
    const initVal = {
      pid: 0,
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
        zorroLPPool,
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
      // TODO: fill in
      targetBorrowLimit: 0,
      targetBorrowLimitHysteresis: 0,
      comptrollerAddress: zeroAddress,
      lendingToken: protocols.apeswap.ethLendingPool,
    };

    // Deploy
    await deployProxy(VaultApeLendingETH,
      [
        vaultTimelock.address,
        initVal,``
      ],
      {
        deployer,
      }
    );
  } else {
    console.log('Not BNB chain. Skipping vault creation');
  }
};