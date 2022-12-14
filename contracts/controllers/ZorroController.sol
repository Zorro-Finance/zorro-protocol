// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./_ZorroControllerBase.sol";

import "./_ZorroControllerVaultMgmt.sol";

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
    ZorroControllerVaultMgmt,
    ZorroControllerAnalytics,
    ZorroControllerInvestment
{
    /* Constructor */

    /// @notice Upgradeable constructor
    /// @param _initValue A ZorroControllerInit struct containing all constructor args
    function initialize(ZorroControllerInit memory _initValue) public initializer {
        // Tokens
        ZORRO = _initValue.ZORRO;
        defaultStablecoin = _initValue.defaultStablecoin;

        // Key addresses
        publicPool = _initValue.publicPool;
        zorroStakingVault = _initValue.zorroStakingVault;
        burnAddress = 0x000000000000000000000000000000000000dEaD;
        controllerActions = _initValue.controllerActions;

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
        baseRewardRateBasisPoints = _initValue.rewards.baseRewardRateBasisPoints;

        // Cross chain
        chainId = _initValue.xChain.chainId;
        homeChainId = _initValue.xChain.homeChainId;
        homeChainZorroController = _initValue.xChain.homeChainZorroController;
        zorroControllerOracle = _initValue.xChain.zorroControllerOracle;
        zorroXChainEndpoint = _initValue.xChain.zorroXChainEndpoint;

        // Ownable
        __Ownable_init();
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
        address zorroXChainEndpoint;
    }

    struct ZorroControllerInit {
        address ZORRO;
        address defaultStablecoin;
        address publicPool;
        address zorroStakingVault;
        address controllerActions;
        ZorroControllerRewards rewards;
        ZorroControllerXChainParams xChain;
    }
}
