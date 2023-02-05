// Upgrades
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
// Chain params
const { getSynthNetwork, isTestNetwork } = require('../helpers/chains');
const { homeNetwork, owners, defaultTimelockPeriodSecs, vesting, zeroAddress, ZORDistributions, ZORTotalDistribution } = require('../helpers/constants');
// Migration
const Migrations = artifacts.require("Migrations");

// Distribution pools
const PoolPublic = artifacts.require("PoolPublic");
const PoolTreasury = artifacts.require('PoolTreasury');
const TreasuryVestingWallet = artifacts.require('TreasuryVestingWallet');
const TeamVestingWallet = artifacts.require('TeamVestingWallet');
const PoolAdvisory = artifacts.require('PoolAdvisory');

// Timelocks
const ControllerTimelock = artifacts.require('ControllerTimelock');
const FinanceTimelock = artifacts.require('FinanceTimelock');
const VaultTimelock = artifacts.require('VaultTimelock');

// Controller
const ZorroController = artifacts.require("ZorroController");
// Token
const Zorro = artifacts.require("Zorro");


module.exports = async function (deployer, network, accounts) {
  // Web3
  const adapter = Migrations.interfaceAdapter;
  const { web3 } = adapter;

  // Constants
  const now = parseInt((new Date().getTime()) / 1000.0);

  // Existing contracts
  const zorroToken = await Zorro.deployed();
  const zorroController = await ZorroController.deployed();

  // Deploy timelock controllers
  const minDelay = isTestNetwork(network) ? 0 : defaultTimelockPeriodSecs;
  const proposers = isTestNetwork(network) ? [accounts[0]] : owners;

  // Deploy ControllerTimelock
  const controllerTimelock = await deployProxy(ControllerTimelock, [
    minDelay,
    proposers,
    []
  ], { deployer });

  // Deploy FinanceTimelock
  const financeTimelock = await deployProxy(FinanceTimelock, [
    minDelay,
    proposers,
    []
  ], { deployer });

  // Deploy VaultTimelock
  await deployProxy(VaultTimelock, [
    minDelay,
    proposers,
    []
  ], { deployer });

  // Controller transfer ownership to controller timelock
  await zorroController.transferOwnership(controllerTimelock.address);

  // Deploy treasury pool on each chain
  const poolTreasury = await deployProxy(PoolTreasury, [
    zorroToken.address,
  ], { deployer });

  // Transfer treasury ownership to timelock
  await poolTreasury.transferOwnership(financeTimelock.address);

  // Allowed networks
  if (getSynthNetwork(network) === homeNetwork) {
    // Pass minting control to this deployer account (temporarily)
    await zorroToken.setZorroController(accounts[0]);

    // Deploy public pool
    const poolPublic = await deployProxy(PoolPublic, [
      zorroToken.address,
      zorroController.address,
    ], { deployer });

    // Mint ZOR to public pool
    const publicQty = web3.utils.toWei((ZORDistributions.public * ZORTotalDistribution).toString(), 'ether');
    await zorroToken.mint(poolPublic.address, publicQty);

    // Set owner to finance timelock
    const financeTimelock = await FinanceTimelock.deployed();
    await poolPublic.transferOwnership(financeTimelock.address);

    // Get vesting params
    const { cliffPeriodSecs, vestingPeriodSecs } = vesting;

    // Deploy treasury vesting wallet
    const treasuryVestingWallet = await deployProxy(TreasuryVestingWallet, [
      poolTreasury.address,
      now,
      vestingPeriodSecs,
    ], { deployer });

    // Mint ZOR to treasury vesting wallet
    const treasuryQty = web3.utils.toWei((ZORDistributions.treasury * ZORTotalDistribution).toString(), 'ether');
    await zorroToken.mint(treasuryVestingWallet.address, treasuryQty);

    // Deploy team vesting wallets
    const modifiedOwners = isTestNetwork(network) ? [accounts[0]] : owners;
    for (let owner of modifiedOwners) {
      // Deploy contract
      const tvw = await TeamVestingWallet.new(
        owner,
        now,
        vestingPeriodSecs,
        cliffPeriodSecs,
      );

      console.log(`Created team vesting wallet for owner: ${owner} at ${tvw.address}`);

      // Send ZOR to vesting wallet
      const teamQty = web3.utils.toWei((ZORDistributions.team * ZORTotalDistribution / modifiedOwners.length).toString(), 'ether');
      // Mint ZOR
      await zorroToken.mint(tvw.address, teamQty);
    }

    // Deploy advisory pool
    const poolAdvisory = await deployProxy(PoolAdvisory, [
      zorroToken.address,
      cliffPeriodSecs,
      vestingPeriodSecs,
    ], { deployer });

    // Mint ZOR to advisory pool
    const advisoryQty = web3.utils.toWei((ZORDistributions.advisors * ZORTotalDistribution).toString(), 'ether');
    await zorroToken.mint(poolAdvisory.address, advisoryQty);

    // Change advisory pool ownership to Finance Timelock
    await poolAdvisory.transferOwnership(financeTimelock.address);

    // Pass minting control back to Zorro controller
    await zorroToken.setZorroController(zorroController.address);

    // Set ownership of Zorro token to timelock controller
    await zorroToken.transferOwnership(financeTimelock.address);
    
  } else {
    console.log('Not home chain. Skipping public pool creation');
  }
};