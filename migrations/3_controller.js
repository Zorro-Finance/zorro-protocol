// Upgrades
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
// Controller
const ZorroController = artifacts.require("ZorroController");
const ZorroControllerXChain = artifacts.require("ZorroControllerXChain");
// Libs
// const CustomMath = artifacts.require("CustomMath");
// const PriceFeed = artifacts.require("PriceFeed");
// const SafeSwapUni = artifacts.require("SafeSwapUni");

module.exports = async function (deployer, network, accounts) {
  // Libs
  // await deployer.deploy(CustomMath);
  // await deployer.deploy(PriceFeed);
  // await deployer.deploy(SafeSwapUni);
  
  // Links
  // await deployer.link(CustomMath, ZorroController);
  // await deployer.link(PriceFeed, ZorroController);
  // await deployer.link(SafeSwapUni, ZorroController);

  // Existing contracts
  const publicPool = await deployer.deployed
  
  // Deploy
  const zcInitVal = {
    ZORRO: '0x0000000000000000000000000000000000000000',
    defaultStablecoin: '',
    zorroLPPoolOtherToken: '',
    publicPool: '',
    zorroStakingVault: '',
    zorroLPPool: '',
    uniRouterAddress: '',
    USDCToZorroPath: [

    ],
    USDCToZorroLPPoolOtherTokenPath: [],
    rewards: {

    },
    xChain: {

    },
    priceFeeds: {

    },
  };
  await deployProxy(ZorroController, [zcInitVal], {deployer});
};

// TODO: Deploy also XChain