// Upgrades
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
const { deploy } = require('@openzeppelin/truffle-upgrades/dist/utils');
// Controllers (only for testing)
const MockZorroController = artifacts.require("MockZorroController");
const MockZorroControllerXChain = artifacts.require("MockZorroControllerXChain");
// Token (only for testing)
const MockZorroToken = artifacts.require("MockZorroToken");
const MockUSDC = artifacts.require("MockUSDC");
const MockBUSD = artifacts.require("MockBUSD");
const MockACS = artifacts.require("MockACS");
const MockAMMToken0 = artifacts.require("MockAMMToken0");
const MockAMMToken1 = artifacts.require("MockAMMToken1");
const MockAMMOtherLPToken = artifacts.require("MockAMMOtherLPToken");
// Vaults (only for testing)
const MockVaultAcryptosSingle = artifacts.require("MockVaultAcryptosSingle");
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
// Other contracts
// AMM
const MockAMMFarm = artifacts.require('MockAMMFarm');
const MockLPPool = artifacts.require('MockLPPool');
const MockLPPool1 = artifacts.require('MockLPPool1');
// Acryptos
const MockAcryptosFarm = artifacts.require('MockAcryptosFarm');
const MockAcryptosVault = artifacts.require('MockAcryptosVault');
// Stargate
const MockStargateRouter = artifacts.require('MockStargateRouter');
const MockStargatePool = artifacts.require('MockStargatePool');
const MockStargateLPStaking = artifacts.require('MockStargateLPStaking');
const MockSTGToken = artifacts.require('MockSTGToken');
// LayerZero
const MockLayerZeroEndpoint = artifacts.require('MockLayerZeroEndpoint');

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
      defaultStablecoin: '0x0000000000000000000000000000000000000000',
      zorroLPPoolOtherToken: '0x0000000000000000000000000000000000000000',
      publicPool: '0x0000000000000000000000000000000000000000',
      zorroStakingVault: '0x0000000000000000000000000000000000000000',
      zorroLPPool: '0x0000000000000000000000000000000000000000',
      uniRouterAddress: '0x0000000000000000000000000000000000000000',
      USDCToZorroPath: [],
      USDCToZorroLPPoolOtherTokenPath: [],
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
        homeChainZorroController: '0x0000000000000000000000000000000000000000',
        zorroControllerOracle: '0x0000000000000000000000000000000000000000',
        zorroXChainEndpoint: '0x0000000000000000000000000000000000000000',
      },
      priceFeeds: {
        priceFeedZOR: '0x0000000000000000000000000000000000000000',
        priceFeedLPPoolOtherToken: '0x0000000000000000000000000000000000000000',
      },
    };
    await deployProxy(MockZorroController, [zcInitVal], { deployer });

    // Zorro Controller X Chain
    const zcxInitVal = {
      defaultStablecoin: '0x0000000000000000000000000000000000000000',
      ZORRO: MockZorroToken.address,
      zorroLPPoolOtherToken: '0x0000000000000000000000000000000000000000',
      zorroStakingVault: '0x0000000000000000000000000000000000000000',
      uniRouterAddress: '0x0000000000000000000000000000000000000000',
      homeChainZorroController: '0x0000000000000000000000000000000000000000',
      currentChainController: '0x0000000000000000000000000000000000000000',
      publicPool: '0x0000000000000000000000000000000000000000',
      bridge: {
        chainId: 0,
        homeChainId: 0,
        ZorroChainIDs: [],
        controllerContracts: [],
        LZChainIDs: [],
        stargateDestPoolIds: [],
        stargateRouter: '0x0000000000000000000000000000000000000000',
        layerZeroEndpoint: '0x0000000000000000000000000000000000000000',
        stargateSwapPoolId: '0x0000000000000000000000000000000000000000',
      },
      swaps: {
        USDCToZorroPath: [],
        USDCToZorroLPPoolOtherTokenPath: [],
      },
      priceFeeds: {
        priceFeedZOR: '0x0000000000000000000000000000000000000000',
        priceFeedLPPoolOtherToken: '0x0000000000000000000000000000000000000000',
      },
    };
    await deployProxy(MockZorroControllerXChain, [zcxInitVal], { deployer });

    // Tokens
    await deployer.deploy(MockUSDC);
    await deployer.deploy(MockBUSD);
    await deployer.deploy(MockACS);
    await deployer.deploy(MockAMMToken0);
    await deployer.deploy(MockAMMToken1);
    await deployer.deploy(MockAMMOtherLPToken);

    // Other contracts
    await deployer.deploy(MockAMMFarm);
    await deployer.deploy(MockAcryptosFarm);
    await deployer.deploy(MockAcryptosVault);
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
        zorroControllerAddress: '0x0000000000000000000000000000000000000000',
        zorroXChainController: '0x0000000000000000000000000000000000000000',
        ZORROAddress: '0x0000000000000000000000000000000000000000',
        zorroStakingVault: '0x0000000000000000000000000000000000000000',
        wantAddress: '0x0000000000000000000000000000000000000000',
        token0Address: '0x0000000000000000000000000000000000000000',
        token1Address: '0x0000000000000000000000000000000000000000',
        earnedAddress: '0x0000000000000000000000000000000000000000',
        farmContractAddress: '0x0000000000000000000000000000000000000000',
        rewardsAddress: '0x0000000000000000000000000000000000000000',
        poolAddress: '0x0000000000000000000000000000000000000000',
        uniRouterAddress: '0x0000000000000000000000000000000000000000',
        zorroLPPool: '0x0000000000000000000000000000000000000000',
        zorroLPPoolOtherToken: '0x0000000000000000000000000000000000000000',
        tokenUSDCAddress: '0x0000000000000000000000000000000000000000',
      },
      USDCToToken0Path: [],
      fees: {
        controllerFee: 0,
        buyBackRate: 0,
        revShareRate: 0,
        entranceFeeFactor: 0,
        withdrawFeeFactor: 0,
      },
      priceFeeds: {
        token0PriceFeed: '0x0000000000000000000000000000000000000000',
        token1PriceFeed: '0x0000000000000000000000000000000000000000',
        earnTokenPriceFeed: '0x0000000000000000000000000000000000000000',
        ZORPriceFeed: '0x0000000000000000000000000000000000000000',
        lpPoolOtherTokenPriceFeed: '0x0000000000000000000000000000000000000000',
      },
    };
    await deployProxy(MockVaultZorro, [accounts[0], initVal0], {deployer});
    
    // VaultAcryptosSingle
    const initVal1 = {
      pid: 0,
      isHomeChain: true,
      isFarmable: true,
      keyAddresses: {
        govAddress: accounts[0],
        zorroControllerAddress: '0x0000000000000000000000000000000000000000',
        zorroXChainController: '0x0000000000000000000000000000000000000000',
        ZORROAddress: '0x0000000000000000000000000000000000000000',
        zorroStakingVault: '0x0000000000000000000000000000000000000000',
        wantAddress: '0x0000000000000000000000000000000000000000',
        token0Address: '0x0000000000000000000000000000000000000000',
        token1Address: '0x0000000000000000000000000000000000000000',
        earnedAddress: '0x0000000000000000000000000000000000000000',
        farmContractAddress: '0x0000000000000000000000000000000000000000',
        rewardsAddress: '0x0000000000000000000000000000000000000000',
        poolAddress: '0x0000000000000000000000000000000000000000',
        uniRouterAddress: '0x0000000000000000000000000000000000000000',
        zorroLPPool: '0x0000000000000000000000000000000000000000',
        zorroLPPoolOtherToken: '0x0000000000000000000000000000000000000000',
        tokenUSDCAddress: '0x0000000000000000000000000000000000000000',
      },
      earnedToZORROPath: [],
      earnedToToken0Path: [],
      USDCToToken0Path: [],
      earnedToZORLPPoolOtherTokenPath: [],
      earnedToUSDCPath: [],
      BUSDToToken0Path: [],
      BUSDToZORROPath: [],
      BUSDToLPPoolOtherTokenPath: [],
      fees: {
        controllerFee: 0,
        buyBackRate: 0,
        revShareRate: 0,
        entranceFeeFactor: 0,
        withdrawFeeFactor: 0,
      },
      priceFeeds: {
        token0PriceFeed: '0x0000000000000000000000000000000000000000',
        token1PriceFeed: '0x0000000000000000000000000000000000000000',
        earnTokenPriceFeed: '0x0000000000000000000000000000000000000000',
        ZORPriceFeed: '0x0000000000000000000000000000000000000000',
        lpPoolOtherTokenPriceFeed: '0x0000000000000000000000000000000000000000',
      },
    };
    await deployProxy(MockVaultAcryptosSingle, [accounts[0], initVal1], {deployer});

    // VaultStandardAMM
    const initVal2 = {
      pid: 0,
      isHomeChain: true,
      isFarmable: true,
      keyAddresses: {
        govAddress: accounts[0],
        zorroControllerAddress: '0x0000000000000000000000000000000000000000',
        zorroXChainController: '0x0000000000000000000000000000000000000000',
        ZORROAddress: '0x0000000000000000000000000000000000000000',
        zorroStakingVault: '0x0000000000000000000000000000000000000000',
        wantAddress: '0x0000000000000000000000000000000000000000',
        token0Address: '0x0000000000000000000000000000000000000000',
        token1Address: '0x0000000000000000000000000000000000000000',
        earnedAddress: '0x0000000000000000000000000000000000000000',
        farmContractAddress: '0x0000000000000000000000000000000000000000',
        rewardsAddress: '0x0000000000000000000000000000000000000000',
        poolAddress: '0x0000000000000000000000000000000000000000',
        uniRouterAddress: '0x0000000000000000000000000000000000000000',
        zorroLPPool: '0x0000000000000000000000000000000000000000',
        zorroLPPoolOtherToken: '0x0000000000000000000000000000000000000000',
        tokenUSDCAddress: '0x0000000000000000000000000000000000000000',
      },
      earnedToZORROPath: [],
      earnedToToken0Path: [],
      earnedToToken1Path: [],
      USDCToToken0Path: [],
      USDCToToken1Path: [],
      earnedToZORLPPoolOtherTokenPath: [],
      earnedToUSDCPath: [],
      fees: {
        controllerFee: 0,
        buyBackRate: 0,
        revShareRate: 0,
        entranceFeeFactor: 0,
        withdrawFeeFactor: 0,
      },
      priceFeeds: {
        token0PriceFeed: '0x0000000000000000000000000000000000000000',
        token1PriceFeed: '0x0000000000000000000000000000000000000000',
        earnTokenPriceFeed: '0x0000000000000000000000000000000000000000',
        ZORPriceFeed: '0x0000000000000000000000000000000000000000',
        lpPoolOtherTokenPriceFeed: '0x0000000000000000000000000000000000000000',
      },
    };
    await deployProxy(MockVaultStandardAMM, [accounts[0], initVal2], {deployer});
    
    // VaultStargate
    const initVal3 = {
      pid: 0,
      isHomeChain: true,
      isFarmable: true,
      keyAddresses: {
        govAddress: accounts[0],
        zorroControllerAddress: '0x0000000000000000000000000000000000000000',
        zorroXChainController: '0x0000000000000000000000000000000000000000',
        ZORROAddress: '0x0000000000000000000000000000000000000000',
        zorroStakingVault: '0x0000000000000000000000000000000000000000',
        wantAddress: '0x0000000000000000000000000000000000000000',
        token0Address: '0x0000000000000000000000000000000000000000',
        token1Address: '0x0000000000000000000000000000000000000000',
        earnedAddress: '0x0000000000000000000000000000000000000000',
        farmContractAddress: '0x0000000000000000000000000000000000000000',
        rewardsAddress: '0x0000000000000000000000000000000000000000',
        poolAddress: '0x0000000000000000000000000000000000000000',
        uniRouterAddress: '0x0000000000000000000000000000000000000000',
        zorroLPPool: '0x0000000000000000000000000000000000000000',
        zorroLPPoolOtherToken: '0x0000000000000000000000000000000000000000',
        tokenUSDCAddress: '0x0000000000000000000000000000000000000000',
      },
      earnedToZORROPath: [],
      earnedToToken0Path: [],
      USDCToToken0Path: [],
      earnedToZORLPPoolOtherTokenPath: [],
      earnedToUSDCPath: [],
      fees: {
        controllerFee: 0,
        buyBackRate: 0,
        revShareRate: 0,
        entranceFeeFactor: 0,
        withdrawFeeFactor: 0,
      },
      priceFeeds: {
        token0PriceFeed: '0x0000000000000000000000000000000000000000',
        token1PriceFeed: '0x0000000000000000000000000000000000000000',
        earnTokenPriceFeed: '0x0000000000000000000000000000000000000000',
        ZORPriceFeed: '0x0000000000000000000000000000000000000000',
        lpPoolOtherTokenPriceFeed: '0x0000000000000000000000000000000000000000',
      },
      tokenSTG: '0x0000000000000000000000000000000000000000',
      stargateRouter: '0x0000000000000000000000000000000000000000',
      stargatePoolId: 0
    };
  
    await deployProxy(MockVaultStargate, [accounts[0], initVal3], {deployer});

    await deployer.deploy(MockPriceAggToken0);
    await deployer.deploy(MockPriceAggToken1);
    await deployer.deploy(MockPriceAggEarnToken);
    await deployer.deploy(MockPriceAggZOR);
    await deployer.deploy(MockPriceAggLPOtherToken);
    await deployer.deploy(MockLPPool);
    await deployer.deploy(MockLPPool1);
    
    await deployProxy(MockInvestmentVault, [accounts[0]], {deployer});
    await deployProxy(MockInvestmentVault1, [accounts[0]], {deployer});
  } else {
    console.log('On live network. Skipping deployment of contracts');
  }

};