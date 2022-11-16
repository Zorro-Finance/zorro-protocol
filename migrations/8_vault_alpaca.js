// Upgrades
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
// Get key params
const {
  getKeyParams, 
  devNets,
  testNets,
} = require('../chains');

// Vaults
// Libraries
const VaultLibrary = artifacts.require('VaultLibrary');
const VaultLibraryAlpaca = artifacts.require('VaultLibraryAlpaca');
// Other contracts
const Zorro = artifacts.require("Zorro");
// Mocks
const MockVaultAlpaca = artifacts.require("MockVaultAlpaca");
const MockAlpacaFarm = artifacts.require('MockAlpacaFarm');
const MockAlpacaVault = artifacts.require('MockAlpacaVault');
// Price feeds
const ZORPriceFeed = artifacts.require("ZORPriceFeed");

module.exports = async function (deployer, network, accounts) {
  /* Production */

  // Deployed contracts
  const zorro = await Zorro.deployed();

  const deployableNetworks = [
    'bsc',
    'bscfork',
    ...devNets,
  ];

  if (deployableNetworks.includes(network)) {
    // No contract deployed for Alpaca at this time
  } else {
    console.log('Not on an allowed chain. Skipping...');
  }

  /* Tests */

  // Allowed networks: Test/dev only
  if (testNets.includes(network)) {
    // MockAlpaca
    const MockAlpaca = artifacts.require("MockAlpaca");
    await deployer.deploy(MockAlpaca);

    // Other mocks
    await deployer.deploy(MockAlpacaFarm);
    await deployer.deploy(MockAlpacaVault);

    // VaultAlpaca
    const testVaultParams = getKeyParams(accounts, zorro.address).test.vaults;
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
      stablecoinToZORROPath: [],
      stablecoinToLPPoolOtherTokenPath: [],
      fees: testVaultParams.fees,
      priceFeeds: testVaultParams.priceFeeds,
    };
    await deployer.link(VaultLibrary, [MockVaultAlpaca]);
    await deployer.link(VaultLibraryAlpaca, [MockVaultAlpaca]);
    await deployProxy(
      MockVaultAlpaca,
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