// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./ILayerZeroReceiver.sol";

import "./IStargateReceiver.sol";

/// @title IZorroControllerXChain
interface IZorroControllerXChainBase {
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
    function checkXChainDepositFee(
        uint256 _chainId,
        bytes memory _dstContract,
        uint256 _pid,
        uint256 _valueUSDC,
        uint256 _weeksCommitted,
        uint256 _maxMarketMovement,
        bytes memory _destWallet
    ) external view returns (uint256);

    function sendXChainDepositRequest(
        uint256 _zorroChainId,
        uint256 _pid,
        uint256 _valueUSDC,
        uint256 _weeksCommitted,
        uint256 _maxMarketMovement,
        bytes memory _destWallet
    ) external payable;

    function receiveXChainDepositRequest(
        uint256 _pid,
        uint256 _valueUSDC,
        uint256 _weeksCommitted,
        uint256 _maxMarketMovement,
        bytes memory _originAccount,
        address _destAccount
    ) external;
}

/// @title IZorroControllerXChainEarn
interface IZorroControllerXChainEarn is IZorroControllerXChainBase {
    function setZorroLPPoolOtherToken(address _token) external;

    function setZorroStakingVault(address _contract) external;

    function setUniRouterAddress(address _contract) external;

    function setSwapPaths(
        address[] calldata _USDCToZorroPath,
        address[] calldata _USDCToZorroLPPoolOtherTokenPath
    ) external;

    function setPriceFeeds(address[] calldata _priceFeeds) external;

    function checkXChainDistributeEarningsFee(
        uint256 _amountUSDCBuyback,
        uint256 _amountUSDCRevShare,
        uint256 _accSlashedRewards,
        uint256 _maxMarketMovement
    ) external view returns (uint256);

    function sendXChainDistributeEarningsRequest(
        uint256 _pid,
        uint256 _buybackAmountUSDC,
        uint256 _revShareAmountUSDC,
        uint256 _maxMarketMovement
    ) external payable;

    function receiveXChainDistributionRequest(
        uint256 _remoteChainId,
        uint256 _amountUSDCBuyback,
        uint256 _amountUSDCRevShare,
        uint256 _accSlashedRewards,
        uint256 _maxMarketMovement
    ) external;
}

/// @title IZorroControllerXChainWithdraw
interface IZorroControllerXChainWithdraw is IZorroControllerXChainBase {
    function checkXChainWithdrawalFee(
        uint256 _zorroChainId,
        uint256 _pid,
        uint256 _trancheId,
        uint256 _maxMarketMovement,
        uint256 _gasForDestinationLZReceive
    ) external view returns (uint256);

    function checkXChainRepatriationFee(
        uint256 _originChainId,
        uint256 _pid,
        uint256 _trancheId,
        bytes memory _originRecipient,
        uint256 _burnableZORRewards,
        uint256 _rewardsDue
    ) external view returns (uint256);

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
        uint256 _burnableZORRewards,
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
