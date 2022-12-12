// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../LayerZero/ILayerZeroReceiver.sol";

import "../../Stargate/IStargateReceiver.sol";

/// @title IZorroControllerXChain
interface IZorroControllerXChainBase {
    /* Structs */

    // Stargate swaps
    struct StargateSwapPayload {
        uint256 chainId;
        uint256 qty;
        bytes dstContract;
        bytes payload;
        uint256 maxMarketMovement;
    }

    // LayerZero messages
    struct LZMessagePayload {
        uint256 zorroChainId;
        bytes destinationContract;
        bytes payload;
        address payable refundAddress;
        address _zroPaymentAddress;
        bytes adapterParams;
    }

    /* Functions */
    
    function setControllerContract(
        uint256 _zorroChainId,
        bytes calldata _controller
    ) external;

    function setZorroChainToLZMap(uint256 _zorroChainId, uint16 _lzChainId)
        external;

    function setStargateDestPoolIds(
        uint256 _zorroChainId,
        uint16 _stargatePoolId
    ) external;

    function setLayerZeroParams(
        address _stargateRouter,
        uint256 _stargateSwapPoolId,
        address _layerZeroEndpoint
    ) external;
}

/// @title IZorroControllerXChainDeposit
interface IZorroControllerXChainDeposit is IZorroControllerXChainBase {
    function sendXChainDepositRequest(
        uint256 _zorroChainId,
        uint256 _pid,
        uint256 _valueUSD,
        uint256 _weeksCommitted,
        uint256 _maxMarketMovement,
        bytes memory _destWallet
    ) external payable;

    function receiveXChainDepositRequest(
        uint256 _pid,
        uint256 _valueUSD,
        uint256 _weeksCommitted,
        uint256 _maxMarketMovement,
        bytes memory _originAccount,
        address _destAccount
    ) external;
}

/// @title IZorroControllerXChainEarn
interface IZorroControllerXChainEarn is IZorroControllerXChainBase {
    /* Events */

    event XChainDistributeEarnings(
        uint256 indexed _remoteChainId,
        uint256 indexed _buybackAmountUSD,
        uint256 indexed _revShareAmountUSD
    );

    event RemovedSlashedRewards(uint256 indexed _amountZOR);

    /* Functions */
    
    function setZorroLPPoolOtherToken(address _token) external;

    function setZorroStakingVault(address _contract) external;

    function setUniRouterAddress(address _contract) external;

    function setSwapPaths(
        address[] calldata _stablecoinToZorroPath,
        address[] calldata _stablecoinToZorroLPPoolOtherTokenPath
    ) external;

    function setPriceFeeds(address[] calldata _priceFeeds) external;

    function sendXChainDistributeEarningsRequest(
        uint256 _pid,
        uint256 _buybackAmountUSD,
        uint256 _revShareAmountUSD,
        uint256 _maxMarketMovement
    ) external payable;

    function receiveXChainDistributionRequest(
        uint256 _remoteChainId,
        uint256 _amountUSDBuyback,
        uint256 _amountUSDRevShare,
        uint256 _accSlashedRewards,
        uint256 _maxMarketMovement
    ) external;
}

/// @title IZorroControllerXChainWithdraw
interface IZorroControllerXChainWithdraw is IZorroControllerXChainBase {
    /* Events */
    
    event XChainRepatriation(
        uint256 indexed _pid,
        address indexed _originRecipient,
        uint256 _trancheId,
        uint256 _originChainId
    );

    /* Functions */

    function sendXChainWithdrawalRequest(
        uint256 _destZorroChainId,
        uint256 _pid,
        uint256 _trancheId,
        uint256 _maxMarketMovement,
        uint256 _gasForDestinationLZReceive
    ) external payable;

    function receiveXChainWithdrawalRequest(
        uint256 _originChainId,
        bytes memory _originAccount,
        uint256 _pid,
        uint256 _trancheId,
        uint256 _maxMarketMovement
    ) external;

    function receiveXChainRepatriationRequest(
        uint256 _originChainId,
        uint256 _pid,
        uint256 _trancheId,
        bytes memory _originRecipient,
        uint256 _rewardsDue
    ) external;
}

/// @title IZorroControllerXChainReceiver
interface IZorroControllerXChainReceiver is
    ILayerZeroReceiver,
    IStargateReceiver,
    IZorroControllerXChainDeposit,
    IZorroControllerXChainEarn,
    IZorroControllerXChainWithdraw
{

}

/// @title IZorroControllerXChain
interface IZorroControllerXChain is
    IZorroControllerXChainBase,
    IZorroControllerXChainDeposit,
    IZorroControllerXChainEarn,
    IZorroControllerXChainWithdraw,
    IZorroControllerXChainReceiver
{

}
