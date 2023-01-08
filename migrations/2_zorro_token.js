const { chains } = require("../helpers/constants");

// Token
const Zorro = artifacts.require("Zorro");

// Price feeds
const ZORPriceFeed = artifacts.require('ZORPriceFeed');

module.exports = async function (deployer, network, accounts) {
  /* Production */

  // Constants
  const { avax } = chains;
  const { tokens, infra } = avax;

  // Deploy
  // NOTE: Deployed on every chain, but values are meant to sync to the "home chain Zorro" token
  await deployer.deploy(Zorro);
  const zorro = await Zorro.deployed();

  await deployer.deploy(
    ZORPriceFeed, 
    infra.uniRouterAddress, 
    zorro.address, 
    tokens.wavax, 
    tokens.usdc
  );
};