// Upgrades
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
// Finance
const PoolPublic = artifacts.require("PoolPublic");
// Controller
const ZorroController = artifacts.require("ZorroController");
// Token
const Zorro = artifacts.require("Zorro");
// Chain params
const {homeNetworks} = require('../chains');


module.exports = async function (deployer, network, accounts) {
  // Allowed networks
  if (homeNetworks.includes(network)) {
    // Get existing contracts
    const zorroToken = await Zorro.deployed();
    const zorroController = await ZorroController.deployed();

    // Deploy
    await deployProxy(PoolPublic, [
      zorroToken.address,
      zorroController.address,
    ], {deployer});
  } else {
    console.log('Not home chain. Skipping public pool creation');
  }
};