// Upgrades
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
// Get key params
const {chains, zeroAddress} = require('../constants');
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

  // Existing contracts
  const zorro = await Zorro.deployed();
  const zorroController = await ZorroController.deployed();
  const zorPriceFeed = await ZORPriceFeed.deployed();

  // Unpack keyParams
  const {avax} = chains;
  const {
    tokens,
    infra,
    priceFeeds,
    xChain,
  } = avax;

  // Controller Actions deployment
  const zcxActionsInitVal = [infra.stargateRouter, infra.layerZeroEndpoint, infra.uniRouterAddress];
  await deployProxy(ZorroControllerXChainActions, [zcxActionsInitVal], {deployer});
  const zorroControllerXChainActions = await ZorroControllerXChainActions.deployed();

  
  // Prep init values
  let zcxInitVal = {
    // TODO: Fill out
    defaultStablecoin: tokens.usdc,
    ZORRO: zorro.address,
    zorroLPPoolOtherToken: tokens.wavax,
    zorroStakingVault: zeroAddress, // Will be reset in subsequent migration
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
      controllerContracts: [zorroController.address],
    },
    swaps: {
      stablecoinToZorroPath: [tokens.usdc, tokens.wavax, zorro.address],
      stablecoinToZorroLPPoolOtherTokenPath: [tokens.usdc, tokens.wavax],
    },
    priceFeeds: {
      priceFeedZOR: zorPriceFeed.address,
      priceFeedLPPoolOtherToken: priceFeeds.avax,
      priceFeedStablecoin: priceFeeds.usdc,
    },
  };

  // TODO: Do BNB deployment too
  // TODO: Once done, need to redo chain and controller contracts mapping

  // Deploy
  await deployProxy(ZorroControllerXChain, [zcxInitVal], {deployer});

  // Update ZorroController
  const zorroControllerXChain = await ZorroControllerXChain.deployed();
  await zorroController.setZorroXChainEndpoint(zorroControllerXChain.address);
};

// TODO: Don't forget to eventually assign timelockowner