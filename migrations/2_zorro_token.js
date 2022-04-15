// Token
const ZorroToken = artifacts.require("Zorro");

module.exports = async function (deployer, network, accounts) {
  // Deploy
  await deployer.deploy(ZorroToken);
};