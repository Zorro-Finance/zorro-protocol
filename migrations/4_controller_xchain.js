// Upgrades
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
// Get key params
const {chains, zeroAddress} = require('../helpers/constants');
const { 
  getSynthNetwork, 
} = require('../helpers/chains');

// Controller
const ZorroControllerXChain = artifacts.require("ZorroControllerXChain");
const ZorroController = artifacts.require("ZorroController");
// Actions
const ZorroControllerXChainActions = artifacts.require("ZorroControllerXChainActions");
// Token
const Zorro = artifacts.require('Zorro');
// Price feeds
const ZORPriceFeed = artifacts.require('ZORPriceFeed');

module.exports = async function (deployer, network, accounts) {
  /* Production */

  // Deployed contracts (common)
  const zorro = await Zorro.deployed();

  /* BNB Chain */

  if (getSynthNetwork(network) === 'bnb') {
    // Unpack keyParams
    const { bnb } = chains;
    const {
      tokens,
      priceFeeds,
      infra,
      xChain,
    } = bnb;

    // Deployed contracts
    const zorro = await Zorro.deployed();
    const zorroController = await ZorroController.deployed();
    const zorPriceFeed = await ZORPriceFeed.deployed();

    // Deploy contracts
    const zcxActionsInitVal = [infra.stargateRouter, infra.layerZeroEndpoint, infra.uniRouterAddress];
    await deployProxy(ZorroControllerXChainActions, [...zcxActionsInitVal], {deployer});
    const zorroControllerXChainActions = await ZorroControllerXChainActions.deployed();

    // Prep init values
    let zcxInitVal = {
      defaultStablecoin: tokens.busd,
      ZORRO: zorro.address,
      zorroLPPoolOtherToken: tokens.wbnb,
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
        stablecoinToZorroPath: [tokens.busd, tokens.wbnb, zorro.address],
        stablecoinToZorroLPPoolOtherTokenPath: [tokens.busd, tokens.wbnb],
      },
      priceFeeds: {
        priceFeedZOR: zorPriceFeed.address,
        priceFeedLPPoolOtherToken: priceFeeds.bnb,
        priceFeedStablecoin: priceFeeds.busd,
      },
    };

    // Deploy
    await deployProxy(ZorroControllerXChain, [zcxInitVal], {deployer});

    // Update ZorroController
    const zorroControllerXChain = await ZorroControllerXChain.deployed();
    await zorroController.setZorroXChainEndpoint(zorroControllerXChain.address);
  }

  /* AVAX Chain */

  if (getSynthNetwork(network) === 'avax') {
    // Unpack keyParams
    const { avax } = chains;
    const {
      tokens,
      priceFeeds,
      infra,
      xChain,
    } = avax;

    // Deployed contracts
    const zorroController = await ZorroController.deployed();

     // Deploy contracts
     const zcxActionsInitVal = [infra.stargateRouter, infra.layerZeroEndpoint, infra.uniRouterAddress];
     const zorroControllerXChainActions = await deployProxy(ZorroControllerXChainActions, [...zcxActionsInitVal], {deployer});

    // Prep init values
    let zcxInitVal = {
      defaultStablecoin: tokens.usdc,
      ZORRO: zorro.address,
      zorroLPPoolOtherToken: zeroAddress,
      zorroStakingVault: zeroAddress,
      uniRouterAddress: infra.uniRouterAddress,
      homeChainZorroController: zeroAddress,
      currentChainController: zorroController.address,
      publicPool: zeroAddress,
      controllerActions: zorroControllerXChainActions.address,
      bridge: {
        chainId: xChain.chainId,
        homeChainId: xChain.homeChainId,
        ZorroChainIDs: [xChain.chainId],
        controllerContracts: [zorroController.address],
        LZChainIDs: [xChain.lzChainId],
        stargateDestPoolIds: [xChain.sgPoolId],
        stargateRouter: infra.stargateRouter,
        controllerContracts: [zorroController.address],
        layerZeroEndpoint: infra.layerZeroEndpoint,
        stargateSwapPoolId: 0, // TODO: Change this to the real value. It's just a placeholder
      },
      swaps: {
        stablecoinToZorroPath: [],
        stablecoinToZorroLPPoolOtherTokenPath: [],
      },
      priceFeeds: {
        priceFeedZOR: zeroAddress,
        priceFeedLPPoolOtherToken: zeroAddress,
        priceFeedStablecoin: priceFeeds.usdc,
      },
    };

    // Deploy
    await deployProxy(ZorroControllerXChain, [zcxInitVal], {deployer});

    // Update ZorroController
    const zorroControllerXChain = await ZorroControllerXChain.deployed();
    await zorroController.setZorroXChainEndpoint(zorroControllerXChain.address);
  }
};

// TODO: Don't forget to eventually assign timelockowner