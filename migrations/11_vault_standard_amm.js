// Upgrades
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
// Migrations
const Migrations = artifacts.require("Migrations");
// Get key params
const { 
  getKeyParams, 
  getSynthNetwork, 
  testNets,
  wavaxOnAvax
} = require('../helpers/chains');

// Vaults
const TraderJoe_ZOR_WAVAX = artifacts.require("TraderJoe_ZOR_WAVAX");
const TraderJoe_WAVAX_USDC = artifacts.require("TraderJoe_WAVAX_USDC");
const VaultZorro = artifacts.require("VaultZorro");
// Libraries
const VaultLibrary = artifacts.require('VaultLibrary');
const VaultLibraryStandardAMM = artifacts.require('VaultLibraryStandardAMM');
// Other contracts
const ZorroController = artifacts.require("ZorroController");
const ZorroControllerXChain = artifacts.require("zorroControllerXChain");
const Zorro = artifacts.require("Zorro");
const IUniswapV2Factory = artifacts.require("IUniswapV2Factory");
const IJoeRouter02 = artifacts.require("IJoeRouter02");
// Price feeds
const ZORPriceFeed = artifacts.require("ZORPriceFeed");
// Mocks
const MockVaultStandardAMM = artifacts.require("MockVaultStandardAMM");
const MockAMMToken0 = artifacts.require("MockAMMToken0");
const MockAMMToken1 = artifacts.require("MockAMMToken1");
const MockAMMOtherLPToken = artifacts.require("MockAMMOtherLPToken");
const MockAMMFarm = artifacts.require('MockAMMFarm');
const MockLPPool = artifacts.require('MockLPPool');
const MockLPPool1 = artifacts.require('MockLPPool1');

