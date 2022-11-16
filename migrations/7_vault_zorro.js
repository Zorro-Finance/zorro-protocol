// Upgrades
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
// Get key params
const { 
  getKeyParams, 
  getSynthNetwork,
  testNets,
  homeNetworks,
  zeroAddress,
  wavaxOnAvax,
} = require('../chains');

// Libraries
const VaultLibrary = artifacts.require("VaultLibrary");
// Vaults
const VaultZorro = artifacts.require("VaultZorro");
// Other contracts
const PoolPublic = artifacts.require("PoolPublic");
const ZorroController = artifacts.require("ZorroController");
const ZorroControllerXChain = artifacts.require("ZorroControllerXChain");
const Zorro = artifacts.require("Zorro");
// Price feeds
const ZORPriceFeed = artifacts.require("ZORPriceFeed");
// Mocks
const MockVaultZorro = artifacts.require("MockVaultZorro");

module.exports = async function (deployer, network, accounts) {
  /* Production */

  // Deployed contracts
  const zorroController = await ZorroController.deployed();
  const zorroControllerXChain = await ZorroControllerXChain.deployed();
  const poolPublic = await PoolPublic.deployed();
  const zorro = await Zorro.deployed();

  // Unpack keyParams
  const {
    defaultStablecoin,
    uniRouterAddress,
    zorroLPPoolOtherToken,
    priceFeeds,
    vaults,
  } = getKeyParams(accounts, zorro.address)[getSynthNetwork(network)];
  
  if (homeNetworks.includes(network)) {
    /* Home chain */

    // Deploy
    const zorPriceFeed = await ZORPriceFeed.deployed();

    // Init values 
    const initVal = {
      pid: vaults.pid,
      keyAddresses: {
        govAddress: accounts[0],
        zorroControllerAddress: zorroController.address,
        zorroXChainController: zorroControllerXChain.address,
        ZORROAddress: zorro.address,
        zorroStakingVault: zeroAddress, // not needed, so use Zero address
        wantAddress: zorro.address,
        token0Address: zorro.address,
        token1Address: zeroAddress, // not needed; use zero address
        earnedAddress: zeroAddress, // not needed; use zero address
        farmContractAddress: zeroAddress, // not needed; use zero address
        rewardsAddress: accounts[2], // not needed; use zero address
        poolAddress: zeroAddress, // not needed; use zero address
        uniRouterAddress,
        zorroLPPool: zeroAddress, // needs to be filled in with appropriate value later!
        zorroLPPoolOtherToken,
        defaultStablecoin,
      },
      stablecoinToToken0Path: [defaultStablecoin, wavaxOnAvax, zorro.address],
      fees: vaults.fees,
      priceFeeds: {
        token0PriceFeed: zorPriceFeed,
        token1PriceFeed: zeroAddress,
        earnTokenPriceFeed: zeroAddress,
        ZORPriceFeed: zorPriceFeed,
        lpPoolOtherTokenPriceFeed: priceFeeds.priceFeedLPPoolOtherToken,
        stablecoinPriceFeed: priceFeeds.priceFeedStablecoin,
      },
    };
    
    // Deploy
    // TODO: For this and all ownable contracts, make sure to set an account that we can always have access to. 
    // https://ethereum.stackexchange.com/questions/17441/how-to-choose-an-account-to-deploy-a-contract-in-truffle 
    await deployer.deploy(VaultLibrary);
    await deployer.link(VaultLibrary, [VaultZorro]);
    await deployProxy(VaultZorro,
      [
        accounts[0],
        initVal,
      ],
      {
        deployer,
        unsafeAllow: ['external-library-linking'],
      }
    );

    // Update ZorroController
    const vaultZorro = await VaultZorro.deployed();
    await zorroController.setZorroContracts(poolPublic.address, vaultZorro.address);
  } else {
    console.log('Not home chain. Skipping Zorro Single Staking Vault creation');
  }

  /* Tests */

  // Allowed networks: Test/dev only
  const testVaultParams = getKeyParams(accounts, zorro.address)['test'];

  if (testNets.includes(network)) {
    const initVal = {
      pid: 0,
      keyAddresses: testVaultParams.keyAddresses,
      stablecoinToToken0Path: [],
      fees: testVaultParams.fees,
      priceFeeds: testVaultParams.priceFeeds,
    };
    await deployer.link(VaultLibrary, [MockVaultZorro]);
    await deployProxy(
      MockVaultZorro,
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