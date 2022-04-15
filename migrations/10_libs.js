// Libs
const CustomMath = artifacts.require("CustomMath");
const PriceFeed = artifacts.require("PriceFeed");
const SafeSwapUni = artifacts.require("SafeSwapUni");
const SafeSwapBalancer = artifacts.require("SafeSwapBalancer");

module.exports = async function (deployer, network, accounts) {
  // Allowed networks: Test/dev only
  const allowedNetworks = [
    'ganache',
    'ganachecli',
    'default',
    'development',
    'test',
  ];
  if (allowedNetworks.includes(network)) {
    // Deploy
    await deployer.deploy(CustomMath);
    await deployer.deploy(PriceFeed);
    await deployer.deploy(SafeSwapUni);
    await deployer.deploy(SafeSwapBalancer);
  } else {
    console.log('Not home chain. Skipping deployment of libs');
  }
};