module.exports = async function (deployer, network, accounts) {
  /* Production */

  // Token addresses
  const tokenJoe = '0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd';
  const masterChefJoe = '0x188bED1968b795d5c9022F6a0bb5931Ac4c18F00';

  // Web3
  const adapter = Migrations.interfaceAdapter;
  const { web3 } = adapter;

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
  } = getKeyParams(accounts)[getSynthNetwork(network)];
  
  let initVal;

  await deployer.deploy(VaultLibraryStandardAMM);
  
  if (['avax', 'avaxfork'].includes(network)) {
    // Create pair via Uni
    const iUniswapV2Factory = await IUniswapV2Factory.at('0x9Ad6C38BE94206cA50bb0d90783181662f0Cfa10');
    await iUniswapV2Factory.createPair(zorro.address, wavaxOnAvax);
    // Get pair address 
    const pairAddr = await iUniswapV2Factory.getPair.call(zorro.address, wavaxOnAvax);
    // Add liquidity for devnet
    if (network === 'avaxfork') {
      // Prep
      const amt = web3.utils.toWei('1000', 'ether');
      const now = Math.floor((new Date).getTime() / 1000);

      // Mint ZOR
      await zorro.setZorroController(accounts[0]);
      await zorro.mint(accounts[0], amt);
      // Set control back to ZC
      await zorro.setZorroController(zorroController.address);

      // Get router
      const router = await IJoeRouter02.at('0x60aE616a2155Ee3d9A68541Ba4544862310933d4');
      // Add liquidity
      await zorro.approve(router.address, amt);
      await router.addLiquidityAVAX(
        zorro.address,
        amt,
        (web3.utils.toBN(amt)).mul(web3.utils.toBN(9)).div(web3.utils.toBN(10)),
        (web3.utils.toBN(amt)).mul(web3.utils.toBN(9)).div(web3.utils.toBN(10)),
        accounts[0],
        now + 300,
        {value: amt}
      );
    }

    // Init vault
    initVal = {
      pid: 0,
      isHomeChain: true,
      isFarmable: false,
      keyAddresses: {
        govAddress: accounts[0],
        zorroControllerAddress: zorroController.address,
        zorroXChainController: zorroControllerXChain.address,
        ZORROAddress: zorro.address,
        zorroStakingVault: vaultZorro.address,
        wantAddress: pairAddr,
        token0Address: zorro.address,
        token1Address: wavaxOnAvax,
        earnedAddress: tokenJoe,
        farmContractAddress: masterChefJoe,
        treasury: accounts[2],
        poolAddress: pairAddr,
        uniRouterAddress,
        zorroLPPool: pairAddr,
        zorroLPPoolOtherToken,
        defaultStablecoin,
      },
      earnedToZORROPath: [tokenJoe, wavaxOnAvax, zorro.address],
      earnedToToken0Path: [tokenJoe, wavaxOnAvax, zorro.address],
      earnedToToken1Path: [tokenJoe, wavaxOnAvax],
      stablecoinToToken0Path: [defaultStablecoin, wavaxOnAvax, zorro.address],
      stablecoinToToken1Path: [defaultStablecoin, wavaxOnAvax],
      earnedToZORLPPoolOtherTokenPath: [tokenJoe, wavaxOnAvax],
      earnedToStablecoinPath: [tokenJoe, defaultStablecoin],
      fees: vaults.fees,
      priceFeeds: {
        token0PriceFeed: zorPriceFeed.address,
        token1PriceFeed: '0x0A77230d17318075983913bC2145DB16C7366156', // Chainlink AVAX price feed
        earnTokenPriceFeed: '0x02D35d3a8aC3e1626d3eE09A78Dd87286F5E8e3a', // Chainlink JOE price feed
        ZORPriceFeed: zorPriceFeed.address,
        lpPoolOtherTokenPriceFeed: priceFeeds.priceFeedLPPoolOtherToken,
        stablecoinPriceFeed: priceFeeds.priceFeedStablecoin,
      },
    };
    // TraderJoe_ZOR_WAVAX
    await deployer.link(VaultLibrary, [TraderJoe_ZOR_WAVAX]);
    await deployer.link(VaultLibraryStandardAMM, [TraderJoe_ZOR_WAVAX]);
    await deployProxy(
      TraderJoe_ZOR_WAVAX, 
      [
        accounts[0], 
        initVal,
      ], { 
        deployer,
        unsafeAllow: [
          'external-library-linking',
        ],
      });
    if (network === 'avaxfork') {
      // TraderJoe_WAVAX_USDC (for testing out farmable AMM contracts on mainnet fork)
      await deployer.link(VaultLibrary, [TraderJoe_WAVAX_USDC]);
      await deployer.link(VaultLibraryStandardAMM, [TraderJoe_WAVAX_USDC]);
      await deployProxy(
        TraderJoe_WAVAX_USDC, 
        [
          accounts[0], 
          {
            ...initVal,
            ...{
              pid: 50,
              isFarmable: true,
              keyAddresses: {
                ...initVal.keyAddresses,
                ...{
                  wantAddress: '0xf4003F4efBE8691B60249E6afbD307aBE7758adb',
                  token0Address: wavaxOnAvax,
                  token1Address: defaultStablecoin,
                  poolAddress: '0xf4003F4efBE8691B60249E6afbD307aBE7758adb',
                },
              },
              earnedToToken0Path: [tokenJoe, wavaxOnAvax, ],
              earnedToToken1Path: [tokenJoe, wavaxOnAvax, defaultStablecoin],
              stablecoinToToken0Path: [defaultStablecoin, wavaxOnAvax, ],
              stablecoinToToken1Path: [], // same token
              priceFeeds: {
                ...initVal.priceFeeds,
                ...{
                  token0PriceFeed: '0x0A77230d17318075983913bC2145DB16C7366156',
                  token1PriceFeed: priceFeeds.priceFeedStablecoin,
                },
              },
            },
          },
        ], { 
          deployer,
          unsafeAllow: [
            'external-library-linking',
          ],
        });
    }
  }

  /* Tests */

  // Allowed networks: Test/dev only
  const testVaultParams = getKeyParams(accounts, zorro.address).test.vaults;

  if (testNets.includes(network)) {
    // Mocks 
    await deployer.deploy(MockAMMToken0);
    await deployer.deploy(MockAMMToken1);
    await deployer.deploy(MockAMMOtherLPToken);
    await deployer.deploy(MockAMMFarm);
    await deployer.deploy(MockLPPool);
    await deployer.deploy(MockLPPool1);

    // VaultStandardAMM
    const initVal2 = {
      pid: 0,
      isHomeChain: true,
      isFarmable: true,
      keyAddresses: testVaultParams.keyAddresses,
      earnedToZORROPath: [],
      earnedToToken0Path: [],
      earnedToToken1Path: [],
      stablecoinToToken0Path: [],
      stablecoinToToken1Path: [],
      earnedToZORLPPoolOtherTokenPath: [],
      earnedToStablecoinPath: [],
      fees: testVaultParams.fees,
      priceFeeds: testVaultParams.priceFeeds,
    };
    await deployer.link(VaultLibrary, [MockVaultStandardAMM]);
    await deployer.link(VaultLibraryStandardAMM, [MockVaultStandardAMM]);
    await deployProxy(
      MockVaultStandardAMM,
      [
        accounts[0],
        initVal2
      ], {
      deployer,
      unsafeAllow: [
        'external-library-linking',
      ],
    });
  }
};

// TODO: For all vaults!: call the addVault() func with appropriate multiplier