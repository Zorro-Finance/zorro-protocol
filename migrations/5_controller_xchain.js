// Upgrades
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
// Get key params
const {
  getKeyParams, 
  getSynthNetwork, 
  zeroAddress, 
  testNets,
} = require('../chains');

// Controller
const ZorroControllerXChain = artifacts.require("ZorroControllerXChain");
const ZorroController = artifacts.require("ZorroController");
const MockZorroControllerXChain = artifacts.require("MockZorroControllerXChain");
// Token
const Zorro = artifacts.require('Zorro');

module.exports = async function (deployer, network, accounts) {
  /* Production */

  // Existing contracts
  const zorro = await Zorro.deployed();
  const zorroController = await ZorroController.deployed();

  // Unpack keyParams
  const {
    defaultStablecoin,
    uniRouterAddress,
    zorroLPPoolOtherToken,
    stablecoinToZorroPath,
    stablecoinToZorroLPPoolOtherTokenPath,
    priceFeeds,
    bridge,
  } = getKeyParams(accounts, zorro.address)[getSynthNetwork(network)];
  
  // Prep init values
  let zcxInitVal = {
    defaultStablecoin,
    ZORRO: zorro.address,
    zorroLPPoolOtherToken,
    zorroStakingVault: zeroAddress, // Will be reset in subsequent migration
    uniRouterAddress,
    homeChainZorroController: zorroController.address,
    currentChainController: zorroController.address,
    publicPool: zeroAddress, // Must be set later
    bridge: {
      ...bridge,
      ...{
        controllerContracts: [zorroController.address],
      },
    },
    swaps: {
      stablecoinToZorroPath,
      stablecoinToZorroLPPoolOtherTokenPath,
    },
    priceFeeds,
  };

  // Deploy
  await deployProxy(ZorroControllerXChain, [zcxInitVal], {deployer});

  // Update ZorroController
  const zorroControllerXChain = await ZorroControllerXChain.deployed();
  await zorroController.setZorroXChainEndpoint(zorroControllerXChain.address);

  /* Tests */
  // Allowed networks: Test/dev only
  if (testNets.includes(network)) {
    // Zorro Controller X Chain
    const mockZCXInitVal = {
      defaultStablecoin: zeroAddress,
      ZORRO: MockZorroToken.address,
      zorroLPPoolOtherToken: zeroAddress,
      zorroStakingVault: zeroAddress,
      uniRouterAddress: zeroAddress,
      homeChainZorroController: zeroAddress,
      currentChainController: zeroAddress,
      publicPool: zeroAddress,
      bridge: {
        chainId: 0,
        homeChainId: 0,
        ZorroChainIDs: [],
        controllerContracts: [],
        LZChainIDs: [],
        stargateDestPoolIds: [],
        stargateRouter: zeroAddress,
        layerZeroEndpoint: zeroAddress,
        stargateSwapPoolId: zeroAddress,
      },
      swaps: {
        stablecoinToZorroPath: [],
        stablecoinToZorroLPPoolOtherTokenPath: [],
      },
      priceFeeds: {
        priceFeedZOR: zeroAddress,
        priceFeedLPPoolOtherToken: zeroAddress,
        priceFeedStablecoin: zeroAddress,
      },
    };
    await deployProxy(MockZorroControllerXChain, [mockZCXInitVal], { deployer });
  }
};

// TODO: Don't forget to eventually assign timelockowner