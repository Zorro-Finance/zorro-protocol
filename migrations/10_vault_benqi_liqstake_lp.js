// Upgrades
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
// Get key params
const {
  getSynthNetwork,
} = require('../helpers/chains');
const { chains, zeroAddress } = require('../helpers/constants');

// Vaults
const VaultBenqiAVAXLiqStakeLP = artifacts.require("VaultBenqiAVAXLiqStakeLP");
// Actions
const VaultActionsLiqStakeLP = artifacts.require('VaultActionsLiqStakeLP');
// Other contracts
const ZorroController = artifacts.require("ZorroController");
const ZorroControllerXChain = artifacts.require("ZorroControllerXChain");
const Zorro = artifacts.require("Zorro");
const VaultTimelock = artifacts.require('VaultTimelock');
const PoolTreasury = artifacts.require('PoolTreasury');

module.exports = async function (deployer, network, accounts) {
  /* Production */

  // Deployed contracts
  const zorroController = await ZorroController.deployed();
  const zorroControllerXChain = await ZorroControllerXChain.deployed();
  const zorro = await Zorro.deployed();
  const vaultTimelock = await VaultTimelock.deployed();
  const poolTreasury = await PoolTreasury.deployed();

  
  if (getSynthNetwork(network) === 'avax') {
    // Unpack keyParams
    const { avax, vaultFees } = chains;
    const {
      tokens,
      priceFeeds,
      infra,
      protocols,
    } = avax;

    // Deployed contracts

    // Get Zorro LP pool
    const iUniswapV2Factory = await IUniswapV2Factory.at(infra.uniFactoryAddress);
    const zorroLPPool = iUniswapV2Factory.getPair.call(zorro.address, tokens.wbnb);

    // Deploy actions contract
    const vaultActionsLiqStakeLP = await deployProxy(VaultActionsLiqStakeLP, [infra.uniRouterAddress], { deployer });

    // Init values 
    const initVal = {
      baseInit: {
        // TODO: get PID right
        pid: 0,
        keyAddresses: {
          govAddress: vaultTimelock.address,
          zorroControllerAddress: zorroController.address,
          zorroXChainController: zorroControllerXChain.address,
          ZORROAddress: zorro.address,
          zorroStakingVault: zeroAddress,
          wantAddress: tokens.wavax,
          token0Address: tokens.wavax,
          token1Address: zeroAddress,
          // TODO: What is the earned address, really? Consider taking this out of VaultBase, as it doesn't seem like it's used
          earnedAddress: zeroAddress,
          farmContractAddress: protocols.benqi.tokenSaleDistributor,
          treasury: poolTreasury.address,
          poolAddress: protocols.benqi.avaxLendingPool,
          uniRouterAddress: infra.uniRouterAddress,
          zorroLPPool: zeroAddress,
          zorroLPPoolOtherToken: zeroAddress,
          defaultStablecoin: tokens.usdc,
          vaultActions: vaultActionsLiqStakeLP.address,
        },
        swapPaths: {
          earnedToZORROPath: [],
          earnedToToken0Path: [tokens.qi, tokens.wavax],
          earnedToToken1Path: [],
          stablecoinToToken0Path: [tokens.usdc, tokens.wavax],
          stablecoinToToken1Path: [],
          earnedToZORLPPoolOtherTokenPath: [],
          earnedToStablecoinPath: [tokens.qi, tokens.wavax, tokens.usdc],
          stablecoinToZORROPath: [],
          stablecoinToLPPoolOtherTokenPath: [],
        },
        fees: vaultFees,
        priceFeeds: {
          token0PriceFeed: priceFeeds.avax,
          token1PriceFeed: zeroAddress,
          earnTokenPriceFeed: priceFeeds.qi,
          ZORPriceFeed: zeroAddress,
          lpPoolOtherTokenPriceFeed: zeroAddress,
          stablecoinPriceFeed: priceFeeds.usdc,
        },
      },
      liquidStakeToken: protocols.benqi.savax,
      liquidStakingPool: protocols.benqi.avaxLendingPool,
      liquidStakeTokenPriceFeed: priceFeeds.savax,
      liquidStakeToToken0Path: [protocols.benqi.savax, tokens.wavax],
      // TODO: Is it in fact farmable? 
      isLPFarmable: true,
    };

    // Deploy
    await deployProxy(VaultBenqiAVAXLiqStakeLP,
      [
        vaultTimelock.address,
        initVal,
      ],
      {
        deployer,
      }
    );
  } else {
    console.log('Not AVAX chain. Skipping vault creation');
  }
};