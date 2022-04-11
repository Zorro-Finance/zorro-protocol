// Token
const ZorroToken = artifacts.require("Zorro");
// Controller
const ZorroController = artifacts.require("ZorroController");

module.exports = async function (deployer, network, accounts) {
  // Get deployed contract
  const zcInstance = await ZorroController.deployed();

  // Deploy
  await deployer.deploy(ZorroToken, zcInstance.address);
};