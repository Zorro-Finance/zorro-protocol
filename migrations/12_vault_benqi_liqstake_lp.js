// Upgrades
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
// Get key params
const {
  getKeyParams, 
  devNets, 
  zeroAddress,
  testNets,
  wavaxOnAvax,
} = require('../chains');

// Vaults
const VaultBenqiAVAXLiqStakeLP = artifacts.require("VaultBenqiAVAXLiqStakeLP");
const VaultZorro = artifacts.require("VaultZorro");
// Libraries
const VaultLibrary = artifacts.require('VaultLibrary');
const VaultLiqStakeLPLibrary = artifacts.require('VaultLiqStakeLPLibrary');
const VaultBenqiLiqStakeLPLibrary = artifacts.require('VaultBenqiLiqStakeLPLibrary');
// Other contracts
const ZorroController = artifacts.require("ZorroController");
const ZorroControllerXChain = artifacts.require("ZorroControllerXChain");
const Zorro = artifacts.require("Zorro");
// Price feeds
const ZORPriceFeed = artifacts.require("ZORPriceFeed");
// Mocks
const MockVaultBenqiLiqStakeLP = artifacts.require('MockVaultBenqiLiqStakeLP');
const MockBenqiLiqStakePoolAVAX = artifacts.require('MockBenqiLiqStakePoolAVAX');

module.exports = async function (deployer, network, accounts) {
  /* Production */

  // Token addresses
  const sAVAXToken = '0x2b2C81e08f1Af8835a78Bb2A90AE924ACE0eA4bE';
  const sAVAXwAVAXLPToken = '0x2b2c81e08f1af8835a78bb2a90ae924ace0ea4be';
  const JOEToken = '0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd';

  // Deployed contracts
  const vaultZorro = await VaultZorro.deployed();
  const zorroController = await ZorroController.deployed();
  const zorroControllerXChain = await ZorroControllerXChain.deployed();
  const zorro = await Zorro.deployed();
  const zorPriceFeed = await ZORPriceFeed.deployed();

  // Unpack keyParams
  const {
    defaultStablecoin,
    uniRouterAddress,
    zorroLPPoolOtherToken,
    priceFeeds,
    vaults,
  } = getKeyParams(accounts, zorro.address)['bsc'];

  const deployableNetworks = [
    'bsc',
    'bscfork',
    ...devNets,
  ];

  if (deployableNetworks.includes(network)) {
    // Init values 
    const initVal = {
      pid: vaults.pid, 
      isHomeChain: false,
      isFarmable: false,
      keyAddresses: {
        govAddress: accounts[0],
        zorroControllerAddress: zorroController.address,
        zorroXChainController: zorroControllerXChain.address,
        ZORROAddress: zorro.address,
        zorroStakingVault: vaultZorro.address,
        wantAddress: sAVAXwAVAXLPToken,
        token0Address: wavaxOnAvax,
        token1Address: zeroAddress,
        earnedAddress: JOEToken,
        farmContractAddress: '0x188bED1968b795d5c9022F6a0bb5931Ac4c18F00', // JOE Masterchef v3
        rewardsAddress: accounts[2],
        poolAddress: sAVAXwAVAXLPToken,
        uniRouterAddress,
        zorroLPPool: zeroAddress,
        zorroLPPoolOtherToken,
        defaultStablecoin,
      },
      liquidStakeToken: sAVAXToken,
      liquidStakingPool: zeroAddress, // Unused
      // TODO: Need to fill out all these paths, on all vaults!
      earnedToZORROPath: [], 
      earnedToToken0Path: [],
      stablecoinToToken0Path: [],
      earnedToZORLPPoolOtherTokenPath: [],
      earnedToStablecoinPath: [],
      stablecoinToZORROPath: [],
      stablecoinToLPPoolOtherTokenPath: [],
      fees: vaults.fees,
      priceFeeds: {
        token0PriceFeed: '0x0A77230d17318075983913bC2145DB16C7366156', // Chainlink AVAX price feed 
        token1PriceFeed: zeroAddress, // Single token
        earnTokenPriceFeed: '0x02D35d3a8aC3e1626d3eE09A78Dd87286F5E8e3a', // Chainlink JOE price feed
        ZORPriceFeed: zorPriceFeed.address,
        lpPoolOtherTokenPriceFeed: priceFeeds.priceFeedLPPoolOtherToken,
        stablecoinPriceFeed: priceFeeds.priceFeedStablecoin,
      }
    };
    // Deploy master contract
    await deployer.link(VaultLibrary, [VaultLiqStakeLPLibrary]);
    await deployer.deploy(VaultLiqStakeLPLibrary);
    await deployer.link(VaultLiqStakeLPLibrary, [VaultBenqiAVAXLiqStakeLP]);
    await deployer.link(VaultLibrary, [VaultBenqiAVAXLiqStakeLP]);

    await deployer.link(VaultLibrary, [VaultBenqiLiqStakeLPLibrary]);
    await deployer.link(VaultLiqStakeLPLibrary, [VaultBenqiLiqStakeLPLibrary]);
    await deployer.deploy(VaultBenqiLiqStakeLPLibrary);
    await deployer.link(VaultBenqiLiqStakeLPLibrary, [VaultBenqiAVAXLiqStakeLP]);

    await deployProxy(
      VaultBenqiAVAXLiqStakeLP, 
      [
        accounts[0], 
        initVal,
      ], 
      {
        deployer,
        unsafeAllow: [
          'external-library-linking',
        ],
      });
  } else {
    console.log('Not on an allowed chain. Skipping...');
  }

  /* Tests */

  // Allowed networks: Test/dev only
  const testVaultParams = getKeyParams(accounts, zorro.address).test.vaults;

  if (testNets.includes(network)) {
    // Mocks
    await deployer.deploy(MockBenqiLiqStakePoolAVAX);
    
    // VaultBenqiLiqStakeLP
    const initVal = {
      pid: 0,
      isHomeChain: true,
      keyAddresses: testVaultParams,
      liquidStakeToken: zeroAddress,
      liquidStakingPool: zeroAddress,
      earnedToZORROPath: [],
      earnedToToken0Path: [],
      stablecoinToToken0Path: [],
      earnedToZORLPPoolOtherTokenPath: [],
      earnedToStablecoinPath: [],
      stablecoinToZORROPath: [],
      stablecoinToLPPoolOtherTokenPath: [],
      fees: testVaultParams.fees,
      priceFeeds: testVaultParams.priceFeeds,
    };
    await deployer.link(VaultLibrary, [VaultLiqStakeLPLibrary]);
    await deployer.link(VaultLiqStakeLPLibrary, [VaultBenqiLiqStakeLPLibrary]);
    await deployer.link(VaultBenqiLiqStakeLPLibrary, [MockVaultBenqiLiqStakeLP]);
    await deployProxy(
      MockVaultBenqiLiqStakeLP,
      [
        accounts[0],
        initVal
      ], {
      deployer,
      unsafeAllow: [
        'external-library-linking',
      ],
    });
  }
};