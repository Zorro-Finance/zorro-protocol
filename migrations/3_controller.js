// Upgrades
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
// Get key params
const {
  chains, 
  zeroAddress,
  homeNetwork,
} = require('../helpers/constants');
const {
  getSynthNetwork, isTestNetwork, 
} = require('../helpers/chains');

// Controller
const ZorroController = artifacts.require("ZorroController");
// Actions
const ZorroControllerActions = artifacts.require("ZorroControllerActions");
// Token
const Zorro = artifacts.require('Zorro');
// Other contracts
const IUniswapV2Factory = artifacts.require('IUniswapV2Factory');


module.exports = async function (deployer, network, accounts) {
  
  if (!isTestNetwork(network)) {
    /* Production */
    
    // Deployed contracts
    const zorro = await Zorro.deployed();
  
    // Get constants
    const {
      tokens,
      infra,
      rewards,
      xChain,
    } = chains[getSynthNetwork(network)];
  
    // ZOR-other LP pool for home chain
    if (getSynthNetwork(network) === homeNetwork) {
      // Create pair via Uni
      const iUniswapV2Factory = await IUniswapV2Factory.at(infra.uniFactoryAddress);
      await iUniswapV2Factory.createPair(zorro.address, tokens.wbnb);
    }
    
    // Deploy Actions
    const zcActions = await deployProxy(ZorroControllerActions, [], {deployer});
  
    // Get block params
    // TODO: Set this to the actual current block by getting W3
    const currentBlock = 0;
  
    // ZC constructor args
    let zcInitVal = {
        ZORRO: zorro.address,
        defaultStablecoin: tokens.defaultStablecoin,
        publicPool: zeroAddress, // will be filled in subsequent migration
        zorroStakingVault: zeroAddress, // ditto
        controllerActions: zcActions.address,
        rewards: {
          ...rewards,
          ...{
            startBlock: homeNetwork === getSynthNetwork(network) ? currentBlock + rewards.blocksPerDay * 7 : 0,
          },
        },
        xChain: {
          chainId: xChain.chainId,
          homeChainId: xChain.homeChainId,
          homeChainZorroController: zeroAddress, 
          zorroControllerOracle: zeroAddress, // TODO: Do we still need this, if we're using Chainlink Keepers?
          zorroXChainEndpoint: zeroAddress,
        },
    };
  
    // Deploy Controller
    await deployProxy(ZorroController, [zcInitVal], {deployer});
  
    // Update XChain props to correct home chain Zorro controller if on the home chain
    if (homeNetwork === getSynthNetwork(network)) {
      const zorroController = await ZorroController.deployed();
      await zorroController.setXChainParams(xChain.chainId, xChain.homeChainId, zorroController.address);
    }
  } else {
    /* Testnet */
    console.log('On testnet. Skipping...')
  }
  

  // TODO: Where is Zorro token's ZC set?
};