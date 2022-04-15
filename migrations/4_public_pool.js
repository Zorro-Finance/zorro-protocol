// Upgrades
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
// Finance
const PoolPublic = artifacts.require("PoolPublic");


module.exports = async function (deployer, network, accounts) {
  await deployProxy(PoolPublic, [], {deployer});
};