// Finance
const PoolPublic = artifacts.require("PoolPublic");


module.exports = async function (deployer, network, accounts) {
  await deployer.deploy(PoolPublic);
};