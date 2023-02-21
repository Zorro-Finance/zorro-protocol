// Upgrades
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
// Get key params
const {
  getSynthNetwork,
  isTestNetwork,
} = require('../helpers/chains');
const { chains, zeroAddress, vaultFees } = require('../helpers/constants');
// Migration
const Migrations = artifacts.require("Migrations");

// Vaults
const VaultBenqiLendingAVAX = artifacts.require("VaultBenqiLendingAVAX");
// Actions
const VaultActionsBenqiLending = artifacts.require('VaultActionsBenqiLending');
// Other contracts
const ZorroController = artifacts.require("ZorroController");
const ZorroControllerXChain = artifacts.require("ZorroControllerXChain");
const Zorro = artifacts.require("Zorro");
const VaultTimelock = artifacts.require('VaultTimelock');
const PoolTreasury = artifacts.require('PoolTreasury');

module.exports = async function (deployer, network, accounts) {
  // Chain check 
  if (isTestNetwork(network)) {
    console.log('On Testnet. Skipping...');
    return;
  }

  // Web3
  const adapter = Migrations.interfaceAdapter;
  const { web3 } = adapter;

  // Deployed contracts
  const zorroController = await ZorroController.deployed();
  const zorroControllerXChain = await ZorroControllerXChain.deployed();
  const zorro = await Zorro.deployed();

  // Unpack keyParams
  const { avax } = chains;
  const {
    tokens,
    priceFeeds,
    infra,
    protocols,
  } = avax;

  const {benqi} = protocols;

  if (getSynthNetwork(network) === 'avax') {
    // Deployed contracts
    const vaultTimelock = await VaultTimelock.deployed();
    const poolTreasury = await PoolTreasury.deployed();

    // Deploy actions contract
    const vaultActionsBenqiLending = await deployProxy(VaultActionsBenqiLending, [infra.uniRouterAddress], { deployer });

    // Init values 
    const initVal = {
      baseInit: {
        config: {
          pid: 0,
          isHomeChain: false,
        },
        keyAddresses: {
          govAddress: vaultTimelock.address,
          zorroControllerAddress: zorroController.address,
          zorroXChainController: zorroControllerXChain.address,
          ZORROAddress: zorro.address,
          zorroStakingVault: zeroAddress,
          wantAddress: tokens.wavax,
          token0Address: tokens.wavax,
          token1Address: zeroAddress,
          earnedAddress: tokens.qi,
          farmContractAddress: benqi.tokenSaleDistributor,
          treasury: poolTreasury.address,
          poolAddress: benqi.avaxLendingPool,
          uniRouterAddress: infra.uniRouterAddress,
          zorroLPPool: zeroAddress,
          zorroLPPoolOtherToken: zeroAddress,
          defaultStablecoin: tokens.usdc,
          vaultActions: vaultActionsBenqiLending.address,
        },
        swapPaths: {
          earnedToZORROPath: [],
          earnedToToken0Path: [tokens.qi, tokens.wavax],
          earnedToToken1Path: [],
          stablecoinToToken0Path: [tokens.usdc, tokens.wavax],
          stablecoinToToken1Path: [],
          earnedToZORLPPoolOtherTokenPath: [],
          earnedToStablecoinPath: [tokens.qi, tokens.wavax, tokens.usdc],
          stablecoinToZORROPath: [],
          stablecoinToLPPoolOtherTokenPath: [],
        },
        fees: vaultFees,
        priceFeeds: {
          token0PriceFeed: priceFeeds.avax,
          token1PriceFeed: zeroAddress,
          earnTokenPriceFeed: priceFeeds.qi,
          ZORPriceFeed: zeroAddress,
          lpPoolOtherTokenPriceFeed: zeroAddress,
          stablecoinPriceFeed: priceFeeds.usdc,
        },
      },
      targetBorrowLimit: web3.utils.toWei('740', 'milli'), // 1% = 1e16
      targetBorrowLimitHysteresis: web3.utils.toWei('10', 'milli'), // 1% = 1e16
      comptrollerAddress: benqi.comptroller,
      lendingToken: benqi.avaxLendingPool,
    };

    // Deploy
    await deployProxy(VaultBenqiLendingAVAX,
      [
        vaultTimelock.address,
        initVal,
      ],
      {
        deployer,
      }
    );
  } else {
    console.log('Not AVAX chain. Skipping vault creation');
  }
};