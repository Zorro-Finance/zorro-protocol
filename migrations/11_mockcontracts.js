// Upgrades
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
const { deploy } = require('@openzeppelin/truffle-upgrades/dist/utils');
const VaultLibrary = artifacts.require('VaultLibrary');
// TODO: Replace with Alpaca
const VaultLibraryAlpaca = artifacts.require('VaultLibraryAlpaca');
const VaultLibraryStandardAMM = artifacts.require('VaultLibraryStandardAMM');
// Controllers (only for testing)
const MockZorroController = artifacts.require("MockZorroController");
const MockZorroControllerXChain = artifacts.require("MockZorroControllerXChain");
// Token (only for testing)
const MockZorroToken = artifacts.require("MockZorroToken");
const MockUSDC = artifacts.require("MockUSDC");
const MockBUSD = artifacts.require("MockBUSD");
const MockAlpaca = artifacts.require("MockAlpaca");
const MockAMMToken0 = artifacts.require("MockAMMToken0");
const MockAMMToken1 = artifacts.require("MockAMMToken1");
const MockAMMOtherLPToken = artifacts.require("MockAMMOtherLPToken");
// Vaults (only for testing)
const MockVaultAlpaca = artifacts.require("MockVaultAlpaca");
const MockVaultStandardAMM = artifacts.require("MockVaultStandardAMM");
const MockVaultStargate = artifacts.require("MockVaultStargate");
const MockVaultZorro = artifacts.require("MockVaultZorro");
const MockInvestmentVault = artifacts.require("MockInvestmentVault");
const MockInvestmentVault1 = artifacts.require("MockInvestmentVault1");
// Price feeds
const MockPriceAggToken0 = artifacts.require('MockPriceAggToken0');
const MockPriceAggToken1 = artifacts.require('MockPriceAggToken1');
const MockPriceAggEarnToken = artifacts.require('MockPriceAggEarnToken');
const MockPriceAggZOR = artifacts.require('MockPriceAggZOR');
const MockPriceAggLPOtherToken = artifacts.require('MockPriceAggLPOtherToken');
const MockPriceUSDC = artifacts.require("MockPriceUSDC");
const MockPriceBUSD = artifacts.require("MockPriceBUSD");
// Other contracts
// AMM
const MockAMMFarm = artifacts.require('MockAMMFarm');
const MockLPPool = artifacts.require('MockLPPool');
const MockLPPool1 = artifacts.require('MockLPPool1');
// Alpaca
const MockAlpacaFarm = artifacts.require('MockAlpacaFarm');
const MockAlpacaVault = artifacts.require('MockAlpacaVault');
// Stargate
const MockStargateRouter = artifacts.require('MockStargateRouter');
const MockStargatePool = artifacts.require('MockStargatePool');
const MockStargateLPStaking = artifacts.require('MockStargateLPStaking');
const MockSTGToken = artifacts.require('MockSTGToken');
// LayerZero
const MockLayerZeroEndpoint = artifacts.require('MockLayerZeroEndpoint');

// Other vars
const zeroAddress = '0x0000000000000000000000000000000000000000';

