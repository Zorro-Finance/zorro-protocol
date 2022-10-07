// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

/// @title IZorroControllerBase
interface IZorroControllerBase {
    function setKeyAddresses(address _ZORRO, address _defaultStablecoin)
        external;

    function setZorroContracts(address _publicPool, address _zorroStakingVault)
        external;

    function setStartBlock(uint256 _startBlock) external;

    function setRewardsParams(
        uint256 _blocksPerDay,
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

    function setZorroControllerOracle(address _zorroControllerOracle) external;

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

    function setStablecoinToZORPath(address[] memory _path) external;

    function setStablecoinToZorroLPPoolOtherTokenPath(address[] memory _path)
        external;

    function setPriceFeeds(
        address _priceFeedZOR,
        address _priceFeedLPPoolOtherToken
    ) external;

    function setZorroXChainEndpoint(address _contract) external;

    function deposit(
        uint256 _pid,
        uint256 _wantAmt,
        uint256 _weeksCommitted
    ) external;

    function depositFullService(
        uint256 _pid,
        uint256 _valueUSD,
        uint256 _weeksCommitted,
        uint256 _maxMarketMovement
    ) external;

    function depositFullServiceFromXChain(
        uint256 _pid,
        address _account,
        bytes memory _foreignAccount,
        uint256 _valueUSD,
        uint256 _weeksCommitted,
        uint256 _vaultEnteredAt,
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

    function withdrawalFullServiceFromXChain(
        address _account,
        bytes memory _foreignAccount,
        uint256 _pid,
        uint256 _trancheId,
        bool _harvestOnly,
        uint256 _maxMarketMovement
    )
        external
        returns (
            uint256 _amountUSD,
            uint256 _rewardsDueXChain
        );

    function transferInvestment(
        uint256 _fromPid,
        uint256 _fromTrancheId,
        uint256 _toPid,
        uint256 _maxMarketMovement
    ) external;

    function withdrawAll(uint256 _pid) external;

    function repatriateRewards(uint256 _rewardsDue, address _destination) external;

    function handleAccXChainRewards(uint256 _totalMinted, uint256 _totalSlashed) external;
}

/// @title IZorroControllerPoolMgmt
interface IZorroControllerPoolMgmt is IZorroControllerBase {
    function add(
        uint256 _allocPoint,
        IERC20Upgradeable _want,
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

/// @title IZorroController: Interface for Zorro Controller
interface IZorroController is
    IZorroControllerBase,
    IZorroControllerPoolMgmt,
    IZorroControllerInvestment,
    IZorroControllerAnalytics
{

}
