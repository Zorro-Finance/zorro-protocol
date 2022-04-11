// Controller
const ZorroControllerXChain = artifacts.require("ZorroControllerXChain");
// Libs
const PriceFeed = artifacts.require("PriceFeed");
const SafeSwapUni = artifacts.require("SafeSwapUni");

module.exports = async function (deployer, network, accounts) {
  // Libs
  await deployer.deploy(PriceFeed);
  await deployer.deploy(SafeSwapUni);
  
  // Links
  await deployer.link(PriceFeed, ZorroControllerXChain);
  await deployer.link(SafeSwapUni, ZorroControllerXChain);
  
  // Deploy
  await deployer.deploy(ZorroControllerXChain);
};