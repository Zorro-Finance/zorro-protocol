// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./_ZorroControllerInvestment.sol";

import "../interfaces/IAMMRouter02.sol";

import "../interfaces/IVault.sol";

import "../libraries/SafeSwap.sol";

import "../interfaces/ILayerZeroEndpoint.sol";

import "../interfaces/IStargateRouter.sol";

import "../interfaces/IZorroControllerXChain.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

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
    using SafeMath for uint256;

    /* Constructor */

    /// @notice Upgradeable constructor
    /// @param _timelockOwner The timelock contract that shall own this contract
    /// @param _initValue a ZorroControllerXChainInit struct for initializing this contract
    function initialize(
        address _timelockOwner,
        ZorroControllerXChainInit memory _initValue
    ) public {
        // Base
        // mapping(uint256 => bytes) public controllerContractsMap; // Mapping of Zorro chain ID to endpoint contract
        // mapping(uint256 => uint16) public ZorroChainToLZMap; // Mapping of Zorro Chain ID to Stargate/LayerZero Chain ID
        // mapping(uint16 => uint256) public LZChainToZorroMap; // Mapping of Stargate/LayerZero Chain ID to Zorro Chain ID
        // address public stargateRouter; // Address to on-chain Stargate router
        // uint256 public stargateSwapPoolId; // Address of the pool to swap from on this contract
        // mapping(uint256 => uint256) public stargateDestPoolIds; // Mapping from Zorro chain ID to Stargate dest Pool for the same token
        // address public layerZeroEndpoint; // Address to on-chain LayerZero endpoint

        // for (uint16 i = 0; i < _initValue.xChain.ZorroChainIDs.length; ++i) {
        //     uint256 _zChainId = _initValue.xChain.ZorroChainIDs[i];

        //     controllerContractsMap[_zChainId] = _initValue
        //         .xChain
        //         .controllerContracts[i];
        //     ZorroChainToLZMap[_zChainId] = _initValue.xChain.LZChainIDs[i];
        //     LZChainToZorroMap[_initValue.xChain.LZChainIDs[i]] = _zChainId;
        //     stargateDestPoolIds[_zChainId] = _initValue
        //         .xChain
        //         .stargateDestPoolIds[i];
        // }

        // Withdraw
        

        // Earn
        // uint256 public accumulatedSlashedRewards; // Accumulated ZOR rewards that need to be minted in batch on the home chain. Should reset to zero periodically
        // // TODO: Constructor, setter
        // // Tokens
        // address public tokenUSDC;
        // address public zorroLPPoolOtherToken;
        // // Contracts
        // address public zorroStakingVault;
        // address public uniRouterAddress;
        // // Paths
        // address[] public USDCToZorroPath;
        // address[] public USDCToZorroLPPoolOtherTokenPath;
        // // Price feeds
        // AggregatorV3Interface public priceFeedZOR;
        // AggregatorV3Interface public priceFeedLPPoolOtherToken;

        // Timelock
        transferOwnership(_timelockOwner);
    }

    /* Structs */

    struct ZorroControllerXChainInit {
        address defaultStablecoin;
        address ZORRO;
        address homeChainZorroController;
        address currentChainController;
        address publicPool;
        uint256 chainId;
        uint256 homeChainId;
    }
}
