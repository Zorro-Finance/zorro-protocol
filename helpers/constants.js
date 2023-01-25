// TODO: Must fill out these values

exports.zeroAddress = '0x0000000000000000000000000000000000000000';

exports.homeNetwork = 'bnb';

exports.owners = [
  
];

exports.defaultTimelockPeriodSecs = 24 * 3600;

exports.chains = {
  avax: {
    rewards: {
      blocksPerDay: 0,
      targetTVLCaptureBasisPoints: 0,
      chainMultiplier: 1,
      baseRewardRateBasisPoints: 0,
    },
    xChain: {
      chainId: 0,
      homeChainId: 0,
      zChainId: 0,
      lzChainId: 0, // TODO Correct this
      sgPoolId: 0, // TODO Correct this
    },
    tokens: {
      wavax: '0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7',
      usdc: '0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E',
      stg: '0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590',
      joe: '0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd',
      qi: '0x8729438EB15e2C8B576fCc6AeCdA6A148776C0F5',
    },
    priceFeeds: {
      usdc: '0xF096872672F44d6EBA71458D74fe67F9a77a23B9',
      avax: '0x0A77230d17318075983913bC2145DB16C7366156',
      joe: '0x02D35d3a8aC3e1626d3eE09A78Dd87286F5E8e3a',
      qi: '0x36E039e6391A5E7A7267650979fdf613f659be5D',
    },
    infra: {
      uniRouterAddress: '0x60aE616a2155Ee3d9A68541Ba4544862310933d4',
      uniFactoryAddress: '0x9Ad6C38BE94206cA50bb0d90783181662f0Cfa10',
      stargateRouter: '0x45A01E4e04F14f7A4a6702c74187c5F6222033cd',
      layerZeroEndpoint: '0x3c2269811836af69497E5F486A85D7316753cf62',
    },
    protocols: {
      benqi: {
        avaxLendingPool: '0x5C0401e81Bc07Ca70fAD469b451682c0d747Ef1c',
        comptroller: '0x486Af39519B4Dc9a7fCcd318217352830E8AD9b4',
        tokenSaleDistributor: '0x77533A0b34cd9Aa135EBE795dc40666Ca295C16D',
      },
      aave: {

      },
      traderjoe: {
        joeToken: '',
        poolUSDC_AVAX: '',
        pidUSDC_AVAX: '',
        masterChef: '',
      },
    },
  },
  bnb: {
    // TODO: Correct all of these values
    rewards: {
      blocksPerDay: 0,
      targetTVLCaptureBasisPoints: 0,
      chainMultiplier: 1,
      baseRewardRateBasisPoints: 0,
    },
    xChain: {
      chainId: 0,
      homeChainId: 0,
      zChainId: 0,
      lzChainId: 0, // TODO Correct this
      sgPoolId: 0, // TODO Correct this
    },
    tokens: {
      wbnb: '0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c',
      busd: '0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56',
    },
    priceFeeds: {
      busd: '0xcBb98864Ef56E9042e7d2efef76141f15731B82f',
      bnb: '0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE',
      cake: '0xB6064eD41d4f67e353768aA239cA86f4F73665a1',
      alpaca: '0xe0073b60833249ffd1bb2af809112c2fbf221DF6',
    },
    infra: {
      uniRouterAddress: '0x10ED43C718714eb63d5aA57B78B54704E256024E',
      uniFactoryAddress: '0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73',
      stargateRouter: '0x4a364f8c717cAAD9A442737Eb7b8A55cc6cf18D8',
      layerZeroEndpoint: '0x3c2269811836af69497E5F486A85D7316753cf62',
    },
    protocols: {
      apeswap: {
        
      },
      stader: {
        
      },
      stargate: {
          
      },
      alpaca: {
        alpaca: '0x8F0528cE5eF7B51152A59745bEfDD91D97091d2F',
        fairLaunch: '0xA625AB01B08ce023B2a342Dbb12a16f2C8489A8F', // Farm contract
        levPoolBNB: '0xd7D069493685A581d27824Fc46EdA46B7EfC0063', // Pool for leveraged BNB lending
      },
      pancakeswap: {
        cake: '0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82',

      },
    },
  },
};

// TODO: Is this global or per chain?
exports.rewards = {
  blocksPerDay: 43200,
  startBlock: 0,
  ZORROPerBlock: 0,
  targetTVLCaptureBasisPoints: 100,
  chainMultiplier: 1,
  baseRewardRateBasisPoints: 10,
};

// TODO: Sascha review
exports.vaultFees = {
  controllerFee: 0,
  buyBackRate: 0,
  revShareRate: 0,
  entranceFeeFactor: 0,
  withdrawFeeFactor: 0,
};

// Vesting
exports.vesting = {
  cliffPeriodSecs: 6 * 30 * 24 * 3600,
  vestingPeriodSecs: 24 * 30 * 24 * 3600,
};

// Distribution
exports.ZORDistributions = {
  public: 0.65,
  treasury: 0.2,
  advisors: 0.03,
  team: 0.12,
};
exports.ZORTotalDistribution = 800000;