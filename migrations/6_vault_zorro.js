// Upgrades
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
// Get key params
const { 
  getSynthNetwork,
} = require('../helpers/chains');
const { chains, zeroAddress, homeNetwork, vaultFees } = require('../helpers/constants');

// Vaults
const VaultZorro = artifacts.require("VaultZorro");
// Actions
const VaultActionsZorro = artifacts.require('VaultActionsZorro');
// Other contracts
const PoolPublic = artifacts.require("PoolPublic");
const ZorroController = artifacts.require("ZorroController");
const ZorroControllerXChain = artifacts.require("ZorroControllerXChain");
const Zorro = artifacts.require("Zorro");
const VaultTimelock = artifacts.require('VaultTimelock');
const ControllerTimelock = artifacts.require('ControllerTimelock');
// Price feeds
const ZORPriceFeed = artifacts.require("ZORPriceFeed");

module.exports = async function (deployer, network, accounts) {
  /* Production */

  // Deployed contracts
  const zorroController = await ZorroController.deployed();
  const zorroControllerXChain = await ZorroControllerXChain.deployed();
  const poolPublic = await PoolPublic.deployed();
  const zorro = await Zorro.deployed();
  const vaultTimelock = await VaultTimelock.deployed();
  const controllerTimelock = await ControllerTimelock.deployed();

  // Unpack keyParams
  const {bnb} = chains;
  const {
    tokens,
    priceFeeds,
    infra,
  } = bnb;
  
  if (getSynthNetwork(network) === homeNetwork) {
    /* Home chain */

    // Deployed contracts
    const zorPriceFeed = await ZORPriceFeed.deployed();

    // Deploy actions contract
    await deployProxy(VaultActionsZorro, [infra.uniRouterAddress], {deployer});
    const vaultActionsZorro = await VaultActionsZorro.deployed();


    // Init values 
    const initVal = {
      baseInit: {
        config: {
          pid: 0,
          isHomeChain: true,
        },
        keyAddresses: {
          govAddress: vaultTimelock.address,
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
          defaultStablecoin: tokens.busd,
          vaultActions: vaultActionsZorro.address,
        },
        swapPaths: {
          earnedToZORROPath: [],
          earnedToToken0Path: [],
          earnedToToken1Path: [],
          stablecoinToToken0Path: [tokens.busd, tokens.wbnb, zorro.address],
          stablecoinToToken1Path: [],
          earnedToZORLPPoolOtherTokenPath: [],
          earnedToStablecoinPath: [],
          stablecoinToZORROPath: [tokens.busd, tokens.wbnb, zorro.address],
          stablecoinToLPPoolOtherTokenPath: [tokens.busd, tokens.wbnb],
        },
        fees: vaultFees,
        priceFeeds: {
          token0PriceFeed: zorPriceFeed.address,
          token1PriceFeed: zeroAddress,
          earnTokenPriceFeed: zeroAddress,
          ZORPriceFeed: zorPriceFeed.address,
          lpPoolOtherTokenPriceFeed: priceFeeds.bnb,
          stablecoinPriceFeed: priceFeeds.busd,
        },
      },
    };
    
    // Deploy
    const vaultZorro = await deployProxy(VaultZorro,
      [
        vaultTimelock.address,
        initVal,
      ],
      {
        deployer,
      }
    );

    // Update ZorroController
    await zorroController.setZorroContracts(poolPublic.address, vaultZorro.address);

    // Controller transfer ownership to controller timelock
    await zorroController.transferOwnership(controllerTimelock.address);
  } else {
    console.log('Not home chain. Skipping Zorro Single Staking Vault creation');
  }
};