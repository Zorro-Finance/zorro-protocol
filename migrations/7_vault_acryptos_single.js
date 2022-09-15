// Upgrades
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
// Vaults
const VaultAcryptosSingle = artifacts.require("VaultAcryptosSingle");
const VaultZorro = artifacts.require("VaultZorro");
// Libraries
const VaultLibrary = artifacts.require('VaultLibrary');
const VaultLibraryAcryptosSingle = artifacts.require('VaultLibraryAcryptosSingle');
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
    USDCToZorroPath,
    USDCToZorroLPPoolOtherTokenPath,
    priceFeeds,
    vaults,
    tokenBUSDPriceFeed,
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
    // TODO: Create for each chain. Also, should use specific name of contract, not generic. E.g. for 'bsc/bscfork', should be AcryptosBNB or whatever
    const initVal = {
      pid: vaults.pid, 
      isHomeChain: false,
      keyAddresses: {
        govAddress: accounts[0],
        zorroControllerAddress: zorroController.address,
        zorroXChainController: zorroControllerXChain.address,
        ZORROAddress: zorro.address,
        zorroStakingVault: vaultZorro.address,
        wantAddress: '0x0E3E97653fE81D771a250b03AF2b5cf294a6dE62', // FILL
        token0Address: '0x7083609fCE4d1d8Dc0C979AAb8c869Ea2C873402', // FILL
        token1Address: zeroAddress,
        earnedAddress: '0x4197C6EF3879a08cD51e5560da5064B773aa1d29', // FILL - ACS
        farmContractAddress: '0xeaE1425d8ed46554BF56968960e2E567B49D0BED', // FILL - Acryptos Masterchef
        rewardsAddress: accounts[2],
        poolAddress: '0x0E3E97653fE81D771a250b03AF2b5cf294a6dE62', // FILL
        uniRouterAddress,
        zorroLPPool: zeroAddress,
        zorroLPPoolOtherToken,
        tokenUSDCAddress: defaultStablecoin,
      },
      earnedToZORROPath: [], 
      earnedToToken0Path: [],
      USDCToToken0Path: [],
      earnedToZORLPPoolOtherTokenPath: [],
      earnedToUSDCPath: [],
      BUSDToToken0Path: [],
      BUSDToZORROPath: [],
      BUSDToLPPoolOtherTokenPath: [],
      fees: vaults.fees,
      priceFeeds: {
        token0PriceFeed: zeroAddress, 
        token1PriceFeed: zeroAddress, // Single token
        earnTokenPriceFeed: zeroAddress, // ACS
        ZORPriceFeed: zeroAddress, // ZOR
        lpPoolOtherTokenPriceFeed: priceFeeds.priceFeedLPPoolOtherToken,
        stablecoinPriceFeed: priceFeeds.priceFeedStablecoin,
      },
      tokenBUSDPriceFeed,
    };
    // Deploy master contract
    await deployer.deploy(VaultLibraryAcryptosSingle);
    await deployer.link(VaultLibraryAcryptosSingle, [VaultAcryptosSingle]);
    await deployer.link(VaultLibrary, [VaultAcryptosSingle]);
    await deployProxy(
      VaultAcryptosSingle, 
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