const { testNets } = require("../chains");

// Tokens
const MockUSDC = artifacts.require("MockUSDC");
const MockBUSD = artifacts.require("MockBUSD");
// Price feeds
const MockPriceUSDC = artifacts.require("MockPriceUSDC");
const MockPriceBUSD = artifacts.require("MockPriceBUSD");
const MockPriceAggToken0 = artifacts.require('MockPriceAggToken0');
const MockPriceAggToken1 = artifacts.require('MockPriceAggToken1');
const MockPriceAggEarnToken = artifacts.require('MockPriceAggEarnToken');
const MockPriceAggLPOtherToken = artifacts.require('MockPriceAggLPOtherToken');
// Libs
const MockCustomMath = artifacts.require("MockCustomMath");
const MockPriceFeed = artifacts.require("MockPriceFeed");
const MockAggregatorV3 = artifacts.require("MockAggregatorV3");
const MockSafeSwapUni = artifacts.require("MockSafeSwapUni");
const MockAMMRouter02 = artifacts.require("MockAMMRouter02");

module.exports = async function (deployer, network, accounts) {
  /* Tests */
  
  // Allowed networks: Test/dev only
  if (testNets.includes(network)) {
    // Tokens
    await deployer.deploy(MockUSDC);
    await deployer.deploy(MockBUSD);

    // Price feeds
    await deployer.deploy(MockPriceUSDC);
    await deployer.deploy(MockPriceBUSD);
    await deployer.deploy(MockPriceAggToken0);
    await deployer.deploy(MockPriceAggToken1);
    await deployer.deploy(MockPriceAggEarnToken);
    await deployer.deploy(MockPriceAggLPOtherToken);

    // Libs
    await deployer.deploy(MockCustomMath);
    await deployer.deploy(MockPriceFeed);
    await deployer.deploy(MockAggregatorV3);
    await deployer.deploy(MockSafeSwapUni);
    await deployer.deploy(MockAMMRouter02);
  }
};