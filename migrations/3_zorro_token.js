const { testNets } = require("../chains");

// Token
const ZorroToken = artifacts.require("Zorro");
// Mocks
const MockZorroToken = artifacts.require("MockZorroToken");
// Price feeds
const MockPriceAggZOR = artifacts.require('MockPriceAggZOR');

module.exports = async function (deployer, network, accounts) {
  /* Production */

  // Deploy
  // NOTE: Deployed on every chain, but values are meant to sync to the "home chain Zorro" token
  await deployer.deploy(ZorroToken);

  /* Tests */
  // Allowed networks: Test/dev only
  if (testNets.includes(network)) {
    // Zorro Token
    await deployer.deploy(MockZorroToken);

    // Price Feeds
    await deployer.deploy(MockPriceAggZOR);
  }
};