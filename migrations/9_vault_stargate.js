// Upgrades
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
// Vaults
const StargateUSDCOnAVAX = artifacts.require("StargateUSDCOnAVAX");
const VaultZorro = artifacts.require("VaultZorro");
// Libraries
const VaultLibrary = artifacts.require('VaultLibrary');
// Other contracts 
const MockPriceAggZORLP = artifacts.require("MockPriceAggZORLP");
const MockPriceAggSTG = artifacts.require("MockPriceAggSTG");
const ZorroController = artifacts.require("ZorroController");
const ZorroControllerXChain = artifacts.require("ZorroControllerXChain");
const Zorro = artifacts.require("Zorro");
const TraderJoe_ZOR_WAVAX = artifacts.require("TraderJoe_ZOR_WAVAX");
// Get key params
const { getKeyParams, getSynthNetwork, devNets } = require('../chains');
const zeroAddress = '0x0000000000000000000000000000000000000000';
const wavax = '0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7';

// TODO: This needs to be filled out in much more detail. Started but incomplete!
module.exports = async function (deployer, network, accounts) {
  // Deployed contracts
  const vaultZorro = await VaultZorro.deployed();
  const zorroController = await ZorroController.deployed();
  const zorroControllerXChain = await ZorroControllerXChain.deployed();
  const zorro = await Zorro.deployed();
  const tjzavax = await TraderJoe_ZOR_WAVAX.deployed();

  // Unpack keyParams
  const {
    defaultStablecoin,
    uniRouterAddress,
    zorroLPPoolOtherToken,
    USDCToZorroPath,
    USDCToZorroLPPoolOtherTokenPath,
    priceFeeds,
    vaults,
    bridge,
  } = getKeyParams(accounts)[getSynthNetwork(network)];

  let mockPriceAggZORLP, mockPriceAggSTG;
  
  if (devNets.includes(network)) {
    // Deploy Mock ZOR price feed if necessary
    if (!MockPriceAggZORLP.hasNetwork(network)) {
      await deployer.deploy(MockPriceAggZORLP, uniRouterAddress, zorro.address, zorroLPPoolOtherToken, defaultStablecoin);
    }
    mockPriceAggZORLP = await MockPriceAggZORLP.deployed();

    // Same for STG
    if (!MockPriceAggSTG.hasNetwork(network)) {
      await deployer.deploy(MockPriceAggSTG, uniRouterAddress, bridge.tokenSTG, wavax, defaultStablecoin);
    }
    mockPriceAggSTG = await MockPriceAggSTG.deployed();
  }

  const zorroLPPool = await tjzavax.poolAddress.call();
  const sgUSDCPool = '0x1205f31718499dBf1fCa446663B532Ef87481fe1';
  const sgLPStaking = '0x8731d54E9D02c286767d56ac03e8037C07e01e98';

  // Init values 
  const initVal = {
    pid: 0,
    isHomeChain: ['avax', 'ganachecloud'].includes(network),
    isFarmable: true,
    keyAddresses: {
      govAddress: accounts[0],
      zorroControllerAddress: zorroController.address,
      zorroXChainController: zorroControllerXChain.address,
      ZORROAddress: zorro.address,
      zorroStakingVault: vaultZorro.address,
      wantAddress: sgUSDCPool,
      token0Address: defaultStablecoin,
      token1Address: zeroAddress,
      earnedAddress: bridge.tokenSTG,
      farmContractAddress: sgLPStaking,
      rewardsAddress: accounts[2],
      poolAddress: sgUSDCPool,
      uniRouterAddress,
      zorroLPPool,
      zorroLPPoolOtherToken,
      tokenUSDCAddress: defaultStablecoin,
    },
    earnedToZORROPath: [
      bridge.tokenSTG,
      defaultStablecoin,
      wavax,
      zorro.address,
    ],
    earnedToToken0Path: [
      bridge.tokenSTG,
      defaultStablecoin,
    ],
    USDCToToken0Path: [], // USDC IS token0, so no need for a path
    earnedToZORLPPoolOtherTokenPath: [
      bridge.tokenSTG,
      defaultStablecoin,
      wavax,
    ],
    earnedToUSDCPath: [
      bridge.tokenSTG,
      defaultStablecoin,
    ],
    fees: vaults.fees,
    priceFeeds: {
      token0PriceFeed: priceFeeds.priceFeedStablecoin,
      token1PriceFeed: zeroAddress,
      earnTokenPriceFeed: mockPriceAggSTG.address,
      ZORPriceFeed: devNets.includes(network) ? mockPriceAggZORLP.address : priceFeeds.priceFeedZOR,
      lpPoolOtherTokenPriceFeed: priceFeeds.priceFeedLPPoolOtherToken,
      stablecoinPriceFeed: priceFeeds.priceFeedStablecoin,
    },
    tokenSTG: bridge.tokenSTG,
    stargateRouter: bridge.stargateRouter,
    stargatePoolId: bridge.stargatePoolId,
  };

  // Deploy master contract
  await deployer.link(VaultLibrary, [StargateUSDCOnAVAX]);
  await deployProxy(
    StargateUSDCOnAVAX, 
    [
      accounts[0], 
      initVal,
    ], {
      deployer,
      unsafeAllow: [
        'external-library-linking',
      ],
    });
};