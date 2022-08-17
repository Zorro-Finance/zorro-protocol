// Upgrades
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
// Vaults
const VaultZorro = artifacts.require("VaultZorro");
// Other contracts
const PoolPublic = artifacts.require("PoolPublic");
const ZorroController = artifacts.require("ZorroController");
const ZorroControllerXChain = artifacts.require("ZorroControllerXChain");
const Zorro = artifacts.require("Zorro");
const MockPriceAggZORLP = artifacts.require("MockPriceAggZORLP");
// Get key params
const {getKeyParams, getSynthNetwork, devNets, homeNetworks} = require('../chains');
const zeroAddress = '0x0000000000000000000000000000000000000000';
const wavax = '0xb31f66aa3c1e785363f0875a1b74e27b85fd66c7';

module.exports = async function (deployer, network, accounts) {
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
    USDCToZorroPath,
    USDCToZorroLPPoolOtherTokenPath,
    priceFeeds,
    vaults,
  } = getKeyParams(accounts, zorro.address)[getSynthNetwork(network)];

  let mockPriceAggZORLP;
  
  if (devNets.includes(network)) {
    // Deploy Mock ZOR price feed if necessary
    if (!MockPriceAggZORLP.hasNetwork(network)) {
      await deployer.deploy(MockPriceAggZORLP, uniRouterAddress, zorro.address, zorroLPPoolOtherToken, defaultStablecoin);
    }
    mockPriceAggZORLP = await MockPriceAggZORLP.deployed();
  }

  if (homeNetworks.includes(network)) {
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
        rewardsAddress: zeroAddress, // not needed; use zero address
        poolAddress: zeroAddress, // not needed; use zero address
        uniRouterAddress,
        zorroLPPool: zeroAddress, // needs to be filled in with appropriate value later!
        zorroLPPoolOtherToken,
        tokenUSDCAddress: defaultStablecoin,
      },
      USDCToToken0Path: [defaultStablecoin, wavax, zorro.address],
      fees: vaults.fees,
      priceFeeds: {
        token0PriceFeed: devNets.includes(network) ? mockPriceAggZORLP.address : priceFeeds.priceFeedZOR,
        token1PriceFeed: zeroAddress,
        earnTokenPriceFeed: zeroAddress,
        ZORPriceFeed: devNets.includes(network) ? mockPriceAggZORLP.address : priceFeeds.priceFeedZOR,
        lpPoolOtherTokenPriceFeed: priceFeeds.priceFeedLPPoolOtherToken,
        stablecoinPriceFeed: priceFeeds.stablecoinPriceFeed, 
      },
    };
    // Deploy
    // TODO: For this and all ownable contracts, make sure to set an account that we can always have access to. 
    // https://ethereum.stackexchange.com/questions/17441/how-to-choose-an-account-to-deploy-a-contract-in-truffle 
    await deployProxy(VaultZorro, [accounts[0], initVal], {deployer});

    // Update ZorroController
    const vaultZorro = await VaultZorro.deployed();
    await zorroController.setZorroContracts(poolPublic.address, vaultZorro.address);
  } else {
    console.log('Not home chain. Skipping Zorro Single Staking Vault creation');
  }
};