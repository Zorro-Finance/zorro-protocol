// Upgrades
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
// Get key params
const { 
  getKeyParams, 
  getSynthNetwork, 
  testNets,
  wavaxOnAvax,
} = require('../helpers/chains');

// Vaults
const StargateUSDCOnAVAX = artifacts.require("StargateUSDCOnAVAX");
const VaultZorro = artifacts.require("VaultZorro");
// Libraries
const VaultLibrary = artifacts.require('VaultLibrary');
// Other contracts 
const ZorroController = artifacts.require("ZorroController");
const ZorroControllerXChain = artifacts.require("ZorroControllerXChain");
const Zorro = artifacts.require("Zorro");
const TraderJoe_ZOR_WAVAX = artifacts.require("TraderJoe_ZOR_WAVAX");
// Price feeds
const ZORPriceFeed = artifacts.require("ZORPriceFeed");
const STGPriceFeed = artifacts.require("STGPriceFeed");
// Mocks
const MockVaultStargate = artifacts.require("MockVaultStargate");
const MockStargateRouter = artifacts.require('MockStargateRouter');
const MockStargatePool = artifacts.require('MockStargatePool');
const MockStargateLPStaking = artifacts.require('MockStargateLPStaking');
const MockSTGToken = artifacts.require('MockSTGToken');
const MockLayerZeroEndpoint = artifacts.require('MockLayerZeroEndpoint');


// TODO: This needs to be filled out in much more detail. Started but incomplete!
module.exports = async function (deployer, network, accounts) {
  /* Production */

  // Deployed contracts
  const vaultZorro = await VaultZorro.deployed();
  const zorroController = await ZorroController.deployed();
  const zorroControllerXChain = await ZorroControllerXChain.deployed();
  const zorro = await Zorro.deployed();
  let tjzavax;
  if (TraderJoe_ZOR_WAVAX.hasNetwork(network)) {
    tjzavax = await TraderJoe_ZOR_WAVAX.deployed();
  }
  const zorPriceFeed = await ZORPriceFeed.deployed();
  const stgPriceFeed = await STGPriceFeed.deployed();

  // Unpack keyParams
  const {
    defaultStablecoin,
    uniRouterAddress,
    zorroLPPoolOtherToken,
    priceFeeds,
    vaults,
    bridge,
  } = getKeyParams(accounts)[getSynthNetwork(network)];

  const zorroLPPool = tjzavax ? await tjzavax.poolAddress.call() : zeroAddress;
  const sgUSDCPool = '0x1205f31718499dBf1fCa446663B532Ef87481fe1';
  const sgLPStaking = '0x8731d54E9D02c286767d56ac03e8037C07e01e98';

  // Init values 
  const initVal = {
    pid: 0,
    isHomeChain: ['avax', 'avaxfork'].includes(network),
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
      treasury: accounts[2],
      poolAddress: sgUSDCPool,
      uniRouterAddress,
      zorroLPPool,
      zorroLPPoolOtherToken,
      defaultStablecoin,
    },
    earnedToZORROPath: [
      bridge.tokenSTG,
      defaultStablecoin,
      wavaxOnAvax,
      zorro.address,
    ],
    earnedToToken0Path: [
      bridge.tokenSTG,
      defaultStablecoin,
    ],
    stablecoinToToken0Path: [], // USDC IS token0, so no need for a path
    earnedToZORLPPoolOtherTokenPath: [
      bridge.tokenSTG,
      defaultStablecoin,
      wavaxOnAvax,
    ],
    earnedToStablecoinPath: [
      bridge.tokenSTG,
      defaultStablecoin,
    ],
    fees: vaults.fees,
    priceFeeds: {
      token0PriceFeed: priceFeeds.priceFeedStablecoin,
      token1PriceFeed: zeroAddress,
      earnTokenPriceFeed: stgPriceFeed.address,
      ZORPriceFeed: zorPriceFeed.address,
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

  /* Tests */

  // Allowed networks: Test/dev only
  const testVaultParams = getKeyParams(accounts, zorro.address).test.vaults;

  if (testNets.includes(network)) {
    // Mocks
    await deployer.deploy(MockStargateRouter);
    await deployer.deploy(MockStargatePool);
    await deployer.deploy(MockStargateLPStaking);
    await deployer.deploy(MockSTGToken);
    await deployer.deploy(MockLayerZeroEndpoint);

    // VaultStargate
    const initVal = {
      pid: 0,
      isHomeChain: true,
      isFarmable: true,
      keyAddresses: testVaultParams.keyAddresses,
      earnedToZORROPath: [],
      earnedToToken0Path: [],
      stablecoinToToken0Path: [],
      earnedToZORLPPoolOtherTokenPath: [],
      earnedToStablecoinPath: [],
      fees: testVaultParams.fees,
      priceFeeds: testVaultParams.priceFeeds,
      tokenSTG: zeroAddress,
      stargateRouter: zeroAddress,
      stargatePoolId: 0
    };
    await deployer.link(VaultLibrary, [MockVaultStargate]);
    await deployProxy(
      MockVaultStargate,
      [
        accounts[0],
        initVal,
      ], {
      deployer,
      unsafeAllow: [
        'external-library-linking',
      ],
    });
  }
};