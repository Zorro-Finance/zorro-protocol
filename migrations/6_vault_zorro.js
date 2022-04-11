// Vaults
const VaultZorro = artifacts.require("VaultZorro");
// Libs
const PriceFeed = artifacts.require("PriceFeed");
const SafeSwapUni = artifacts.require("SafeSwapUni");


module.exports = async function (deployer, network, accounts) {
  const deployableNetworks = [
    'avalanche',
    'ganache',
    'default',
    'development',
  ];
  if (deployableNetworks.includes(network)) {
    // Libs
    await deployer.deploy(PriceFeed);
    await deployer.deploy(SafeSwapUni);
    
    // Links
    await deployer.link(PriceFeed, VaultZorro);
    await deployer.link(SafeSwapUni, VaultZorro);
    
    // Deploy
    await deployer.deploy(VaultZorro);
  }
};