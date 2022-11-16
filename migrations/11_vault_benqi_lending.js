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
const VaultBenqiLendingAVAX = artifacts.require("VaultBenqiLendingAVAX");
const VaultZorro = artifacts.require("VaultZorro");
// Libraries
const VaultLibrary = artifacts.require('VaultLibrary');
const VaultLendingLibrary = artifacts.require('VaultLendingLibrary');
// Other contracts
const ZorroController = artifacts.require("ZorroController");
const ZorroControllerXChain = artifacts.require("ZorroControllerXChain");
const Zorro = artifacts.require("Zorro");
// Mocks
const MockVaultBenqiLending = artifacts.require('MockVaultBenqiLending');
const MockBenqiLendingPool = artifacts.require('MockBenqiLendingPool');
const MockBenqiTokenSaleDistributor = artifacts.require('MockBenqiTokenSaleDistributor');
const MockBenqiUnitroller = artifacts.require('MockBenqiUnitroller');
// Price feeds
const ZORPriceFeed = artifacts.require('ZORPriceFeed');

module.exports = async function (deployer, network, accounts) {
  /* Production */

  // Token addresses
  const qiToken = '0x8729438EB15e2C8B576fCc6AeCdA6A148776C0F5';

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
      keyAddresses: {
        govAddress: accounts[0],
        zorroControllerAddress: zorroController.address,
        zorroXChainController: zorroControllerXChain.address,
        ZORROAddress: zorro.address,
        zorroStakingVault: vaultZorro.address,
        wantAddress: wavaxOnAvax,
        token0Address: wavaxOnAvax,
        token1Address: zeroAddress, // Single token only
        earnedAddress: qiToken,
        farmContractAddress: '0x77533A0b34cd9Aa135EBE795dc40666Ca295C16D', // QiTokenSaleDistributor
        rewardsAddress: accounts[2], // TODO: Set this and all other rewards addresses to a proper hard coded one
        poolAddress: '0x5C0401e81Bc07Ca70fAD469b451682c0d747Ef1c', // qiAVAX QiToken pool
        uniRouterAddress,
        // TODO: Fix all the blank zorroLPPool values
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
        token0PriceFeed: '0x0A77230d17318075983913bC2145DB16C7366156', // Chainlink AVAX feed 
        token1PriceFeed: zeroAddress, // Single token
        earnTokenPriceFeed: '0x36E039e6391A5E7A7267650979fdf613f659be5D', // Chainlink Qi feed
        ZORPriceFeed: zorPriceFeed.address, // ZOR
        lpPoolOtherTokenPriceFeed: priceFeeds.priceFeedLPPoolOtherToken,
        stablecoinPriceFeed: priceFeeds.priceFeedStablecoin,
      },
      comptrollerAddress: '0x486Af39519B4Dc9a7fCcd318217352830E8AD9b4', // Benqi Comptroller
    };
    // Deploy master contract
    await deployer.link(VaultLibrary, [VaultLendingLibrary]);
    await deployer.deploy(VaultLendingLibrary);
    await deployer.link(VaultLendingLibrary, [VaultBenqiLendingAVAX]);
    await deployer.link(VaultLendingLibrary, [VaultBenqiLendingAVAX]);
    await deployProxy(
      VaultBenqiLendingAVAX, 
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
    // Mocks
    await deployer.deploy(MockBenqiLendingPool);
    await deployer.deploy(MockBenqiTokenSaleDistributor);
    await deployer.deploy(MockBenqiUnitroller);

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
      fees: testVaultParams.keyAddresses,
      priceFeeds: testVaultParams.priceFeeds,
      comptrollerAddress: zeroAddress,
    };
    await deployer.link(VaultLibrary, [MockVaultBenqiLending]);
    await deployer.link(VaultLendingLibrary, [MockVaultBenqiLending]);
    await deployProxy(
      MockVaultBenqiLending,
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
