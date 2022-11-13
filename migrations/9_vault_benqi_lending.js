// Upgrades
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
// Vaults
const VaultApeLending = artifacts.require("VaultApeLending");
const VaultApeLendingETH = artifacts.require("VaultApeLendingETH");
const VaultZorro = artifacts.require("VaultZorro");
// Libraries
const VaultLibrary = artifacts.require('VaultLibrary');
const VaultLibraryAlpaca = artifacts.require('VaultLendingLibrary');
// Other contracts
const ZorroController = artifacts.require("ZorroController");
const ZorroControllerXChain = artifacts.require("ZorroControllerXChain");
const MockPriceAggZORLP = artifacts.require("MockPriceAggZORLP");
const Zorro = artifacts.require("Zorro");
// Get key params
const {getKeyParams, devNets} = require('../chains');
const zeroAddress = '0x0000000000000000000000000000000000000000';

module.exports = async function (deployer, network, accounts) {
  // Deployed contracts
  const vaultZorro = await VaultZorro.deployed();
  const zorroController = await ZorroController.deployed();
  const zorroControllerXChain = await ZorroControllerXChain.deployed();
  const zorro = await Zorro.deployed();

  // Unpack keyParams
  const {
    defaultStablecoin,
    uniRouterAddress,
    zorroLPPoolOtherToken,
    priceFeeds,
    vaults,
  } = getKeyParams(accounts, zorro.address)['bsc'];

  let mockPriceAggZORLP;
  
  if (devNets.includes(network)) {
    // Deploy Mock ZOR price feed if necessary
    if (!MockPriceAggZORLP.hasNetwork(network)) {
      await deployer.deploy(MockPriceAggZORLP, uniRouterAddress, zorro.address, zorroLPPoolOtherToken, defaultStablecoin);
    }
    mockPriceAggZORLP = await MockPriceAggZORLP.deployed();
  }

  const deployableNetworks = [
    'bsc',
    'bscfork',
    ...devNets,
  ];
  // TODO: This needs to be filled out in much more detail. Started but incomplete!

  if (deployableNetworks.includes(network)) {
    // Init values 
    // TODO: Create for each chain. Also, should use specific name of contract, not generic. E.g. for 'bsc/bscfork', should be AlpacaBTCB or whatever
    const initVal = {
      pid: vaults.pid, 
      isHomeChain: false,
      keyAddresses: {
        govAddress: accounts[0],
        zorroControllerAddress: zorroController.address,
        zorroXChainController: zorroControllerXChain.address,
        ZORROAddress: zorro.address,
        zorroStakingVault: vaultZorro.address,
        wantAddress: '0x2170ed0880ac9a755fd29b2688956bd959f933f8', // FILL
        token0Address: '0x2170ed0880ac9a755fd29b2688956bd959f933f8', // FILL
        token1Address: zeroAddress,
        earnedAddress: '0x603c7f932ED1fc6575303D8Fb018fDCBb0f39a95', // FILL - Alpaca
        farmContractAddress: '0x5CB93C0AdE6B7F2760Ec4389833B0cCcb5e4efDa', // FILL - Alpaca Masterchef (Fairlaunch)
        rewardsAddress: accounts[2],
        poolAddress: '0xaA1b1E1f251610aE10E4D553b05C662e60992EEd', // TODO FILL Alpaca vault
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
        token0PriceFeed: zeroAddress, 
        token1PriceFeed: zeroAddress, // Single token
        earnTokenPriceFeed: zeroAddress, // Alpaca
        ZORPriceFeed: zeroAddress, // ZOR
        lpPoolOtherTokenPriceFeed: priceFeeds.priceFeedLPPoolOtherToken,
        stablecoinPriceFeed: priceFeeds.priceFeedStablecoin,
      }
    };
    // Deploy master contract
    await deployer.link(VaultLibrary, [VaultLendingLibrary]);
    await deployer.deploy(VaultLendingLibrary);
    await deployer.link(VaultLendingLibrary, [VaultApeLendingETH]);
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
};