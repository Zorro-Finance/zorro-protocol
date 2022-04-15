// Token
const ZorroToken = artifacts.require("Zorro");

module.exports = async function (deployer, network, accounts) {
  // Allowed networks
  const allowedNetworks = [
    'avax',
    'ganache',
    'ganachecli',
    'default',
    'development',
    'test',
  ];
  if (allowedNetworks.includes(network)) {
    // Deploy
    await deployer.deploy(ZorroToken);
  } else {
    console.log('Not home chain. Skipping public pool creation');
  }
};