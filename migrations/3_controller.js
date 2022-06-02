// Upgrades
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
// Controller
const ZorroController = artifacts.require("ZorroController");
// Token
const Zorro = artifacts.require('Zorro');

module.exports = async function (deployer, network, accounts) {
  // Existing contracts
  const ZorroToken = await Zorro.deployed();
  
  // Prep init values
  let zcInitVal = {
    ZORRO: ZorroToken.address,
    defaultStablecoin: '0x0000000000000000000000000000000000000000',
    zorroLPPoolOtherToken: '0x0000000000000000000000000000000000000000',
    publicPool: '0x0000000000000000000000000000000000000000',
    zorroStakingVault: '0x0000000000000000000000000000000000000000',
    zorroLPPool: '0x0000000000000000000000000000000000000000',
    uniRouterAddress: '0x0000000000000000000000000000000000000000',
    USDCToZorroPath: [],
    USDCToZorroLPPoolOtherTokenPath: [],
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
      homeChainZorroController: '0x0000000000000000000000000000000000000000',
      zorroControllerOracle: '0x0000000000000000000000000000000000000000',
      zorroXChainEndpoint: '0x0000000000000000000000000000000000000000',
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
  await deployProxy(ZorroController, [zcInitVal], {deployer});
};