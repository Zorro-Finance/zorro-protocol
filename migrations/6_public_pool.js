// Upgrades
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
// Chain params
const {homeNetworks} = require('../chains');
// Migration
const Migrations = artifacts.require("Migrations");

// Finance
const PoolPublic = artifacts.require("PoolPublic");
// Controller
const ZorroController = artifacts.require("ZorroController");
// Token
const Zorro = artifacts.require("Zorro");


module.exports = async function (deployer, network, accounts) {
  // Web3
  const adapter = Migrations.interfaceAdapter;
  const { web3 } = adapter;
  
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

  // For dev net, mint some ZOR to the public pool
  if (network === 'avaxfork') {
    // Get existing contracts
    const zorro = await Zorro.deployed();
    const zorroController = await ZorroController.deployed();
    const publicPool = await PoolPublic.deployed();

    // Pass control to this account
    await zorro.setZorroController(accounts[0]);
    // Mint ZOR
    const amt = web3.utils.toWei('100000', 'ether');
    await zorro.mint(publicPool.address, amt);
    // Pass control back
    await zorro.setZorroController(zorroController.address);
  }
};