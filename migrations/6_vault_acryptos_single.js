// Vaults
const VaultAcryptosSingle = artifacts.require("VaultAcryptosSingle");
// Libs
const PriceFeed = artifacts.require("PriceFeed");
const SafeSwapUni = artifacts.require("SafeSwapUni");
const SafeSwapBalancer = artifacts.require("SafeSwapBalancer");


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
    await deployer.deploy(SafeSwapBalancer);

    // Links
    await deployer.link(PriceFeed, VaultAcryptosSingle);
    await deployer.link(SafeSwapUni, VaultAcryptosSingle);
    await deployer.link(SafeSwapBalancer, VaultAcryptosSingle);

    // Deploy
    await deployer.deploy(VaultAcryptosSingle);

    // TODO: Change to deploy proxy
    // TODO: Deploy proxy the factory, initialize with the master contract
  }
};