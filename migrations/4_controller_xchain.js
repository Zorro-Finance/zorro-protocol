// Upgrades
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
// Get key params
const {chains, zeroAddress, homeNetwork} = require('../helpers/constants');
const { 
  getSynthNetwork, isTestNetwork, 
} = require('../helpers/chains');

// Controller
const ZorroControllerXChain = artifacts.require("ZorroControllerXChain");
const MockZorroControllerXChain = artifacts.require("MockZorroControllerXChain");
const ZorroController = artifacts.require("ZorroController");
// Actions
const ZorroControllerXChainActions = artifacts.require("ZorroControllerXChainActions");
// Token
const Zorro = artifacts.require('Zorro');
// Price feeds
const ZORPriceFeed = artifacts.require('ZORPriceFeed');

module.exports = async function (deployer, network, accounts) {
  // Check network
  if (isTestNetwork(network)) {
    /* Testnet */

    // Get key vars
    const {
      infra,
      tokens,
      xChain,
    } = chains[network];
  
    // Deploy contracts
    const zcxActionsInitVal = [infra.stargateRouter, infra.layerZeroEndpoint, infra.uniRouterAddress];
    const zorroControllerXChainActions = await deployProxy(ZorroControllerXChainActions, [...zcxActionsInitVal], {deployer});
  
    // Prep init values
    const zcxInitVal = {
      defaultStablecoin: tokens.defaultStablecoin,
      ZORRO: zeroAddress,
      zorroLPPoolOtherToken: zeroAddress,
      zorroStakingVault: zeroAddress, // Must be set later
      uniRouterAddress: infra.uniRouterAddress,
      homeChainZorroController: zeroAddress,
      currentChainController: zeroAddress,
      publicPool: zeroAddress, // Must be set later
      controllerActions: zorroControllerXChainActions.address,
      bridge: {
        chainId: xChain.chainId,
        homeChainId: xChain.homeChainId,
        ZorroChainIDs: [xChain.chainId],
        controllerContracts: [zeroAddress],
        LZChainIDs: [xChain.lzChainId],
        stargateDestPoolIds: [xChain.sgPoolId],
        stargateRouter: infra.stargateRouter,
        layerZeroEndpoint: infra.layerZeroEndpoint,
        stargateSwapPoolId: xChain.sgPoolId,
      },
      swaps: {
        stablecoinToZorroPath: [],
        stablecoinToZorroLPPoolOtherTokenPath: [],
      },
      priceFeeds: {
        priceFeedZOR: zeroAddress,
        priceFeedLPPoolOtherToken: zeroAddress,
        priceFeedStablecoin: zeroAddress,
      },
    };
  
    // Deploy
    await deployProxy(MockZorroControllerXChain, [zcxInitVal], {deployer});
  } else {
    /* Production */

    // Unpack keyParams
    const {
      tokens,
      priceFeeds,
      infra,
      xChain,
    } = chains[getSynthNetwork(network)];
  
    // Deployed contracts
    const zorro = await Zorro.deployed();
    const zorroController = await ZorroController.deployed();
    const zorPriceFeed = await ZORPriceFeed.deployed();
  
    // Deploy contracts
    const zcxActionsInitVal = [infra.stargateRouter, infra.layerZeroEndpoint, infra.uniRouterAddress];
    const zorroControllerXChainActions = await deployProxy(ZorroControllerXChainActions, [...zcxActionsInitVal], {deployer});
  
    // Prep init values
    const zcxInitVal = {
      defaultStablecoin: tokens.defaultStablecoin,
      ZORRO: zorro.address,
      zorroLPPoolOtherToken: network === homeNetwork ? tokens.wbnb : zeroAddress,
      zorroStakingVault: zeroAddress, // Must be set later
      uniRouterAddress: infra.uniRouterAddress,
      homeChainZorroController: zorroController.address,
      currentChainController: zorroController.address,
      publicPool: zeroAddress, // Must be set later
      controllerActions: zorroControllerXChainActions.address,
      bridge: {
        chainId: xChain.chainId,
        homeChainId: xChain.homeChainId,
        ZorroChainIDs: [xChain.chainId],
        controllerContracts: [zorroController.address],
        LZChainIDs: [xChain.lzChainId],
        stargateDestPoolIds: [xChain.sgPoolId],
        stargateRouter: infra.stargateRouter,
        layerZeroEndpoint: infra.layerZeroEndpoint,
        stargateSwapPoolId: 0, // TODO: Change this to the real value. It's just a placeholder
      },
      swaps: {
        stablecoinToZorroPath: network === homeNetwork ? [tokens.busd, tokens.wbnb, zorro.address] : [],
        stablecoinToZorroLPPoolOtherTokenPath: network === homeNetwork ? [tokens.busd, tokens.wbnb] : [],
      },
      priceFeeds: {
        priceFeedZOR: network === homeNetwork ? zorPriceFeed.address: zeroAddress,
        priceFeedLPPoolOtherToken: network === homeNetwork ? priceFeeds.bnb : network === homeNetwork,
        priceFeedStablecoin: priceFeeds.defaultStablecoin,
      },
    };
  
    // Deploy
    const zorroControllerXChain = await deployProxy(ZorroControllerXChain, [zcxInitVal], {deployer});
  
    // Update ZorroController
    await zorroController.setZorroXChainEndpoint(zorroControllerXChain.address);
  }

};

// TODO: Don't forget to eventually assign timelockowner