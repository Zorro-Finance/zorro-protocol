const Zorro = artifacts.require("Zorro");

module.exports = async function (deployer) {
  await deployer.deploy(Zorro);
};
