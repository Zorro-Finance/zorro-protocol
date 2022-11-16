// Upgrades
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
// Get key params
const {
  getKeyParams, 
  devNets,
  zeroAddress,
  testNets,
} = require('../chains');

// Vaults
const VaultApeLendingETH = artifacts.require("VaultApeLendingETH");
const VaultZorro = artifacts.require("VaultZorro");
// Libraries
const VaultLibrary = artifacts.require('VaultLibrary');
const VaultLendingLibrary = artifacts.require('VaultLendingLibrary');
// Other contracts
const ZorroController = artifacts.require("ZorroController");
const ZorroControllerXChain = artifacts.require("ZorroControllerXChain");
const Zorro = artifacts.require("Zorro");
// Mocks
const MockVaultApeLending = artifacts.require("MockVaultApeLending");
const MockApeLendingPool = artifacts.require("MockApeLendingPool");
const MockApeLendingRainMaker = artifacts.require("MockApeLendingRainMaker");
const MockApeLendingUnitroller = artifacts.require("MockApeLendingUnitroller");
// Price feeds
const ZORPriceFeed = artifacts.require("ZORPriceFeed");
const BANANAPriceFeed = artifacts.require("BANANAPriceFeed");

module.exports = async function (deployer, network, accounts) {
  /* Production */

  // Token addresses
  const ethToken = '0x2170ed0880ac9a755fd29b2688956bd959f933f8';
  const bananaToken = '0x603c7f932ED1fc6575303D8Fb018fDCBb0f39a95';

  // Deployed contracts
  const vaultZorro = await VaultZorro.deployed();
  const zorroController = await ZorroController.deployed();
  const zorroControllerXChain = await ZorroControllerXChain.deployed();
  const zorro = await Zorro.deployed();
  const zorPriceFeed = await ZORPriceFeed.deployed();
  
  await deployer.deploy(BANANAPriceFeed, uniRouterAddress, bananaToken, defaultStablecoin);
  const bananaPriceFeed = await BANANAPriceFeed.deployed();

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
      keyAddresses: {
        govAddress: accounts[0],
        zorroControllerAddress: zorroController.address,
        zorroXChainController: zorroControllerXChain.address,
        ZORROAddress: zorro.address,
        zorroStakingVault: vaultZorro.address,
        wantAddress: ethToken,
        token0Address: ethToken,
        token1Address: zeroAddress,
        earnedAddress: bananaToken,
        farmContractAddress: '0x5CB93C0AdE6B7F2760Ec4389833B0cCcb5e4efDa', // Rainmaker
        rewardsAddress: accounts[2],
        poolAddress: '0xaA1b1E1f251610aE10E4D553b05C662e60992EEd', // ETH lending pool
        uniRouterAddress,
        zorroLPPool: zeroAddress,
        zorroLPPoolOtherToken,
        defaultStablecoin,
      },
      earnedToZORROPath: [], 
      earnedToToken0Path: [],
      stablecoinToToken0Path: [],
      earnedToZORLPPoolOtherTokenPath: [],
      earnedToStablecoinPath: [],
      stablecoinToZORROPath: [],
      stablecoinToLPPoolOtherTokenPath: [],
      fees: vaults.fees,
      priceFeeds: {
        token0PriceFeed: '0x9ef1B8c0E4F7dc8bF5719Ea496883DC6401d5b2e', // ETH Chainlink feed
        token1PriceFeed: zeroAddress, // Single token
        earnTokenPriceFeed: bananaPriceFeed, // Banana
        ZORPriceFeed: zorPriceFeed.address, // ZOR
        lpPoolOtherTokenPriceFeed: priceFeeds.priceFeedLPPoolOtherToken,
        stablecoinPriceFeed: priceFeeds.priceFeedStablecoin,
      },
      comptrollerAddress: '0xAD48B2C9DC6709a560018c678e918253a65df86e', // Apelending (Ola) Comptroller proxy address 
    };
    // Deploy master contract
    await deployer.link(VaultLibrary, [VaultLendingLibrary]);
    await deployer.deploy(VaultLendingLibrary);
    await deployer.link(VaultLibrary, [VaultApeLendingETH]);
    await deployer.link(VaultLendingLibrary, [VaultApeLendingETH]);
    await deployProxy(
      VaultApeLendingETH, 
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
  if (testNets.includes(network)) {
    // Deploy mocks
    await deployer.deploy(MockApeLendingPool);
    await deployer.deploy(MockApeLendingRainMaker);
    await deployer.deploy(MockApeLendingUnitroller);

    // Deploy vault
    const testVaultParams = getKeyParams(accounts, zorro.address).test.vaults;
    const initVal = {
      pid: 0,
      isHomeChain: true,
      keyAddresses: testVaultParams.keyAddresses,
      earnedToZORROPath: [],
      earnedToToken0Path: [],
      stablecoinToToken0Path: [],
      earnedToZORLPPoolOtherTokenPath: [],
      earnedToStablecoinPath: [],
      stablecoinToZORROPath: [],
      stablecoinToLPPoolOtherTokenPath: [],
      fees: testVaultParams.fees,
      priceFeeds: testVaultParams.priceFeeds,
      comptrollerAddress: zeroAddress,
    };
    await deployer.link(VaultLibrary, [MockVaultApeLending]);
    await deployer.link(VaultLendingLibrary, [MockVaultApeLending]);
    await deployProxy(
      MockVaultApeLending,
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