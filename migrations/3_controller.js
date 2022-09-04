// Upgrades
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
// Controller
const ZorroController = artifacts.require("ZorroController");
// Token
const Zorro = artifacts.require('Zorro');
// Other contracts
const MockPriceAggZORLP = artifacts.require("MockPriceAggZORLP");
// Get key params
const {getKeyParams, getSynthNetwork, homeNetworks, devNets} = require('../chains');
const zeroAdress = '0x0000000000000000000000000000000000000000';

module.exports = async function (deployer, network, accounts) {
  // Existing contracts
  const zorro = await Zorro.deployed();

  // Unpack keyParams
  const {
    defaultStablecoin,
    uniRouterAddress,
    zorroLPPoolOtherToken,
    USDCToZorroPath,
    USDCToZorroLPPoolOtherTokenPath,
    rewards,
    xChain,
    priceFeeds,
    zorroLPPool,
  } = getKeyParams(accounts, zorro.address)[getSynthNetwork(network)];

  let mockPriceAggZORLP;
  
  if (devNets.includes(network)) {
    // Deploy Mock ZOR price feed if necessary
    if (!MockPriceAggZORLP.hasNetwork(network)) {
      await deployer.deploy(MockPriceAggZORLP, uniRouterAddress, zorro.address, zorroLPPoolOtherToken, defaultStablecoin);
    }
    mockPriceAggZORLP = await MockPriceAggZORLP.deployed();
  }

  let zcInitVal;

  if (['avax', 'avaxfork'].includes(network)) {
    // Prep init values
    const wavax = '0xb31f66aa3c1e785363f0875a1b74e27b85fd66c7';
    zcInitVal = {
      ZORRO: zorro.address,
      defaultStablecoin,
      zorroLPPoolOtherToken,
      publicPool: zeroAdress, // will be filled in subsequent migration
      zorroStakingVault: zeroAdress, // ditto
      zorroLPPool,
      uniRouterAddress,
      USDCToZorroPath: [defaultStablecoin, wavax, zorro.address],
      USDCToZorroLPPoolOtherTokenPath,
      rewards,
      xChain,
      priceFeeds: {
        ...priceFeeds,
        ...{
          priceFeedZOR: devNets.includes(network) ? mockPriceAggZORLP.address : priceFeeds.priceFeedZOR,
        },
      },
    };
    console.log('zc: ', 'devNets.includes(network): ', devNets.includes(network), 'priceFeeds.priceFeedZOR: ', priceFeeds.priceFeedZOR, 'zcInitVal: ', zcInitVal);
  } else {
    zcInitVal = {
      ZORRO: zorro.address,
      defaultStablecoin,
      zorroLPPoolOtherToken,
      publicPool: zeroAdress,
      zorroStakingVault: zeroAdress,
      zorroLPPool,
      uniRouterAddress,
      USDCToZorroPath,
      USDCToZorroLPPoolOtherTokenPath,
      rewards,
      xChain,
      priceFeeds,
    };
  }

  // Deploy
  await deployProxy(ZorroController, [zcInitVal], {deployer});
  // Update XChain props to correct home chain Zorro controller if on the home chain
  if (homeNetworks.includes(network)) {
    const zorroController = await ZorroController.deployed();
    await zorroController.setXChainParams(xChain.chainId, xChain.homeChainId, zorroController.address);
  }
};