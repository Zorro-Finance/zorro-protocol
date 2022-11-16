// Addresses
const zeroAddress = '0x0000000000000000000000000000000000000000';
const wavaxOnAvax = '0xb31f66aa3c1e785363f0875a1b74e27b85fd66c7';

// Key params
exports.getKeyParams = (accounts, zorroToken) => ({
  test: {
    vaults: {
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
    },
  },
  dev: {
    defaultStablecoin: zeroAddress,
    uniRouterAddress: zeroAddress,
    uniFactoryAddress: zeroAddress,
    uniPoolAddress: zeroAddress,
    zorroLPPoolOtherToken: zeroAddress,
    stablecoinToZorroPath: [
      zeroAddress,
      zorroToken,
    ],
    stablecoinToZorroLPPoolOtherTokenPath: [
      zeroAddress,
      zeroAddress,
    ],
    rewards: {
      blocksPerDay: 43200,
      startBlock: 0,
      ZORROPerBlock: 0,
      targetTVLCaptureBasisPoints: 100,
      chainMultiplier: 1,
      baseRewardRateBasisPoints: 10,
    },
    xChain: {
      chainId: 0,
      homeChainId: 0,
      homeChainZorroController: zeroAddress, // To be filled in on each chain
      zorroControllerOracle: accounts[0], // Initially set to deployer address
      zorroXChainEndpoint: zeroAddress, // To be filled in on each chain after deployment
    },
    priceFeeds: {
      priceFeedZOR: zeroAddress, 
      priceFeedLPPoolOtherToken: zeroAddress,
      priceFeedStablecoin: zeroAddress,
    },
    zorroLPPool: zeroAddress, // To be filled in on home chain after deployment!
    bridge: {
      chainId: 0,
      homeChainId: 0,
      ZorroChainIDs: [0],
      controllerContracts: [zeroAddress], // To be filled in on each chain
      LZChainIDs: [6],
      stargateDestPoolIds: [zeroAddress],
      stargateRouter: zeroAddress,
      layerZeroEndpoint: zeroAddress,
      stargateSwapPoolId: zeroAddress,
      stargatePoolId: 1,
      tokenSTG: zeroAddress,
    },
    vaults: {
      pid: 0, // needs to be re-set to appropriate value, if applicable
      fees: {
        controllerFee: 400,
        buyBackRate: 200,
        revShareRate: 300,
        entranceFeeFactor: 9990,
        withdrawFeeFactor: 10000,
      },
    },
  },
  avax: {
    defaultStablecoin: '0xb97ef9ef8734c71904d8002f8b6bc66dd9c48a6e',
    uniRouterAddress: '0x60aE616a2155Ee3d9A68541Ba4544862310933d4',
    uniFactoryAddress: '0x9Ad6C38BE94206cA50bb0d90783181662f0Cfa10',
    uniPoolAddress: '0xf4003f4efbe8691b60249e6afbd307abe7758adb', // WAVAX/USDC
    zorroLPPoolOtherToken: '0xb31f66aa3c1e785363f0875a1b74e27b85fd66c7', // WAVAX
    stablecoinToZorroPath: [
      zeroAddress,
      zorroToken,
    ],
    stablecoinToZorroLPPoolOtherTokenPath: [
      '0xb97ef9ef8734c71904d8002f8b6bc66dd9c48a6e',
      '0xb31f66aa3c1e785363f0875a1b74e27b85fd66c7',
    ],
    rewards: {
      blocksPerDay: 43200, // 1.9 blocks per sec
      startBlock: 0,
      ZORROPerBlock: 0, // Needs to be calculated, see below
      targetTVLCaptureBasisPoints: 100, // TODO: Sascha: need input here
      chainMultiplier: 1,
      baseRewardRateBasisPoints: 10, // 0.1%
    },
    xChain: {
      chainId: 0,
      homeChainId: 0,
      homeChainZorroController: zeroAddress, // To be filled in on each chain
      zorroControllerOracle: accounts[0], // Initially set to deployer address
      zorroXChainEndpoint: zeroAddress, // To be filled in on each chain after deployment
    },
    priceFeeds: {
      priceFeedZOR: zeroAddress, // TODO: Fill this out with the actual value on each chain, once Oracle is up
      priceFeedLPPoolOtherToken: '0x0A77230d17318075983913bC2145DB16C7366156', // AVAX/USD price feed
      priceFeedStablecoin: '0xF096872672F44d6EBA71458D74fe67F9a77a23B9',
    },
    zorroLPPool: zeroAddress, // To be filled in on home chain after deployment!
    bridge: {
      chainId: 0,
      homeChainId: 0,
      ZorroChainIDs: [0],
      controllerContracts: [zeroAddress], // To be filled in on each chain
      LZChainIDs: [6],
      stargateDestPoolIds: ['0x1205f31718499dBf1fCa446663B532Ef87481fe1'],
      stargateRouter: '0x45A01E4e04F14f7A4a6702c74187c5F6222033cd',
      layerZeroEndpoint: '0x3c2269811836af69497E5F486A85D7316753cf62',
      stargateSwapPoolId: '0x1205f31718499dBf1fCa446663B532Ef87481fe1',
      stargatePoolId: 1,
      tokenSTG: '0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590',
    },
    vaults: {
      pid: 0, // needs to be re-set to appropriate value, if applicable
      // TODO: Fill these in with initial values by launch time
      fees: {
        controllerFee: 400,
        buyBackRate: 200,
        revShareRate: 300,
        entranceFeeFactor: 9990,
        withdrawFeeFactor: 10000,
      },
    },
  },
  bsc: {
    defaultStablecoin: '0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d',
    uniRouterAddress: '0x10ED43C718714eb63d5aA57B78B54704E256024E',
    uniFactoryAddress: '0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73',
    uniPoolAddress: zeroAddress,
    zorroLPPoolOtherToken: zeroAddress,
    stablecoinToZorroPath: [
      '0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d',
      zorroToken,
    ],
    stablecoinToZorroLPPoolOtherTokenPath: [],
    rewards: {
      blocksPerDay: 28800, // 3 secs per block
      startBlock: 0,
      ZORROPerBlock: 0, // Needs to be calculated, see below
      targetTVLCaptureBasisPoints: 100, // TODO: Sascha: need input here
      chainMultiplier: 1,
      baseRewardRateBasisPoints: 10, // 0.1%
    },
    xChain: {
      chainId: 0,
      homeChainId: 0,
      homeChainZorroController: zeroAddress, // To be filled in on each chain
      zorroControllerOracle: accounts[0], // Initially set to deployer address
      zorroXChainEndpoint: zeroAddress, // To be filled in on each chain after deployment
    },
    priceFeeds: {
      priceFeedZOR: zeroAddress, // TODO: Fill this out with the actual value on each chain, once Oracle is up
      priceFeedLPPoolOtherToken: zeroAddress,
      priceFeedStablecoin: '0x9331b55D9830EF609A2aBCfAc0FBCE050A52fdEa', // BUSD
    },
    zorroLPPool: zeroAddress,
    bridge: {
      chainId: 1,
      homeChainId: 0,
      ZorroChainIDs: [1],
      controllerContracts: [zeroAddress], // To be filled in on each chain // TODO: Need to adjust for BSC, AVAX
      LZChainIDs: [2],
      stargateDestPoolIds: [],
      stargateRouter: '0x4a364f8c717cAAD9A442737Eb7b8A55cc6cf18D8',
      layerZeroEndpoint: '0x3c2269811836af69497E5F486A85D7316753cf62',
      stargateSwapPoolId: '0x98a5737749490856b401DB5Dc27F522fC314A4e1', // BUSD not USDC
      stargatePoolId: 5,
      tokenSTG: '0xB0D502E938ed5f4df2E681fE6E419ff29631d62b',
    },
    vaults: {
      pid: 0, // needs to be re-set to appropriate value, if applicable
      // TODO: Fill these in with initial values by launch time
      fees: {
        controllerFee: 400,
        buyBackRate: 200,
        revShareRate: 300,
        entranceFeeFactor: 9990,
        withdrawFeeFactor: 10000,
      },
    },
  },
});

const testNets = [
  'ganachecli',
  'default',
  'test',
]

const devNets = [
  'development',
  'avaxfork',
  'bscfork',
  ...testNets,
];

const homeNetworks = [
  'avax',
  ...devNets,
];

exports.zeroAddress = zeroAddress;
exports.wavaxOnAvax = wavaxOnAvax;
exports.testNets = testNets;
exports.devNets = devNets;
exports.homeNetworks = homeNetworks;

exports.getSynthNetwork = (network) => {
  if (network === 'avaxfork') {
    return 'avax';
  }

  if (network === 'bscfork') {
    return 'bsc';
  }

  if (devNets.includes(network)) {
    return 'dev';
  }

  return network;
};