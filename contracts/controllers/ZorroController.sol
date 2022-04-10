// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./_ZorroControllerBase.sol";

import "./_ZorroControllerPoolMgmt.sol";

import "./_ZorroControllerInvestment.sol";

import "./_ZorroControllerAnalytics.sol";

import "./_ZorroControllerXChainReceiver.sol";

import "./_ZorroControllerXChainDeposit.sol";

import "./_ZorroControllerXChainWithdraw.sol";

import "./_ZorroControllerXChainEarn.sol";

/* Main Contract */
/// @title ZorroController: The main controller of the Zorro yield farming protocol. Used for cash flow operations (deposit/withdrawal), managing vaults, and rewards allocations, among other things.
contract ZorroController is
    ZorroControllerBase,
    ZorroControllerPoolMgmt,
    ZorroControllerAnalytics,
    ZorroControllerInvestment
{
    /* Constructor */

    /// @notice Upgradeable constructor
    /// @param _timelockOwner Address of owner (should be a timelock)
    /// @param _initValue A ZorroControllerInit struct containing all constructor args
    function initialize(address _timelockOwner, ZorroControllerInit memory _initValue) public {
        // Tokens
        ZORRO = _initValue.ZORRO;
        defaultStablecoin = _initValue.defaultStablecoin;
        zorroLPPoolOtherToken = _initValue.zorroLPPoolOtherToken;
        tokenUSDC = _initValue.tokenUSDC;

        // Key contracts
        publicPool = _initValue.publicPool;
        zorroStakingVault = _initValue.zorroStakingVault;
        zorroLPPool = _initValue.zorroLPPool;
        uniRouterAddress = _initValue.uniRouterAddress;

        // Rewards
        ZORRODailyDistributionFactorBasisPointsMin = 1;
        ZORRODailyDistributionFactorBasisPointsMax = 20;
        isTimeMultiplierActive = true;
        blocksPerDay = _initValue.rewards.blocksPerDay;
        startBlock = _initValue.rewards.startBlock;
        ZORROPerBlock = _initValue.rewards.ZORROPerBlock;
        targetTVLCaptureBasisPoints = _initValue
            .rewards
            .targetTVLCaptureBasisPoints;
        chainMultiplier = _initValue.rewards.chainMultiplier;
        baseRewardRateBasisPoints = _initValue.rewards.chainMultiplier;

        // Cross chain
        chainId = _initValue.xChain.chainId;
        homeChainId = _initValue.xChain.homeChainId;
        address _homeChainZorroController = _initValue
            .xChain
            .homeChainZorroController;
        if (_homeChainZorroController == address(0)) {
            homeChainZorroController = address(this);
        } else {
            homeChainZorroController = _homeChainZorroController;
        }
        zorroControllerOracle = _initValue.xChain.zorroControllerOracle;

        // Investment
        USDCToZorroPath = _initValue.USDCToZorroPath;
        USDCToZorroLPPoolOtherTokenPath = _initValue
            .USDCToZorroLPPoolOtherTokenPath;

        // Price feeds
        priceFeedZOR = AggregatorV3Interface(
            _initValue.priceFeeds.priceFeedZOR
        );
        priceFeedLPPoolOtherToken = AggregatorV3Interface(
            _initValue.priceFeeds.priceFeedLPPoolOtherToken
        );

        // Assign owner as to timelock contract
        transferOwnership(_timelockOwner);
    }

    /* Structs */

    struct ZorroControllerRewards {
        uint256 blocksPerDay;
        uint256 startBlock;
        uint256 ZORROPerBlock;
        uint256 targetTVLCaptureBasisPoints;
        uint256 chainMultiplier;
        uint256 baseRewardRateBasisPoints;
    }

    struct ZorroControllerXChainParams {
        uint256 chainId;
        uint256 homeChainId;
        address homeChainZorroController;
        address zorroControllerOracle;
    }

    struct ZorroControllerPriceFeeds {
        address priceFeedZOR;
        address priceFeedLPPoolOtherToken;
    }

    struct ZorroControllerInit {
        address ZORRO;
        address defaultStablecoin;
        address zorroLPPoolOtherToken;
        address tokenUSDC;
        address publicPool;
        address zorroStakingVault;
        address zorroLPPool;
        address uniRouterAddress;
        address[] USDCToZorroPath;
        address[] USDCToZorroLPPoolOtherTokenPath;
        ZorroControllerRewards rewards;
        ZorroControllerXChainParams xChain;
        ZorroControllerPriceFeeds priceFeeds;
    }
}
