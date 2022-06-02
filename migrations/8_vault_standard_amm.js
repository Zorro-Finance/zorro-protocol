// Upgrades
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
// Vaults
const VaultStandardAMM = artifacts.require("VaultStandardAMM");
// Factory
const VaultFactoryStandardAMM = artifacts.require('VaultFactoryStandardAMM');

module.exports = async function (deployer, network, accounts) {
  // Init values
  // TODO: Create init value for each chain
  const initVal = {
    pid: 0,
    isHomeChain: network === 'avax',
    keyAddresses: {
      govAddress: '0x0000000000000000000000000000000000000000',
      zorroControllerAddress: '0x0000000000000000000000000000000000000000',
      zorroXChainController: '0x0000000000000000000000000000000000000000',
      ZORROAddress: '0x0000000000000000000000000000000000000000',
      zorroStakingVault: '0x0000000000000000000000000000000000000000',
      wantAddress: '0x0000000000000000000000000000000000000000',
      token0Address: '0x0000000000000000000000000000000000000000',
      token1Address: '0x0000000000000000000000000000000000000000',
      earnedAddress: '0x0000000000000000000000000000000000000000',
      farmContractAddress: '0x0000000000000000000000000000000000000000',
      rewardsAddress: '0x0000000000000000000000000000000000000000',
      poolAddress: '0x0000000000000000000000000000000000000000',
      uniRouterAddress: '0x0000000000000000000000000000000000000000',
      zorroLPPool: '0x0000000000000000000000000000000000000000',
      zorroLPPoolOtherToken: '0x0000000000000000000000000000000000000000',
      tokenUSDCAddress: '0x0000000000000000000000000000000000000000',
    },
    earnedToZORROPath: [],
    earnedToToken0Path: [],
    earnedToToken1Path: [],
    USDCToToken0Path: [],
    USDCToToken1Path: [],
    earnedToZORLPPoolOtherTokenPath: [],
    earnedToUSDCPath: [],
    fees: {
      controllerFee: 0,
      buyBackRate: 0,
      revShareRate: 0,
      entranceFeeFactor: 0,
      withdrawFeeFactor: 0,
    },
    priceFeeds: {
      token0PriceFeed: '0x0000000000000000000000000000000000000000',
      token1PriceFeed: '0x0000000000000000000000000000000000000000',
      earnTokenPriceFeed: '0x0000000000000000000000000000000000000000',
      ZORPriceFeed: '0x0000000000000000000000000000000000000000',
      lpPoolOtherTokenPriceFeed: '0x0000000000000000000000000000000000000000',
    },
  };
  // Deploy master contract
  const instance = await deployProxy(VaultStandardAMM, [accounts[0], initVal], {deployer});

  // Deploy factory contract
  deployProxy(VaultFactoryStandardAMM, [instance.address], {deployer});
};