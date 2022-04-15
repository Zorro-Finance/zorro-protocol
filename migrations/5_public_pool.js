// Upgrades
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
// Finance
const PoolPublic = artifacts.require("PoolPublic");
// Controller
const ZorroController = artifacts.require("ZorroController");
// Token
const Zorro = artifacts.require("Zorro");


module.exports = async function (deployer, network, accounts) {
  // Allowed networks
  const allowedNetworks = [
    'avalanche',
    'ganache',
    'ganachecli',
    'default',
    'development',
  ];
  if (allowedNetworks.includes(network)) {
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