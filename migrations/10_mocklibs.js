// Libs (only for testing)
const MockCustomMath = artifacts.require("MockCustomMath");
const MockPriceFeed = artifacts.require("MockPriceFeed");
const MockAggregatorV3 = artifacts.require("MockAggregatorV3");
const MockSafeSwapUni = artifacts.require("MockSafeSwapUni");
const MockAMMRouter02 = artifacts.require("MockAMMRouter02");
const MockSafeSwapBalancer = artifacts.require("MockSafeSwapBalancer");
const MockBalancerVault = artifacts.require("MockBalancerVault");

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
    await deployer.deploy(MockCustomMath);
    await deployer.deploy(MockPriceFeed);
    await deployer.deploy(MockAggregatorV3);
    await deployer.deploy(MockSafeSwapUni);
    await deployer.deploy(MockAMMRouter02);
    await deployer.deploy(MockSafeSwapBalancer);
    await deployer.deploy(MockBalancerVault);
  } else {
    console.log('On live network. Skipping deployment of libs');
  }
};