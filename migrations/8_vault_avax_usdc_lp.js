// Upgrades
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
// Get key params
const {
  getSynthNetwork,
  isTestNetwork,
} = require('../helpers/chains');
const { chains, zeroAddress, vaultFees } = require('../helpers/constants');

// Vaults
const TJ_AVAX_USDC = artifacts.require("TJ_AVAX_USDC");
// Actions
const VaultActionsStandardAMM = artifacts.require('VaultActionsStandardAMM');
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

  // Deployed contracts
  const zorroController = await ZorroController.deployed();
  const zorroControllerXChain = await ZorroControllerXChain.deployed();
  const zorro = await Zorro.deployed();
  const vaultTimelock = await VaultTimelock.deployed();
  const poolTreasury = await PoolTreasury.deployed();

  
  if (getSynthNetwork(network) === 'avax') {
    // Unpack keyParams
    const { avax } = chains;
    const {
      tokens,
      priceFeeds,
      infra,
      protocols,
    } = avax;

    // Deployed contracts

    // Deploy actions contract
    const vaultActionsStandardAMM = await deployProxy(VaultActionsStandardAMM, [infra.uniRouterAddress], { deployer });

    // Init values 
    const initVal = {
      baseInit: {
        config: {
          pid: protocols.traderjoe.pidAVAX_USDC,
          isHomeChain: false,
        },
        keyAddresses: {
          govAddress: vaultTimelock.address,
          zorroControllerAddress: zorroController.address,
          zorroXChainController: zorroControllerXChain.address,
          ZORROAddress: zorro.address,
          zorroStakingVault: zeroAddress,
          wantAddress: protocols.traderjoe.poolAVAX_USDC,
          token0Address: tokens.wavax,
          token1Address: tokens.usdc,
          earnedAddress: tokens.joe,
          farmContractAddress: protocols.traderjoe.masterChef,
          treasury: poolTreasury.address,
          poolAddress: protocols.traderjoe.poolAVAX_USDC,
          uniRouterAddress: infra.uniRouterAddress,
          zorroLPPool: zeroAddress,
          zorroLPPoolOtherToken: zeroAddress,
          defaultStablecoin: tokens.usdc,
          vaultActions: vaultActionsStandardAMM.address,
        },
        swapPaths: {
          earnedToZORROPath: [],
          earnedToToken0Path: [tokens.joe, tokens.wavax],
          earnedToToken1Path: [tokens.joe, tokens.wavax, tokens.usdc],
          stablecoinToToken0Path: [tokens.usdc, tokens.wavax],
          stablecoinToToken1Path: [],
          earnedToZORLPPoolOtherTokenPath: [],
          earnedToStablecoinPath: [tokens.joe, tokens.wavax, tokens.usdc],
          stablecoinToZORROPath: [],
          stablecoinToLPPoolOtherTokenPath: [],
        },
        fees: vaultFees,
        priceFeeds: {
          token0PriceFeed: priceFeeds.avax,
          token1PriceFeed: priceFeeds.usdc,
          earnTokenPriceFeed: priceFeeds.joe,
          ZORPriceFeed: zeroAddress,
          lpPoolOtherTokenPriceFeed: zeroAddress,
          stablecoinPriceFeed: priceFeeds.usdc,
        },
        dstGasForEarningsCall: 100000,
      },
      isLPFarmable: true,
    };

    // Deploy
    await deployProxy(TJ_AVAX_USDC,
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

// TODO: For all vaults!: call the addVault() func with appropriate multiplier