module.exports = async function (deployer, network, accounts) {
  // Allowed networks: Test/dev only
  const allowedNetworks = [
    'ganache',
    'ganachecli',
    'default',
    'development',
    'test',
  ];
  if (allowedNetworks.includes(network)) {
    // Zorro Token
    await deployer.deploy(MockZorroToken);

    // Zorro Controller
    const zcInitVal = {
      ZORRO: MockZorroToken.address,
      defaultStablecoin: zeroAddress,
      zorroLPPoolOtherToken: zeroAddress,
      publicPool: zeroAddress,
      zorroStakingVault: zeroAddress,
      zorroLPPool: zeroAddress,
      uniRouterAddress: zeroAddress,
      stablecoinToZorroPath: [],
      stablecoinToZorroLPPoolOtherTokenPath: [],
      rewards: {
        blocksPerDay: 0,
        startBlock: 0,
        ZORROPerBlock: 0,
        targetTVLCaptureBasisPoints: 0,
        chainMultiplier: 0,
        baseRewardRateBasisPoints: 0,
      },
      xChain: {
        chainId: 0,
        homeChainId: 0,
        homeChainZorroController: zeroAddress,
        zorroControllerOracle: zeroAddress,
        zorroXChainEndpoint: zeroAddress,
      },
      priceFeeds: {
        priceFeedZOR: zeroAddress,
        priceFeedLPPoolOtherToken: zeroAddress,
        stablecoinPriceFeed: zeroAddress,
      },
    };
    await deployProxy(MockZorroController, [zcInitVal], { deployer });

    // Zorro Controller X Chain
    const zcxInitVal = {
      defaultStablecoin: zeroAddress,
      ZORRO: MockZorroToken.address,
      zorroLPPoolOtherToken: zeroAddress,
      zorroStakingVault: zeroAddress,
      uniRouterAddress: zeroAddress,
      homeChainZorroController: zeroAddress,
      currentChainController: zeroAddress,
      publicPool: zeroAddress,
      bridge: {
        chainId: 0,
        homeChainId: 0,
        ZorroChainIDs: [],
        controllerContracts: [],
        LZChainIDs: [],
        stargateDestPoolIds: [],
        stargateRouter: zeroAddress,
        layerZeroEndpoint: zeroAddress,
        stargateSwapPoolId: zeroAddress,
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
    await deployProxy(MockZorroControllerXChain, [zcxInitVal], { deployer });

    // Tokens
    await deployer.deploy(MockUSDC);
    await deployer.deploy(MockBUSD);
    await deployer.deploy(MockAlpaca);
    await deployer.deploy(MockAMMToken0);
    await deployer.deploy(MockAMMToken1);
    await deployer.deploy(MockAMMOtherLPToken);

    // Other contracts
    await deployer.deploy(MockAMMFarm);
    await deployer.deploy(MockAlpacaFarm);
    await deployer.deploy(MockAlpacaVault);
    await deployer.deploy(MockStargateRouter);
    await deployer.deploy(MockStargatePool);
    await deployer.deploy(MockStargateLPStaking);
    await deployer.deploy(MockSTGToken);
    await deployer.deploy(MockLayerZeroEndpoint);

    // Vaults
    // VaultZorro
    const initVal0 = {
      pid: 0,
      keyAddresses: {
        govAddress: accounts[0],
        zorroControllerAddress: zeroAddress,
        zorroXChainController: zeroAddress,
        ZORROAddress: zeroAddress,
        zorroStakingVault: zeroAddress,
        wantAddress: zeroAddress,
        token0Address: zeroAddress,
        token1Address: zeroAddress,
        earnedAddress: zeroAddress,
        farmContractAddress: zeroAddress,
        rewardsAddress: zeroAddress,
        poolAddress: zeroAddress,
        uniRouterAddress: zeroAddress,
        zorroLPPool: zeroAddress,
        zorroLPPoolOtherToken: zeroAddress,
        defaultStablecoin: zeroAddress,
      },
      stablecoinToToken0Path: [],
      fees: {
        controllerFee: 0,
        buyBackRate: 0,
        revShareRate: 0,
        entranceFeeFactor: 0,
        withdrawFeeFactor: 0,
      },
      priceFeeds: {
        token0PriceFeed: zeroAddress,
        token1PriceFeed: zeroAddress,
        earnTokenPriceFeed: zeroAddress,
        ZORPriceFeed: zeroAddress,
        lpPoolOtherTokenPriceFeed: zeroAddress,
        stablecoinPriceFeed: zeroAddress,
      },
    };
    await deployer.link(VaultLibrary, [MockVaultZorro]);
    await deployProxy(
      MockVaultZorro,
      [
        accounts[0],
        initVal0,
      ], {
      deployer,
      unsafeAllow: [
        'external-library-linking',
      ],
    });

    // VaultAlpaca
    const initVal1 = {
      pid: 0,
      isHomeChain: true,
      isFarmable: true,
      keyAddresses: {
        govAddress: accounts[0],
        zorroControllerAddress: zeroAddress,
        zorroXChainController: zeroAddress,
        ZORROAddress: zeroAddress,
        zorroStakingVault: zeroAddress,
        wantAddress: zeroAddress,
        token0Address: zeroAddress,
        token1Address: zeroAddress,
        earnedAddress: zeroAddress,
        farmContractAddress: zeroAddress,
        rewardsAddress: zeroAddress,
        poolAddress: zeroAddress,
        uniRouterAddress: zeroAddress,
        zorroLPPool: zeroAddress,
        zorroLPPoolOtherToken: zeroAddress,
        defaultStablecoin: zeroAddress,
      },
      earnedToZORROPath: [],
      earnedToToken0Path: [],
      stablecoinToToken0Path: [],
      earnedToZORLPPoolOtherTokenPath: [],
      earnedToStablecoinPath: [],
      stablecoinToZORROPath: [],
      stablecoinToLPPoolOtherTokenPath: [],
      fees: {
        controllerFee: 0,
        buyBackRate: 0,
        revShareRate: 0,
        entranceFeeFactor: 0,
        withdrawFeeFactor: 0,
      },
      priceFeeds: {
        token0PriceFeed: zeroAddress,
        token1PriceFeed: zeroAddress,
        earnTokenPriceFeed: zeroAddress,
        ZORPriceFeed: zeroAddress,
        lpPoolOtherTokenPriceFeed: zeroAddress,
        stablecoinPriceFeed: zeroAddress,
      },
    };
    await deployer.link(VaultLibrary, [MockVaultAlpaca]);
    await deployer.link(VaultLibraryAlpaca, [MockVaultAlpaca]);
    await deployProxy(
      MockVaultAlpaca,
      [
        accounts[0],
        initVal1
      ], {
      deployer,
      unsafeAllow: [
        'external-library-linking',
      ],
    });

    // VaultStandardAMM
    const initVal2 = {
      pid: 0,
      isHomeChain: true,
      isFarmable: true,
      keyAddresses: {
        govAddress: accounts[0],
        zorroControllerAddress: zeroAddress,
        zorroXChainController: zeroAddress,
        ZORROAddress: zeroAddress,
        zorroStakingVault: zeroAddress,
        wantAddress: zeroAddress,
        token0Address: zeroAddress,
        token1Address: zeroAddress,
        earnedAddress: zeroAddress,
        farmContractAddress: zeroAddress,
        rewardsAddress: zeroAddress,
        poolAddress: zeroAddress,
        uniRouterAddress: zeroAddress,
        zorroLPPool: zeroAddress,
        zorroLPPoolOtherToken: zeroAddress,
        defaultStablecoin: zeroAddress,
      },
      earnedToZORROPath: [],
      earnedToToken0Path: [],
      earnedToToken1Path: [],
      stablecoinToToken0Path: [],
      stablecoinToToken1Path: [],
      earnedToZORLPPoolOtherTokenPath: [],
      earnedToStablecoinPath: [],
      fees: {
        controllerFee: 0,
        buyBackRate: 0,
        revShareRate: 0,
        entranceFeeFactor: 0,
        withdrawFeeFactor: 0,
      },
      priceFeeds: {
        token0PriceFeed: zeroAddress,
        token1PriceFeed: zeroAddress,
        earnTokenPriceFeed: zeroAddress,
        ZORPriceFeed: zeroAddress,
        lpPoolOtherTokenPriceFeed: zeroAddress,
        stablecoinPriceFeed: zeroAddress,
      },
    };
    await deployer.link(VaultLibrary, [MockVaultStandardAMM]);
    await deployer.link(VaultLibraryStandardAMM, [MockVaultStandardAMM]);
    await deployProxy(
      MockVaultStandardAMM,
      [
        accounts[0],
        initVal2
      ], {
      deployer,
      unsafeAllow: [
        'external-library-linking',
      ],
    });

    // VaultStargate
    const initVal3 = {
      pid: 0,
      isHomeChain: true,
      isFarmable: true,
      keyAddresses: {
        govAddress: accounts[0],
        zorroControllerAddress: zeroAddress,
        zorroXChainController: zeroAddress,
        ZORROAddress: zeroAddress,
        zorroStakingVault: zeroAddress,
        wantAddress: zeroAddress,
        token0Address: zeroAddress,
        token1Address: zeroAddress,
        earnedAddress: zeroAddress,
        farmContractAddress: zeroAddress,
        rewardsAddress: zeroAddress,
        poolAddress: zeroAddress,
        uniRouterAddress: zeroAddress,
        zorroLPPool: zeroAddress,
        zorroLPPoolOtherToken: zeroAddress,
        defaultStablecoin: zeroAddress,
      },
      earnedToZORROPath: [],
      earnedToToken0Path: [],
      stablecoinToToken0Path: [],
      earnedToZORLPPoolOtherTokenPath: [],
      earnedToStablecoinPath: [],
      fees: {
        controllerFee: 0,
        buyBackRate: 0,
        revShareRate: 0,
        entranceFeeFactor: 0,
        withdrawFeeFactor: 0,
      },
      priceFeeds: {
        token0PriceFeed: zeroAddress,
        token1PriceFeed: zeroAddress,
        earnTokenPriceFeed: zeroAddress,
        ZORPriceFeed: zeroAddress,
        lpPoolOtherTokenPriceFeed: zeroAddress,
        stablecoinPriceFeed: zeroAddress,
      },
      tokenSTG: zeroAddress,
      stargateRouter: zeroAddress,
      stargatePoolId: 0
    };
    await deployer.link(VaultLibrary, [MockVaultStargate]);
    await deployProxy(
      MockVaultStargate,
      [
        accounts[0],
        initVal3,
      ], {
      deployer,
      unsafeAllow: [
        'external-library-linking',
      ],
    });

    await deployer.deploy(MockPriceAggToken0);
    await deployer.deploy(MockPriceAggToken1);
    await deployer.deploy(MockPriceAggEarnToken);
    await deployer.deploy(MockPriceAggZOR);
    await deployer.deploy(MockPriceAggLPOtherToken);
    await deployer.deploy(MockLPPool);
    await deployer.deploy(MockLPPool1);
    await deployer.deploy(MockPriceUSDC);
    await deployer.deploy(MockPriceBUSD);

    await deployer.link(VaultLibrary, [MockInvestmentVault]);
    await deployProxy(
      MockInvestmentVault,
      [
        accounts[0]
      ], {
      deployer,
      unsafeAllow: [
        'external-library-linking',
      ],
    });
    await deployer.link(VaultLibrary, [MockInvestmentVault1]);
    await deployProxy(
      MockInvestmentVault1,
      [
        accounts[0]
      ], {
      deployer,
      unsafeAllow: [
        'external-library-linking',
      ],
    });
  } else {
    console.log('On live network. Skipping deployment of contracts');
  }

};