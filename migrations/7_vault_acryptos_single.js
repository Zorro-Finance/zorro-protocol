// Upgrades
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
// Vaults
const VaultAcryptosSingle = artifacts.require("VaultAcryptosSingle");
const VaultZorro = artifacts.require("VaultZorro");
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
      mockPriceAggZORLP = await MockPriceAggZORLP.deployed();
    }
  }

  const deployableNetworks = [
    'bsc',
    ...devNets,
  ];
  // TODO: This needs to be filled out in much more detail. Started but incomplete!

  if (deployableNetworks.includes(network)) {
    // Init values 
    // TODO: Create for each chain
    const initVal = {
      pid: vaults.pid, 
      isHomeChain: false,
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
      USDCToToken0Path: [],
      earnedToZORLPPoolOtherTokenPath: [],
      earnedToUSDCPath: [],
      BUSDToToken0Path: [],
      BUSDToZORROPath: [],
      BUSDToLPPoolOtherTokenPath: [],
      fees: vaults.fees,
      priceFeeds: {
        token0PriceFeed: devNets.includes(network) ? mockPriceAggZORLP.address : priceFeeds.priceFeedZOR,
        token1PriceFeed: zeroAddress,
        earnTokenPriceFeed: zeroAddress,
        ZORPriceFeed: devNets.includes(network) ? mockPriceAggZORLP.address : priceFeeds.priceFeedZOR,
        lpPoolOtherTokenPriceFeed: priceFeeds.priceFeedLPPoolOtherToken,
        stablecoinPriceFeed: priceFeeds.stablecoinPriceFeed,
      },
      tokenBUSDPriceFeed,
    };
    // Deploy master contract
    await deployProxy(VaultAcryptosSingle, [accounts[0], initVal], {deployer});
  } else {
    console.log('Not on an allowed chain. Skipping...');
  }
};