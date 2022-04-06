// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./ILayerZeroReceiver.sol";

import "./IStargateReceiver.sol";

/// @title IZorroControllerBase
interface IZorroControllerBase {
    function setKeyAddresses(address _ZORRO, address _defaultStablecoin)
        external;

    function setZorroContracts(address _publicPool, address _zorroStakingVault)
        external; 

    function setStartBlock(uint256 _startBlock) external; 

    function setRewardsParams(
        uint256[] calldata _blockParams,
        uint256[] calldata _dailyDistFactors,
        uint256 _chainMultiplier,
        uint256 _baseRewardRateBasisPoints
    ) external;

    function setTargetTVLCaptureBasisPoints(
        uint256 _targetTVLCaptureBasisPoints
    ) external;

    function setXChainParams(
        uint256 _chainId,
        uint256 _homeChainId,
        address _homeChainZorroController
    ) external;

    function setZorroControllerOracle(address _zorroControllerOracle)
        external;

    function poolLength() external view returns (uint256);

    function trancheLength(uint256 _pid, address _user)
        external
        view
        returns (uint256);

    function updatePool(uint256 _pid) external returns (uint256);

    function inCaseTokensGetStuck(address _token, uint256 _amount) external;
}

/// @title IZorroControllerAnalytics
interface IZorroControllerAnalytics is IZorroControllerBase {
    function pendingZORRORewards(
        uint256 _pid,
        address _account,
        int256 _trancheId
    ) external view returns (uint256);

    function stakedWantTokens(
        uint256 _pid,
        address _account,
        int256 _trancheId
    ) external view returns (uint256);
}

/// @title IZorroControllerInvestment
interface IZorroControllerInvestment is IZorroControllerBase {
    function setIsTimeMultiplierActive(bool _isActive) external;

    function setZorroLPPoolParams(
        address _zorroLPPool,
        address _zorroLPPoolOtherToken
    ) external; 

    function setUniRouter(address _uniV2Router) external;

    function setUSDCToZORPath(address[] memory _path) external;

    function setUSDCToZorroLPPoolOtherTokenPath(address[] memory _path)
        external;

    function setPriceFeeds(
        address _priceFeedZOR,
        address _priceFeedLPPoolOtherToken
    ) external;

    function deposit(
        uint256 _pid,
        uint256 _wantAmt,
        uint256 _weeksCommitted
    ) external;

    function depositFullService(
        uint256 _pid,
        uint256 _valueUSDC,
        uint256 _weeksCommitted,
        uint256 _maxMarketMovement
    ) external;

    function withdraw(
        uint256 _pid,
        uint256 _trancheId,
        bool _harvestOnly
    ) external returns (uint256);

    function withdrawalFullService(
        uint256 _pid,
        uint256 _trancheId,
        bool _harvestOnly,
        uint256 _maxMarketMovement
    ) external returns (uint256);

    function transferInvestment(
        uint256 _fromPid,
        uint256 _fromTrancheId,
        uint256 _toPid,
        uint256 _maxMarketMovement
    ) external;

    function withdrawAll(uint256 _pid) external;

    function getTimeMultiplier(uint256 durationInWeeks)
        external
        view
        returns (uint256);

    function getUserContribution(
        uint256 _liquidityCommitted,
        uint256 _timeMultiplier
    ) external pure returns (uint256);
}

/// @title IZorroControllerPoolMgmt
interface IZorroControllerPoolMgmt is IZorroControllerBase {
    function add(
        uint256 _allocPoint,
        IERC20 _want,
        bool _withUpdate,
        address _vault
    ) external;

    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) external;

    function massUpdatePools() external returns (uint256);
}

/// @title IZorroControllerXChain
interface IZorroControllerXChain is IZorroControllerInvestment {
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
interface IZorroControllerXChainDeposit is IZorroControllerXChain {
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
interface IZorroControllerXChainEarn is IZorroControllerXChain {
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
interface IZorroControllerXChainWithdraw is IZorroControllerXChain {
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
        uint256 _rewardsDue,
        uint256 _gasForDestinationLZReceive
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

/// @title IZorroController: Interface for Zorro Controller
interface IZorroController is
    IZorroControllerBase,
    IZorroControllerPoolMgmt,
    IZorroControllerInvestment,
    IZorroControllerAnalytics,
    IZorroControllerXChainReceiver
{

}
