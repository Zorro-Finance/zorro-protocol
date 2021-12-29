const ZorroController = artifacts.require("ZorroController");
const Math = artifacts.require("Math");

module.exports = async function (deployer) {
  await deployer.deploy(Math);
  await deployer.link(Math, ZorroController);
  await deployer.deploy(ZorroController);
};
