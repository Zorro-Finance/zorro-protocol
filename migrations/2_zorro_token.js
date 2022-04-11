// Tokens
const Zorro = artifacts.require("Zorro");

module.exports = async function (deployer, network, accounts) {
  await deployer.deploy(Zorro, accounts[0]);
};