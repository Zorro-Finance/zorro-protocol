// TODO: Needs to be filled out for BenqiLending

// Upgrades
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
// Get key params
const {
  getSynthNetwork,
} = require('../chains');
const { chains, zeroAddress } = require('../helpers/constants');

// Vaults
const VaultBenqiLendingAVAX = artifacts.require("VaultBenqiLendingAVAX");
// Actions
const VaultActionsBenqiLending = artifacts.require('VaultActionsBenqiLending');
// Other contracts
const ZorroController = artifacts.require("ZorroController");
const ZorroControllerXChain = artifacts.require("ZorroControllerXChain");
const Zorro = artifacts.require("Zorro");

module.exports = async function (deployer, network, accounts) {
  /* Production */

  // Deployed contracts
  const zorroController = await ZorroController.deployed();
  const zorroControllerXChain = await ZorroControllerXChain.deployed();
  const zorro = await Zorro.deployed();

  // Unpack keyParams
  const { avax, vaultFees } = chains;
  const {
    tokens,
    priceFeeds,
    infra,
  } = avax;

  if (getSynthNetwork(network) === 'avax') {
    /* Home chain */

    // Deployed contracts
    const zorPriceFeed = await ZORPriceFeed.deployed();

    // Deploy actions contract
    await deployProxy(VaultActionsAlpaca, [infra.uniRouterAddress], { deployer });
    const vaultActionsAlpaca = await VaultActionsAlpaca.deployed();


    // Init values 
    const initVal = {
      // TODO: This needs to be filled out
      pid: 0,
      keyAddresses: {
        govAddress: accounts[0], // TODO: Should this be accounts[0]?
        zorroControllerAddress: zorroController.address,
        zorroXChainController: zorroControllerXChain.address,
        ZORROAddress: zorro.address,
        zorroStakingVault: zeroAddress,
        wantAddress: zorro.address,
        token0Address: zorro.address,
        token1Address: zeroAddress,
        earnedAddress: zeroAddress,
        farmContractAddress: zeroAddress,
        treasury: zeroAddress,
        poolAddress: zeroAddress,
        uniRouterAddress: infra.uniRouterAddress,
        zorroLPPool: zeroAddress,
        zorroLPPoolOtherToken: zeroAddress,
        defaultStablecoin: tokens.usdc,
        vaultActions: vaultActionsAlpaca.address,
      },
      swapPaths: {
        earnedToZORROPath: [],
        earnedToToken0Path: [],
        earnedToToken1Path: [],
        stablecoinToToken0Path: [tokens.usdc, tokens.wavax, zorro.address],
        stablecoinToToken1Path: [],
        earnedToZORLPPoolOtherTokenPath: [],
        earnedToStablecoinPath: [],
        stablecoinToZORROPath: [tokens.usdc, tokens.wavax, zorro.address],
        stablecoinToLPPoolOtherTokenPath: [tokens.usdc, tokens.wavax],
      },
      fees: vaultFees,
      priceFeeds: {
        token0PriceFeed: zorPriceFeed.address,
        token1PriceFeed: zeroAddress,
        earnTokenPriceFeed: zeroAddress,
        ZORPriceFeed: zorPriceFeed.address,
        lpPoolOtherTokenPriceFeed: priceFeeds.avax,
        stablecoinPriceFeed: priceFeeds.usdc,
      },
      targetBorrowLimit: 0, 
      targetBorrowLimitHysteresis: 0,
      comptrollerAddress: zeroAddress,
      lendingToken: zeroAddress,
    };

    // Deploy
    await deployProxy(VaultAlpacaLeveragedBTCB,
      [
        accounts[0],
        initVal,
      ],
      {
        deployer,
      }
    );
  } else {
    console.log('Not BNB chain. Skipping vault creation');
  }
};