// Upgrades
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
// Vaults
const VaultZorro = artifacts.require("VaultZorro");


module.exports = async function (deployer, network, accounts) {
  const deployableNetworks = [
    'avalanche',
    'ganache',
    'ganachecli',
    'default',
    'development',
    'test',
  ];
  if (deployableNetworks.includes(network)) {
    // Init values 
    const initVal = {
      pid: 0,
      keyAddresses: {
        govAddress: '0x0000000000000000000000000000000000000000',
        zorroControllerAddress: '0x0000000000000000000000000000000000000000',
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
      USDCToToken0Path: [],
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
    // Deploy
    // TODO: For this and all ownable contracts, make sure to set an account that we can always have access to. 
    // https://ethereum.stackexchange.com/questions/17441/how-to-choose-an-account-to-deploy-a-contract-in-truffle 
    const instance = await deployProxy(VaultZorro, ['0x62D255A418a7a25e3b2e08c30F12AC80718CB67F', initVal], {deployer});
    const owner = await instance.owner.call();
    console.log('owner: ', owner);
    // console.log('current owner: ', instance.owner.call());
  } else {
    console.log('Not home chain. Skipping Zorro Single Staking Vault creation');
  }
};