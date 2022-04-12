// Vaults
const VaultStandardAMM = artifacts.require("VaultStandardAMM");
// Libs
const PriceFeed = artifacts.require("PriceFeed");
const SafeSwapUni = artifacts.require("SafeSwapUni");


module.exports = async function (deployer, network, accounts) {
  const deployableNetworks = [
    'bsc',
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
      await deployer.link(PriceFeed, VaultStandardAMM);
      await deployer.link(SafeSwapUni, VaultStandardAMM);
      
      // Deploy
      await deployer.deploy(VaultStandardAMM);
  }
};