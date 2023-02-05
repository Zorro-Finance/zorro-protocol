// Upgrades
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
// Get key params
const {
  getSynthNetwork,
} = require('../helpers/chains');
const { chains, zeroAddress, vaultFees } = require('../helpers/constants');

// Vaults
const VaultBenqiAVAXLiqStakeLP = artifacts.require("VaultBenqiAVAXLiqStakeLP");
// Actions
const VaultActionsBenqiLiqStakeLP = artifacts.require('VaultActionsBenqiLiqStakeLP');
// Other contracts
const ZorroController = artifacts.require("ZorroController");
const ZorroControllerXChain = artifacts.require("ZorroControllerXChain");
const Zorro = artifacts.require("Zorro");
const VaultTimelock = artifacts.require('VaultTimelock');
const PoolTreasury = artifacts.require('PoolTreasury');

module.exports = async function (deployer, network, accounts) {
  /* Production */
  
  if (getSynthNetwork(network) === 'avax') {
    // Unpack keyParams
    const { avax } = chains;
    const {
      tokens,
      priceFeeds,
      infra,
      protocols,
    } = avax;

    // Deployed contracts
    const zorroController = await ZorroController.deployed();
    const zorroControllerXChain = await ZorroControllerXChain.deployed();
    const zorro = await Zorro.deployed();
    const vaultTimelock = await VaultTimelock.deployed();
    const poolTreasury = await PoolTreasury.deployed();

    // Deploy actions contract
    const vaultActionsBenqiLiqStakeLP = await deployProxy(VaultActionsBenqiLiqStakeLP, [infra.uniRouterAddress], { deployer });

    // Init values 
    const initVal = {
      baseInit: {
        config: {
          // TODO: get PID right
          pid: 0,
          isHomeChain: false,
        },
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
          vaultActions: vaultActionsBenqiLiqStakeLP.address,
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