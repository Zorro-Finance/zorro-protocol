// Upgrades
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
// Controller
const ZorroController = artifacts.require("ZorroController");
// Token
const Zorro = artifacts.require('Zorro');
// Other contracts
const MockPriceAggZOR = artifacts.require("MockPriceAggZOR");
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

  let mockPriceAggZOR;
  
  if (devNets.includes(network)) {
    // Deploy Mock ZOR price feed if necessary
    if (!MockPriceAggZOR.hasNetwork(network)) {
      await deployer.deploy(MockPriceAggZOR);
      mockPriceAggZOR = await MockPriceAggZOR.deployed();
    }
  }

  let zcInitVal;

  if (['avax', 'ganachecloud'].includes(network)) {
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
          priceFeedZOR: devNets.includes(network) ? mockPriceAggZOR.address : priceFeeds.priceFeedZOR,
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
};