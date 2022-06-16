// Upgrades
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
// Controller
const ZorroController = artifacts.require("ZorroController");
// Token
const Zorro = artifacts.require('Zorro');
// Get key params
const {getKeyParams, getSynthNetwork, homeNetworks} = require('../chains');
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
  
  // Prep init values
  let zcInitVal = {
    ZORRO: zorro.address,
    defaultStablecoin,
    zorroLPPoolOtherToken,
    publicPool: zeroAdress, // will be filled in subsequent migration
    zorroStakingVault: zeroAdress, // ditto
    zorroLPPool,
    uniRouterAddress,
    USDCToZorroPath,
    USDCToZorroLPPoolOtherTokenPath,
    rewards,
    xChain,
    priceFeeds,
  };
  // Deploy
  await deployProxy(ZorroController, [zcInitVal], {deployer});
  // Update XChain props to correct home chain Zorro controller if on the home chain
  if (homeNetworks.includes(network)) {
    const zorroController = await ZorroController.deployed();
    await zorroController.setXChainParams(xChain.chainId, xChain.homeChainId, zorroController.address);
  }
};