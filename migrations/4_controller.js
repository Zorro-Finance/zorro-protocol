// Upgrades
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
// Get key params
const {
  getKeyParams, 
  getSynthNetwork, 
  homeNetworks, 
  devNets, 
  testNets, 
  zeroAddress,
  wavaxOnAvax,
} = require('../chains');

// Controller
const ZorroController = artifacts.require("ZorroController");
// Token
const Zorro = artifacts.require('Zorro');
// Price feeds
const ZORPriceFeed = artifacts.require("ZORPriceFeed");
// Mocks
const MockInvestmentVault = artifacts.require("MockInvestmentVault");
const MockInvestmentVault1 = artifacts.require("MockInvestmentVault1");


module.exports = async function (deployer, network, accounts) {
  /* Production */

  // Deploy ZOR price feed
  const zorPriceFeed = await ZORPriceFeed.deployed();

  // Existing contracts
  const zorro = await Zorro.deployed();
  await deployer.deploy(ZORPriceFeed, uniRouterAddress, zorro.address, zorroLPPoolOtherToken, defaultStablecoin);

  // Unpack keyParams
  const {
    defaultStablecoin,
    uniRouterAddress,
    zorroLPPoolOtherToken,
    stablecoinToZorroPath,
    stablecoinToZorroLPPoolOtherTokenPath,
    rewards,
    xChain,
    priceFeeds,
    zorroLPPool,
  } = getKeyParams(accounts, zorro.address)[getSynthNetwork(network)];

  // Defaults to non-home-chain value. See below.
  let zcInitVal = {
      ZORRO: zorro.address,
      defaultStablecoin,
      zorroLPPoolOtherToken,
      publicPool: zeroAddress, // will be filled in subsequent migration
      zorroStakingVault: zeroAddress, // ditto
      zorroLPPool,
      uniRouterAddress,
      stablecoinToZorroPath,
      stablecoinToZorroLPPoolOtherTokenPath,
      rewards,
      xChain,
      priceFeeds,
  };

  if (['avax', 'avaxfork'].includes(network)) {
    /* Home chain */

    // Prep init values
    zcInitVal = {
      ...zcInitVal, 
      ...{
        stablecoinToZorroPath: [defaultStablecoin, wavaxOnAvax, zorro.address],
        rewards,
        xChain,
        priceFeeds: {
          ...priceFeeds,
          ...{
            priceFeedZOR: zorPriceFeed,
          },
        },
      },
    };
  }

  // Deploy
  await deployProxy(ZorroController, [zcInitVal], {deployer});
  // Update XChain props to correct home chain Zorro controller if on the home chain
  if (homeNetworks.includes(network)) {
    const zorroController = await ZorroController.deployed();
    await zorroController.setXChainParams(xChain.chainId, xChain.homeChainId, zorroController.address);
  }

  /* Tests */

  // Allowed networks: Test/dev only
  if (testNets.includes(network)) {
    // Mock vaults
    for (let invVault of [MockInvestmentVault, MockInvestmentVault1]) {
      await deployer.link(VaultLibrary, [invVault]);
      await deployProxy(
        invVault,
        [
          accounts[0]
        ], {
        deployer,
        unsafeAllow: [
          'external-library-linking',
        ],
      });
    }

    // Zorro Controller
    const mockZCInitVal = {
      ZORRO: MockZorroToken.address,
      defaultStablecoin: zeroAddress,
      zorroLPPoolOtherToken: zeroAddress,
      publicPool: zeroAddress,
      zorroStakingVault: zeroAddress,
      zorroLPPool: zeroAddress,
      uniRouterAddress: zeroAddress,
      stablecoinToZorroPath: [],
      stablecoinToZorroLPPoolOtherTokenPath: [],
      rewards: {
        blocksPerDay: 0,
        startBlock: 0,
        ZORROPerBlock: 0,
        targetTVLCaptureBasisPoints: 0,
        chainMultiplier: 0,
        baseRewardRateBasisPoints: 0,
      },
      xChain: {
        chainId: 0,
        homeChainId: 0,
        homeChainZorroController: zeroAddress,
        zorroControllerOracle: zeroAddress,
        zorroXChainEndpoint: zeroAddress,
      },
      priceFeeds: {
        priceFeedZOR: zeroAddress,
        priceFeedLPPoolOtherToken: zeroAddress,
        stablecoinPriceFeed: zeroAddress,
      },
    };
    await deployProxy(MockZorroController, [mockZCInitVal], { deployer });
  }

};