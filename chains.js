const zeroAdress = '0x0000000000000000000000000000000000000000';

// Key params
exports.getKeyParams = (accounts, zorroToken) => ({
  dev: {
    defaultStablecoin: zeroAdress,
    uniRouterAddress: zeroAdress,
    uniFactoryAddress: zeroAdress,
    uniPoolAddress: zeroAdress,
    zorroLPPoolOtherToken: zeroAdress,
    USDCToZorroPath: [
      zeroAdress,
      zorroToken,
    ],
    USDCToZorroLPPoolOtherTokenPath: [
      zeroAdress,
      zeroAdress,
    ],
    rewards: {
      blocksPerDay: 164160,
      startBlock: 0,
      ZORROPerBlock: 0,
      targetTVLCaptureBasisPoints: 100,
      chainMultiplier: 1,
      baseRewardRateBasisPoints: 10,
    },
    xChain: {
      chainId: 0,
      homeChainId: 0,
      homeChainZorroController: zeroAdress, // To be filled in on each chain
      zorroControllerOracle: accounts[0], // Initially set to deployer address
      zorroXChainEndpoint: zeroAdress, // To be filled in on each chain after deployment
    },
    priceFeeds: {
      priceFeedZOR: zeroAdress, 
      priceFeedLPPoolOtherToken: zeroAdress,
      priceFeedStablecoin: zeroAdress,
    },
    zorroLPPool: zeroAdress, // To be filled in on home chain after deployment!
    bridge: {
      chainId: 0,
      homeChainId: 0,
      ZorroChainIDs: [0],
      controllerContracts: [zeroAdress], // To be filled in on each chain
      LZChainIDs: [6],
      stargateDestPoolIds: [zeroAdress],
      stargateRouter: zeroAdress,
      layerZeroEndpoint: zeroAdress,
      stargateSwapPoolId: zeroAdress,
      stargatePoolId: 1,
      tokenSTG: zeroAdress,
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
    USDCToZorroPath: [
      zeroAdress,
      zorroToken,
    ],
    USDCToZorroLPPoolOtherTokenPath: [
      '0xb97ef9ef8734c71904d8002f8b6bc66dd9c48a6e',
      '0xb31f66aa3c1e785363f0875a1b74e27b85fd66c7',
    ],
    rewards: {
      blocksPerDay: 164160, // 1.9 blocks per sec
      startBlock: 0,
      ZORROPerBlock: 0, // Needs to be calculated, see below
      targetTVLCaptureBasisPoints: 100, // TODO: Sascha: need input here
      chainMultiplier: 1,
      baseRewardRateBasisPoints: 10, // 0.1%
    },
    xChain: {
      chainId: 0,
      homeChainId: 0,
      homeChainZorroController: zeroAdress, // To be filled in on each chain
      zorroControllerOracle: accounts[0], // Initially set to deployer address
      zorroXChainEndpoint: zeroAdress, // To be filled in on each chain after deployment
    },
    priceFeeds: {
      priceFeedZOR: zeroAdress, // TODO: Fill this out with the actual value on each chain, once Oracle is up
      priceFeedLPPoolOtherToken: '0x0A77230d17318075983913bC2145DB16C7366156', // AVAX/USD price feed
      priceFeedStablecoin: '0xF096872672F44d6EBA71458D74fe67F9a77a23B9',
    },
    zorroLPPool: zeroAdress, // To be filled in on home chain after deployment!
    bridge: {
      chainId: 0,
      homeChainId: 0,
      ZorroChainIDs: [0],
      controllerContracts: [zeroAdress], // To be filled in on each chain
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
  // TODO: The BSC node was just a copy of avax. Values must be changed before proper bsc migration
  bsc: {
    defaultStablecoin: '0xb97ef9ef8734c71904d8002f8b6bc66dd9c48a6e',
    uniRouterAddress: '0x60aE616a2155Ee3d9A68541Ba4544862310933d4',
    uniFactoryAddress: '0x9Ad6C38BE94206cA50bb0d90783181662f0Cfa10',
    uniPoolAddress: '0xf4003f4efbe8691b60249e6afbd307abe7758adb', // WAVAX/USDC
    zorroLPPoolOtherToken: '0xb31f66aa3c1e785363f0875a1b74e27b85fd66c7', // WAVAX
    USDCToZorroPath: [
      zeroAdress,
      zorroToken,
    ],
    USDCToZorroLPPoolOtherTokenPath: [
      '0xb97ef9ef8734c71904d8002f8b6bc66dd9c48a6e',
      '0xb31f66aa3c1e785363f0875a1b74e27b85fd66c7',
    ],
    rewards: {
      blocksPerDay: 164160, // 1.9 blocks per sec
      startBlock: 0,
      ZORROPerBlock: 0, // Needs to be calculated, see below
      targetTVLCaptureBasisPoints: 100, // TODO: Sascha: need input here
      chainMultiplier: 1,
      baseRewardRateBasisPoints: 10, // 0.1%
    },
    xChain: {
      chainId: 0,
      homeChainId: 0,
      homeChainZorroController: zeroAdress, // To be filled in on each chain
      zorroControllerOracle: accounts[0], // Initially set to deployer address
      zorroXChainEndpoint: zeroAdress, // To be filled in on each chain after deployment
    },
    priceFeeds: {
      priceFeedZOR: zeroAdress, // TODO: Fill this out with the actual value on each chain, once Oracle is up
      priceFeedLPPoolOtherToken: '0x0A77230d17318075983913bC2145DB16C7366156', // AVAX/USD price feed
      stablecoinPriceFeed: '0x51597f405303C4377E36123cBc172b13269EA163',
    },
    zorroLPPool: zeroAdress, // To be filled in on home chain after deployment!
    bridge: {
      chainId: 0,
      homeChainId: 0,
      ZorroChainIDs: [0],
      controllerContracts: [zeroAdress], // To be filled in on each chain
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
    tokenBUSDPriceFeed: '0x9331b55D9830EF609A2aBCfAc0FBCE050A52fdEa',
  },
});

const devNets = [
  'ganachecloud',
  'ganachecli',
  'default',
  'development',
  'test',
];

const homeNetworks = [
  'avax',
  ...devNets,
];

exports.devNets = devNets;
exports.homeNetworks = homeNetworks;

exports.getSynthNetwork = (network) => {
  if (network === 'ganachecloud') {
    return 'avax';
  }

  if (devNets.includes(network)) {
    return 'dev';
  }

  return network;
};