// Vaults
const VaultStargate = artifacts.require("VaultStargate");
// Libs
const PriceFeed = artifacts.require("PriceFeed");
const SafeSwapUni = artifacts.require("SafeSwapUni");


module.exports = async function (deployer, network, accounts) {
  const deployableNetworks = [
    'avalanche',
    'ganache',
    'ganachecli',
    'default',
    'development',
  ];
  if (deployableNetworks.includes(network)) {
    // Libs
    await deployer.deploy(PriceFeed);
    await deployer.deploy(SafeSwapUni);
    
    // Links
    await deployer.link(PriceFeed, VaultStargate);
    await deployer.link(SafeSwapUni, VaultStargate);
    
    // Deploy
    await deployer.deploy(VaultStargate);
  }
};