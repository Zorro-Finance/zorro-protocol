// Upgrades
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
// Controller
const ZorroControllerXChain = artifacts.require("ZorroControllerXChain");
// Token
const Zorro = artifacts.require('Zorro');

module.exports = async function (deployer, network, accounts) {
  // Existing contracts
  const ZorroToken = await Zorro.deployed();
  
  // Prep init values
  let zcxInitVal = {
    defaultStablecoin: '0x0000000000000000000000000000000000000000',
    ZORRO: ZorroToken.address,
    zorroLPPoolOtherToken: '0x0000000000000000000000000000000000000000',
    zorroStakingVault: '0x0000000000000000000000000000000000000000',
    uniRouterAddress: '0x0000000000000000000000000000000000000000',
    homeChainZorroController: '0x0000000000000000000000000000000000000000',
    currentChainController: '0x0000000000000000000000000000000000000000',
    publicPool: '0x0000000000000000000000000000000000000000',
    bridge: {
      chainId: 0,
      homeChainId: 0,
      ZorroChainIDs: [],
      controllerContracts: [],
      LZChainIDs: [],
      stargateDestPoolIds: [],
      stargateRouter: '0x0000000000000000000000000000000000000000',
      layerZeroEndpoint: '0x0000000000000000000000000000000000000000',
      stargateSwapPoolId: '0x0000000000000000000000000000000000000000',
    },
    swaps: {
      USDCToZorroPath: [],
      USDCToZorroLPPoolOtherTokenPath: [],
    },
    priceFeeds: {
      priceFeedZOR: '0x0000000000000000000000000000000000000000',
      priceFeedLPPoolOtherToken: '0x0000000000000000000000000000000000000000',
    },
  };
  if (network === 'avax') {
    // TODO: Other chains
  }
  // Deploy
  await deployProxy(ZorroControllerXChain, [zcxInitVal], {deployer});
};

// TODO: Don't forget to eventually assign timelockowner