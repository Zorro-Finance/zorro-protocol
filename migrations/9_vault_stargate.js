// Upgrades
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
// Vaults
const VaultStargate = artifacts.require("VaultStargate");
const VaultZorro = artifacts.require("VaultZorro");
// Other contracts 
const MockPriceAggZORLP = artifacts.require("MockPriceAggZORLP");
const ZorroController = artifacts.require("ZorroController");
const ZorroControllerXChain = artifacts.require("ZorroControllerXChain");
const Zorro = artifacts.require("Zorro");
// Get key params
const { getKeyParams, getSynthNetwork, devNets } = require('../chains');
const zeroAddress = '0x0000000000000000000000000000000000000000';

// TODO: This needs to be filled out in much more detail. Started but incomplete!
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
    bridge,
  } = getKeyParams(accounts)[getSynthNetwork(network)];

  let mockPriceAggZORLP;
  
  if (devNets.includes(network)) {
    // Deploy Mock ZOR price feed if necessary
    if (!MockPriceAggZORLP.hasNetwork(network)) {
      await deployer.deploy(MockPriceAggZORLP, uniRouterAddress, zorro.address, zorroLPPoolOtherToken, defaultStablecoin);
    }
    mockPriceAggZORLP = await MockPriceAggZORLP.deployed();
  }

  // TODO: These values need to be re-examined

  // Init values 
  const initVal = {
    pid: 0,
    isHomeChain: ['avax', 'ganachecloud'].includes(network),
    keyAddresses: {
      govAddress: accounts[0],
      zorroControllerAddress: zorroController.address,
      zorroXChainController: zorroControllerXChain.address,
      ZORROAddress: zorro.address,
      zorroStakingVault: vaultZorro.address,
      wantAddress: defaultStablecoin,
      token0Address: defaultStablecoin,
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
    USDCToToken0Path: [],
    earnedToZORLPPoolOtherTokenPath: [],
    earnedToUSDCPath: [],
    fees: vaults.fees,
    priceFeeds: {
      token0PriceFeed: devNets.includes(network) ? mockPriceAggZORLP.address : priceFeeds.priceFeedZOR,
      token1PriceFeed: zeroAddress,
      earnTokenPriceFeed: zeroAddress,
      ZORPriceFeed: devNets.includes(network) ? mockPriceAggZORLP.address : priceFeeds.priceFeedZOR,
      lpPoolOtherTokenPriceFeed: priceFeeds.priceFeedLPPoolOtherToken,
      stablecoinPriceFeed: priceFeeds.stablecoinPriceFeed,
    },
    tokenSTG: bridge.tokenSTG,
    stargateRouter: bridge.stargateRouter,
    stargatePoolId: bridge.stargatePoolId,
  };

  // Deploy master contract
  await deployProxy(VaultStargate, [accounts[0], initVal], {deployer});
};