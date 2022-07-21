// Upgrades
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
// Vaults
const VaultStandardAMM = artifacts.require("VaultStandardAMM");
const TraderJoe_ZOR_WAVAX = artifacts.require("TraderJoe_ZOR_WAVAX");
const VaultZorro = artifacts.require("VaultZorro");
// Other contracts
const ZorroController = artifacts.require("ZorroController");
const ZorroControllerXChain = artifacts.require("zorroControllerXChain");
const Zorro = artifacts.require("Zorro");
const MockPriceAggZORLP = artifacts.require("MockPriceAggZORLP");
const IUniswapV2Factory = artifacts.require("IUniswapV2Factory");
// Get key params
const { getKeyParams, devNets, getSynthNetwork } = require('../chains');
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
  } = getKeyParams(accounts)[getSynthNetwork(network)];
  
  let mockPriceAggZORLP;
  
  if (devNets.includes(network)) {
    // Deploy Mock ZOR price feed if necessary
    if (!MockPriceAggZORLP.hasNetwork(network)) {
      await deployer.deploy(MockPriceAggZORLP, uniRouterAddress, zorro.address, zorroLPPoolOtherToken, defaultStablecoin);
      mockPriceAggZORLP = await MockPriceAggZORLP.deployed();
    }
  }
  
  let initVal;
  
  if (['avax', 'ganachecloud'].includes(network)) {
    // Prep
    const wavax = '0xb31f66aa3c1e785363f0875a1b74e27b85fd66c7';
    const tokenJoe = '0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd';
    const masterChefJoe = '0x188bED1968b795d5c9022F6a0bb5931Ac4c18F00';
    // Create pair via Uni
    const iUniswapV2Factory = await IUniswapV2Factory.at('0x9Ad6C38BE94206cA50bb0d90783181662f0Cfa10');
    await iUniswapV2Factory.createPair(zorro.address, wavax)
    // Get pair address 
    const pairAddr = await iUniswapV2Factory.getPair.call(zorro.address, wavax);

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
        token1Address: wavax,
        earnedAddress: tokenJoe,
        farmContractAddress: masterChefJoe,
        rewardsAddress: accounts[0],
        poolAddress: pairAddr,
        uniRouterAddress,
        zorroLPPool: pairAddr,
        zorroLPPoolOtherToken,
        tokenUSDCAddress: defaultStablecoin,
      },
      earnedToZORROPath: [tokenJoe, wavax, zorro.address],
      earnedToToken0Path: [tokenJoe, wavax, zorro.address],
      earnedToToken1Path: [tokenJoe, wavax],
      USDCToToken0Path: [defaultStablecoin, wavax, zorro.address],
      USDCToToken1Path: [defaultStablecoin, wavax],
      earnedToZORLPPoolOtherTokenPath: [tokenJoe, wavax, zorro.address],
      earnedToUSDCPath: [tokenJoe, defaultStablecoin],
      fees: vaults.fees,
      priceFeeds: {
        token0PriceFeed: devNets.includes(network) ? mockPriceAggZORLP.address : priceFeeds.priceFeedZOR,
        token1PriceFeed: '0x0A77230d17318075983913bC2145DB16C7366156',
        earnTokenPriceFeed: '0x02D35d3a8aC3e1626d3eE09A78Dd87286F5E8e3a',
        ZORPriceFeed: devNets.includes(network) ? mockPriceAggZORLP.address : priceFeeds.priceFeedZOR,
        lpPoolOtherTokenPriceFeed: priceFeeds.priceFeedLPPoolOtherToken,
        stablecoinPriceFeed: priceFeeds.stablecoinPriceFeed,
      },
    };
    await deployProxy(TraderJoe_ZOR_WAVAX, [accounts[0], initVal], { deployer });
  } else {
    initVal = {
      pid: 0,
      isHomeChain: devNets.includes(network),
      isFarmable: true,
      keyAddresses: {
        govAddress: accounts[0],
        zorroControllerAddress: zorroController.address,
        zorroXChainController: zorroControllerXChain.address,
        ZORROAddress: zorro.address,
        zorroStakingVault: vaultZorro.address,
        wantAddress: zeroAddress,
        token0Address: zeroAddress,
        token1Address: zeroAddress,
        earnedAddress: zeroAddress,
        farmContractAddress: zeroAddress,
        rewardsAddress: zeroAddress,
        poolAddress: zeroAddress,
        uniRouterAddress,
        zorroLPPool: zeroAddress,
        zorroLPPoolOtherToken,
        tokenUSDCAddress: defaultStablecoin,
      },
      earnedToZORROPath: [],
      earnedToToken0Path: [],
      earnedToToken1Path: [],
      USDCToToken0Path: [],
      USDCToToken1Path: [],
      earnedToZORLPPoolOtherTokenPath: [],
      earnedToUSDCPath: [],
      fees: vaults.fees,
      priceFeeds: {
        token0PriceFeed: devNets.includes(network) ? mockPriceAggZOR.address : priceFeeds.priceFeedZOR,
        token1PriceFeed: zeroAddress,
        earnTokenPriceFeed: zeroAddress,
        ZORPriceFeed: devNets.includes(network) ? mockPriceAggZOR.address : priceFeeds.priceFeedZOR,
        lpPoolOtherTokenPriceFeed: priceFeeds.priceFeedLPPoolOtherToken,
        stablecoinPriceFeed: priceFeeds.stablecoinPriceFeed,
      },
    };
    await deployProxy(VaultStandardAMM, [accounts[0], initVal], { deployer });
  }

};