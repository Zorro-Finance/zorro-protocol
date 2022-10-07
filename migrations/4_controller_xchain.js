// Upgrades
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
// Controller
const ZorroControllerXChain = artifacts.require("ZorroControllerXChain");
const ZorroController = artifacts.require("ZorroController");
// Token
const Zorro = artifacts.require('Zorro');
// Get key params
const {getKeyParams, getSynthNetwork} = require('../chains');
const zeroAddress = '0x0000000000000000000000000000000000000000';

module.exports = async function (deployer, network, accounts) {
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
  console.log('zcxc init val: ', zcxInitVal.priceFeeds);
  await deployProxy(ZorroControllerXChain, [zcxInitVal], {deployer});

  // Update ZorroController
  const zorroControllerXChain = await ZorroControllerXChain.deployed();
  await zorroController.setZorroXChainEndpoint(zorroControllerXChain.address);
};

// TODO: Don't forget to eventually assign timelockowner