// Upgrades
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
// Vaults
const VaultStandardAMM = artifacts.require("VaultStandardAMM");
const VaultZorro = artifacts.require("VaultZorro");
// Other contracts
const ZorroController = artifacts.require("ZorroController");
const ZorroControllerXChain = artifacts.require("zorroControllerXChain");
const Zorro = artifacts.require("Zorro");
const MockPriceAggZOR = artifacts.require("MockPriceAggZOR");
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

  let mockPriceAggZOR; 

  if (devNets.includes(network)) {
    // Deploy Mock ZOR price feed if necessary
    if (!MockPriceAggZOR.hasNetwork(network)) {
      await deployer.deploy(MockPriceAggZOR);
      mockPriceAggZOR = await MockPriceAggZOR.deployed();
    }
  }

  // Init values
  const initVal = {
    pid: 0,
    isHomeChain: network === 'avax',
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
    },
  };
  await deployProxy(VaultStandardAMM, [accounts[0], initVal], { deployer });
};