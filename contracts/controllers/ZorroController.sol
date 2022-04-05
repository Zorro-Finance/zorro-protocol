// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/* Dependencies */
import "./_ZorroControllerBase.sol";

import "./_ZorroControllerPoolMgmt.sol";

import "./_ZorroControllerInvestment.sol";

import "./_ZorroControllerAnalytics.sol";

import "./_ZorroControllerXChainReceiver.sol";

import "./_ZorroControllerXChainDeposit.sol";

import "./_ZorroControllerXChainWithdraw.sol";

import "./_ZorroControllerXChainEarn.sol";


// TODO: General: Complete audit of docstrings and make sure they make sense

/* Main Contract */
/// @title ZorroController: The main controller of the Zorro yield farming protocol. Used for cash flow operations (deposit/withdrawal), managing vaults, and rewards allocations, among other things.
contract ZorroController is
    ZorroControllerBase,
    ZorroControllerPoolMgmt,
    ZorroControllerInvestment,
    ZorroControllerAnalytics,
    ZorroControllerXChainReceiver
{
    /* Constructor */

    /// @notice Constructor
    /// @param _timelockOwner address of owner (should be a timelock)
    /// @param _homeChainZorroController The address of the home chain Zorro controller contract
    /// @param _zorroLPPoolAddresses An array of: The address of the Zorro LP pool, the counterparty token to the ZOR LP pool
    /// @param _chainId The ID of the chain that this contract is being deployed on
    /// @param _priceFeeds Array of Chainlink price feeds: [priceFeedZOR, priceFeedLPPoolOtherToken]
    /// @param _zorroControllerOracle Address of Zorro Chainlink oracle for controller
    constructor(
        address _timelockOwner,
        address _publicPool,
        address _stableCoinAddress,
        address _homeChainZorroController,
        address[] memory _zorroLPPoolAddresses,
        uint256 _chainId,
        address[] memory _priceFeeds,
        address _zorroControllerOracle
    ) {
        // Base
        // TODO: Implement real numbers these are just dummy values
        ZORRO = address(0);
        publicPool = _publicPool;
        blocksPerDay = 28800;
        startBlock = block.number;
        ZORROPerBlock = 1000;
        targetTVLCaptureBasisPoints = 33;
        ZORRODailyDistributionFactorBasisPointsMin = 1;
        ZORRODailyDistributionFactorBasisPointsMax = 20;
        chainMultiplier = 1;
        baseRewardRateBasisPoints = 10;
        totalAllocPoint = 0;
        defaultStablecoin = _stableCoinAddress;
        zorroStakingVault = address(0);
        chainId = _chainId;
        homeChainId = 0;
        require(_homeChainZorroController != address(0), "cannot be 0 addr");
        homeChainZorroController = _homeChainZorroController;
        zorroControllerOracle = _zorroControllerOracle;

        // Investment
        isTimeMultiplierActive = true;
        zorroLPPool = _zorroLPPoolAddresses[0];
        zorroLPPoolOtherToken = _zorroLPPoolAddresses[1];
        uniRouterAddress = address(0);
        // TODO
        // USDCToZorroPath = [?];
        // USDCToZorroLPPoolOtherTokenPath = [?];
        priceFeedZOR = AggregatorV3Interface(_priceFeeds[0]);
        priceFeedLPPoolOtherToken = AggregatorV3Interface(_priceFeeds[1]);

        // XChain
        stargateRouter = address(0);
        stargateSwapPoolId = 0;
        layerZeroEndpoint = address(0);

        // Assign owner as to timelock contract
        transferOwnership(_timelockOwner);
    }
}
