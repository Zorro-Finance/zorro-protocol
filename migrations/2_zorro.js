// Tokens
const Zorro = artifacts.require("Zorro");
// Finance
const PoolPublic = artifacts.require("PoolPublic");
// Controller
const ZorroController = artifacts.require("ZorroController");
const CustomMath = artifacts.require("CustomMath");
const PriceFeed = artifacts.require("PriceFeed");
const SafeSwapUni = artifacts.require("SafeSwapUni");


module.exports = async function (deployer, network, accounts) {
  await deployer.deploy(Zorro, accounts[0]);
  await deployer.deploy(PoolPublic);
  // Libs
  await deployer.deploy(CustomMath);
  await deployer.deploy(PriceFeed);
  await deployer.deploy(SafeSwapUni);
  
  // Links
  await deployer.link(CustomMath, ZorroController);
  await deployer.link(PriceFeed, ZorroController);
  await deployer.link(SafeSwapUni, ZorroController);
  
  // Deploy
  await deployer.deploy(ZorroController);
};