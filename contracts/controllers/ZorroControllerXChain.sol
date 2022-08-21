// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./_ZorroControllerInvestment.sol";

import "../interfaces/IAMMRouter02.sol";

import "../interfaces/IVault.sol";

import "../libraries/SafeSwap.sol";

import "../interfaces/ILayerZeroEndpoint.sol";

import "../interfaces/IStargateRouter.sol";

import "../interfaces/IZorroControllerXChain.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "./_ZorroControllerXChainBase.sol";

import "./_ZorroControllerXChainDeposit.sol";

import "./_ZorroControllerXChainEarn.sol";

import "./_ZorroControllerXChainWithdraw.sol";

import "./_ZorroControllerXChainReceiver.sol";

contract ZorroControllerXChain is
    IZorroControllerXChain,
    ZorroControllerXChainBase,
    ZorroControllerXChainDeposit,
    ZorroControllerXChainWithdraw,
    ZorroControllerXChainEarn,
    ZorroControllerXChainReceiver
{
    /* Libraries */
    using SafeMathUpgradeable for uint256;

    /* Constructor */

    /// @notice Upgradeable constructor
    /// @param _initValue a ZorroControllerXChainInit struct for initializing this contract
    function initialize(ZorroControllerXChainInit memory _initValue)
        public
        initializer
    {
        // Base
        stargateRouter = _initValue.bridge.stargateRouter;
        stargateSwapPoolId = _initValue.bridge.stargateSwapPoolId;
        layerZeroEndpoint = _initValue.bridge.layerZeroEndpoint;
        burnAddress = 0x000000000000000000000000000000000000dEaD;

        for (uint16 i = 0; i < _initValue.bridge.ZorroChainIDs.length; ++i) {
            uint256 _zChainId = _initValue.bridge.ZorroChainIDs[i];

            controllerContractsMap[_zChainId] = _initValue
                .bridge
                .controllerContracts[i];
            ZorroChainToLZMap[_zChainId] = _initValue.bridge.LZChainIDs[i];
            LZChainToZorroMap[_initValue.bridge.LZChainIDs[i]] = _zChainId;
            stargateDestPoolIds[_zChainId] = _initValue
                .bridge
                .stargateDestPoolIds[i];
        }

        // Earn
        // Tokens
        zorroLPPoolOtherToken = _initValue.zorroLPPoolOtherToken;
        // Contracts
        zorroStakingVault = _initValue.zorroStakingVault;
        uniRouterAddress = _initValue.uniRouterAddress;
        // Swaps
        USDCToZorroPath = _initValue.swaps.USDCToZorroPath;
        USDCToZorroLPPoolOtherTokenPath = _initValue
            .swaps
            .USDCToZorroLPPoolOtherTokenPath;
        // Price feed
        priceFeedZOR = AggregatorV3Interface(
            _initValue.priceFeeds.priceFeedZOR
        );
        priceFeedLPPoolOtherToken = AggregatorV3Interface(
            _initValue.priceFeeds.priceFeedLPPoolOtherToken
        );
        priceFeedStablecoin = AggregatorV3Interface(
            _initValue.priceFeeds.priceFeedStablecoin
        );

        // Ownable
        __Ownable_init();
    }

    /* Structs */

    struct ZorroControllerXChainSwapParams {
        address[] USDCToZorroPath;
        address[] USDCToZorroLPPoolOtherTokenPath;
    }

    struct ZorroControllerXChainBridgeParams {
        uint256 chainId;
        uint256 homeChainId;
        uint256[] ZorroChainIDs;
        bytes[] controllerContracts; // Must be same length as ZorroChainIDs
        uint16[] LZChainIDs; // Must be same length as ZorroChainIDs
        uint256[] stargateDestPoolIds; // Must be same length as ZorroChainIDs
        address stargateRouter;
        address layerZeroEndpoint;
        uint256 stargateSwapPoolId;
    }

    struct ZorroControllerXChainPriceFeedParams {
        address priceFeedZOR;
        address priceFeedLPPoolOtherToken;
        address priceFeedStablecoin;
    }

    struct ZorroControllerXChainInit {
        // Tokens
        address defaultStablecoin;
        address ZORRO;
        address zorroLPPoolOtherToken;
        // Contracts
        address zorroStakingVault;
        address uniRouterAddress;
        address homeChainZorroController;
        address currentChainController;
        address publicPool;
        // Bridge
        ZorroControllerXChainBridgeParams bridge;
        // Swaps
        ZorroControllerXChainSwapParams swaps;
        // Price feed
        ZorroControllerXChainPriceFeedParams priceFeeds;
    }
}
