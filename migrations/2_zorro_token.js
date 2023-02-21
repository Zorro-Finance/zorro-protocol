const { chains } = require("../helpers/constants");
const { isDevNetwork, isTestNetwork, getSynthNetwork } = require("../helpers/chains");

// Token
const Zorro = artifacts.require("Zorro");

// Price feeds
const ZORPriceFeed = artifacts.require('ZORPriceFeed');

module.exports = async function (deployer, network, accounts) {
  if (!isTestNetwork(network)) {
    /* Production */

    // Common vars
    let uniRouterAddress, stablecoin, lpOtherToken;

    if (getSynthNetwork(network) === 'bnb') {
      const { bnb } = chains;
      const { tokens, infra } = bnb;
      uniRouterAddress = infra.uniRouterAddress;
      stablecoin = tokens.busd;
      lpOtherToken = tokens.wbnb;
    } else if (getSynthNetwork(network) === 'avax') {
      const { avax } = chains;
      const { tokens, infra } = avax;
      uniRouterAddress = infra.uniRouterAddress;
      stablecoin = tokens.usdc;
      lpOtherToken = tokens.wavax;
    } else {
      console.log('Unidentified network. Skipping...');
      return;
    }

    // Deploy
    // Zorro token. NOTE: Deployed on every chain, but values are meant to sync to the "home chain Zorro" token
    await deployer.deploy(Zorro);
    const zorro = await Zorro.deployed();
  
    // Zorro price feed
    await deployer.deploy(
      ZORPriceFeed, 
      uniRouterAddress, 
      zorro.address, 
      lpOtherToken, 
      stablecoin
    );
  } else {
    console.log('Testnet identified. Skipping...');
  }
};