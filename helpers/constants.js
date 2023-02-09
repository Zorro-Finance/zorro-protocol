// TODO: Must fill out these values

const zeroAddress = '0x0000000000000000000000000000000000000000';

exports.zeroAddress = zeroAddress;

exports.homeNetwork = 'bnb';

exports.owners = [
  // TODO: Put in Sierra + Delta wallets
];

exports.defaultTimelockPeriodSecs = 24 * 3600;

exports.chains = {
  avax: {
    rewards: {
      ZORROPerBlock: 0,
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
      defaultStablecoin: '0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E',
      wavax: '0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7',
      usdc: '0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E',
      usdt: '0xc7198437980c041c805A1EDcbA50c1Ce5db95118',
      stg: '0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590',
      joe: '0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd',
      qi: '0x8729438EB15e2C8B576fCc6AeCdA6A148776C0F5',
    },
    priceFeeds: {
      defaultStablecoin: '0xF096872672F44d6EBA71458D74fe67F9a77a23B9',
      usdc: '0xF096872672F44d6EBA71458D74fe67F9a77a23B9',
      usdt: '0xEBE676ee90Fe1112671f19b6B7459bC678B67e8a',
      avax: '0x0A77230d17318075983913bC2145DB16C7366156',
      joe: '0x02D35d3a8aC3e1626d3eE09A78Dd87286F5E8e3a',
      qi: '0x36E039e6391A5E7A7267650979fdf613f659be5D',
      savax: '0x2854Ca10a54800e15A2a25cFa52567166434Ff0a',
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
        savax: '0x2b2C81e08f1Af8835a78Bb2A90AE924ACE0eA4bE',
        comptroller: '0x486Af39519B4Dc9a7fCcd318217352830E8AD9b4',
        tokenSaleDistributor: '0x77533A0b34cd9Aa135EBE795dc40666Ca295C16D',
      },
      aave: {

      },
      traderjoe: {
        joeToken: '',
        poolUSDC_AVAX: '',
        pidUSDC_AVAX: '',
        masterChef: '0x188bED1968b795d5c9022F6a0bb5931Ac4c18F00',
      },
      stargate: {
        poolUSDT: '0x29e38769f23701A2e4A8Ef0492e19dA4604Be62c',
        lpStaking: '0x8731d54E9D02c286767d56ac03e8037C07e01e98',
      },
    },
  },
  bnb: {
    // TODO: Correct all of these values
    rewards: {
      ZORROPerBlock: 0,
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
      defaultStablecoin: '0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56',
      wbnb: '0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c',
      busd: '0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56',
      eth: '0x2170Ed0880ac9A755fd29B2688956BD959F933F8',
    },
    priceFeeds: {
      defaultStablecoin: '0xcBb98864Ef56E9042e7d2efef76141f15731B82f',
      busd: '0xcBb98864Ef56E9042e7d2efef76141f15731B82f',
      bnb: '0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE',
      cake: '0xB6064eD41d4f67e353768aA239cA86f4F73665a1',
      alpaca: '0xe0073b60833249ffd1bb2af809112c2fbf221DF6',
      eth: '0x9ef1B8c0E4F7dc8bF5719Ea496883DC6401d5b2e',
    },
    infra: {
      uniRouterAddress: '0x10ED43C718714eb63d5aA57B78B54704E256024E',
      uniFactoryAddress: '0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73',
      stargateRouter: '0x4a364f8c717cAAD9A442737Eb7b8A55cc6cf18D8',
      layerZeroEndpoint: '0x3c2269811836af69497E5F486A85D7316753cf62',
    },
    protocols: {
      apeswap: {
        ethLendingPool: '0xaA1b1E1f251610aE10E4D553b05C662e60992EEd',
        banana: '0x603c7f932ED1fc6575303D8Fb018fDCBb0f39a95',
        unitroller: '0xAD48B2C9DC6709a560018c678e918253a65df86e',
      },
      stader: {
        
      },
      stargate: {
        stg: '0xB0D502E938ed5f4df2E681fE6E419ff29631d62b',
        lpStaking: '0x3052A0F6ab15b4AE1df39962d5DdEFacA86DaB47',
        poolBUSD: '0x98a5737749490856b401DB5Dc27F522fC314A4e1',
      },
      alpaca: {
        alpaca: '0x8F0528cE5eF7B51152A59745bEfDD91D97091d2F',
        fairLaunch: '0xA625AB01B08ce023B2a342Dbb12a16f2C8489A8F', // Farm contract
        levPoolBNB: '0xd7D069493685A581d27824Fc46EdA46B7EfC0063', // Pool for leveraged BNB lending
      },
      pancakeswap: {
        cake: '0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82',
        masterChef: '0xa5f8C5Dbd5F286960b9d90548680aE5ebFf07652',
      },
    },
  },
  bnbtest: {
    tokens: {
      defaultStablecoin: '0x1010Bb1b9Dff29e6233E7947e045e0ba58f6E92e', // BUSD
    },
    infra: {
      layerZeroEndpoint: '0x6Fcb97553D41516Cb228ac03FdC8B9a0a9df04A1',
      stargateRouter: '0xbB0f1be1E9CE9cB27EA5b0c3a85B7cc3381d8176',
      uniRouterAddress: zeroAddress,
    },
    xChain: {
      chainId: 0, // Zorro Chain ID (BNB)
      homeChainId: 0, // ID of the Zorro Home Chain (BNB)
      lzChainId: 10102,
      sgPoolId: 5, // BUSD
    },
  },
  avaxtest: {
    tokens: {
      defaultStablecoin: '0x4A0D1092E9df255cf95D72834Ea9255132782318', // USDC
    },
    infra: {
      layerZeroEndpoint: '0x93f54D755A063cE7bB9e6Ac47Eccc8e33411d706',
      stargateRouter: '0x13093E05Eb890dfA6DacecBdE51d24DabAb2Faa1',
      uniRouterAddress: zeroAddress,
    },
    xChain: {
      chainId: 1, // Zorro Chain ID (AVAX)
      homeChainId: 0, // ID of the Zorro Home Chain (BNB)
      lzChainId: 10106,
      sgPoolId: 2, // USDT
    },
  },
};

// TODO: Is this global or per chain?
// Rewards
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