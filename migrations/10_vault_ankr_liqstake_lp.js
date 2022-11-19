// Upgrades
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
// Get key params
const {
  getKeyParams, 
  devNets,
  testNets,
} = require('../chains');

// Vaults
const VaultZorro = artifacts.require("VaultZorro");
const VaultAnkrBNBLiqStakeLP = artifacts.require("VaultAnkrBNBLiqStakeLP");
// Libraries
const VaultLibrary = artifacts.require('VaultLibrary');
const VaultAnkrLiqStakeLPLibrary = artifacts.require('VaultAnkrLiqStakeLPLibrary');
// Other contracts
const ZorroController = artifacts.require("ZorroController");
const ZorroControllerXChain = artifacts.require("ZorroControllerXChain");
const Zorro = artifacts.require("Zorro");
// Mocks
const MockVaultAnkrLiqStakeLP = artifacts.require('MockVaultAnkrLiqStakeLP');
const MockAnkrLiqStakePoolBNB = artifacts.require('MockAnkrLiqStakePoolBNB');

module.exports = async function (deployer, network, accounts) {
  /* Production */

  // Deployed contracts
  const vaultZorro = await VaultZorro.deployed();
  const zorroController = await ZorroController.deployed();
  const zorroControllerXChain = await ZorroControllerXChain.deployed();
  const zorro = await Zorro.deployed();

  // Token addresses
  const bnbToken = '0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c';
  const cakeToken = '0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82';

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
    // TODO: Create for each chain. Also, should use specific name of contract, not generic. E.g. for 'bsc/bscfork', should be AlpacaBTCB or whatever
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
        wantAddress: '0x0E3E97653fE81D771a250b03AF2b5cf294a6dE62', // FILL
        token0Address: bnbToken,
        token1Address: zeroAddress,
        earnedAddress: cakeToken,
        farmContractAddress: '0x73feaa1eE314F8c655E354234017bE2193C9E24E', // PCS MasterChef
        rewardsAddress: accounts[2],
        poolAddress: '0x272c2CF847A49215A3A1D4bFf8760E503A06f880', // PCS LP pool for aBNBc/WBNB
        uniRouterAddress,
        zorroLPPool: zeroAddress,
        zorroLPPoolOtherToken,
        defaultStablecoin,
      },
      liquidStakeToken: '0xE85aFCcDaFBE7F2B096f268e31ccE3da8dA2990A', // aBNBc
      liquidStakingPool: '0x66BEA595AEFD5a65799a920974b377Ed20071118', // ANKR liq staking pool
      earnedToZORROPath: [], 
      earnedToToken0Path: [],
      stablecoinToToken0Path: [],
      earnedToZORLPPoolOtherTokenPath: [],
      earnedToStablecoinPath: [],
      stablecoinToZORROPath: [],
      stablecoinToLPPoolOtherTokenPath: [],
      fees: vaults.fees,
      priceFeeds: {
        token0PriceFeed: '0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE', // Chainlink BNB price feed
        token1PriceFeed: zeroAddress, // Single token
        earnTokenPriceFeed: '0xB6064eD41d4f67e353768aA239cA86f4F73665a1', // Chainlink CAKE price feed
        ZORPriceFeed: zeroAddress, // ZOR
        lpPoolOtherTokenPriceFeed: priceFeeds.priceFeedLPPoolOtherToken,
        stablecoinPriceFeed: priceFeeds.priceFeedStablecoin,
      }
    };
    // Deploy master contract
    await deployer.link(VaultLibrary, [VaultAnkrLiqStakeLPLibrary]);
    await deployer.deploy(VaultAnkrLiqStakeLPLibrary);
    await deployer.link(VaultAnkrLiqStakeLPLibrary, [VaultAnkrBNBLiqStakeLP]);
    await deployer.link(VaultLibrary, [VaultAnkrBNBLiqStakeLP]);
    await deployProxy(
      VaultAnkrBNBLiqStakeLP, 
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
    await deployer.deploy(MockAnkrLiqStakePoolBNB);
    
    // VaultBenqiLiqStakeLP
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
    };
    await deployer.link(VaultLibrary, [VaultLiqStakeLPLibrary]);
    await deployer.link(VaultLiqStakeLPLibrary, [MockVaultAnkrLiqStakeLP]);
    await deployer.link(VaultBenqiLiqStakeLPLibrary, [MockVaultAnkrLiqStakeLP]);
    await deployProxy(
      MockVaultAnkrLiqStakeLP,
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