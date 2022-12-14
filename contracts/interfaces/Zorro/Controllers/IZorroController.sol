// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

/// @title IZorroControllerBase
interface IZorroControllerBase {
    /* Structs */

    // Info of each tranche.
    struct TrancheInfo {
        uint256 contribution; // The tranche-specific contribution for a given vault (Cx). Equivalent to the product of their contributed deposit and a time multiplier
        uint256 timeMultiplier; // The time multiplier factor for rewards
        uint256 rewardDebt; // The tranche's share of the amount of rewards accumulated in the vault to date (see README)
        uint256 durationCommittedInWeeks; // How many weeks the user committed to at the time of deposit for this tranche
        uint256 enteredVaultAt; // The block timestamp for which the user deposited into a Vault.
        uint256 exitedVaultAt; // The block timestamp for which the user finished withdrawal
    }

    // Info of each vault
    struct VaultInfo {
        IERC20Upgradeable want; // Want token contract.
        uint256 allocPoint; // How many allocation points assigned to this vault.
        uint256 lastRewardBlock; // Last block number that ZORRO distribution occurs.
        uint256 accZORRORewards; // Accumulated ZORRO rewards in this vault
        uint256 totalTrancheContributions; // Sum of all user contributions in this vault
        address vault; // Address of the Vault
    }

    /* Setters */

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

    /* Functions */

    function vaultLength() external view returns (uint256);

    function vaultInfo(uint256 _i) external view returns (IERC20Upgradeable, uint256, uint256, uint256, uint256, address);

    function vaultMapping(address _vault) external view returns (uint256);

    function trancheLength(uint256 _vid, address _user)
        external
        view
        returns (uint256);

    function updateVault(uint256 _vid) external returns (uint256);

    function inCaseTokensGetStuck(address _token, uint256 _amount) external;
}

/// @title IZorroControllerAnalytics
interface IZorroControllerAnalytics is IZorroControllerBase {
    function pendingZORRORewards(
        uint256 _vid,
        address _account,
        int256 _trancheId
    ) external view returns (uint256);

    function shares(
        uint256 _vid,
        address _account,
        int256 _trancheId
    ) external view returns (uint256);
}

/// @title IZorroControllerInvestment
interface IZorroControllerInvestment is IZorroControllerBase {
    /* Structs */

    struct WithdrawalResult {
        uint256 wantAmt; // Amount of Want token withdrawn
        uint256 rewardsDueXChain; // ZOR rewards due to the origin (cross chain) user
    }

    /* Events */

    event Deposit(
        address indexed account,
        bytes indexed foreignAccount,
        uint256 indexed vid,
        uint256 wantAmount
    );

    event Withdraw(
        address indexed account,
        bytes indexed foreignAccount,
        uint256 indexed vid,
        uint256 trancheId,
        uint256 wantAmount
    );
    event TransferInvestment(
        address account,
        uint256 indexed fromVid,
        uint256 indexed fromTrancheId,
        uint256 indexed toVid
    );

    /* Functions */

    function setIsTimeMultiplierActive(bool _isActive) external;

    function setZorroXChainEndpoint(address _contract) external;

    function deposit(
        uint256 _vid,
        uint256 _wantAmt,
        uint256 _weeksCommitted
    ) external;

    function depositFullService(
        uint256 _vid,
        uint256 _valueUSD,
        uint256 _weeksCommitted,
        uint256 _maxMarketMovement
    ) external;

    function depositFullServiceFromXChain(
        uint256 _vid,
        address _account,
        bytes memory _foreignAccount,
        uint256 _valueUSD,
        uint256 _weeksCommitted,
        uint256 _vaultEnteredAt,
        uint256 _maxMarketMovement
    ) external;

    function withdraw(
        uint256 _vid,
        uint256 _trancheId,
        bool _harvestOnly
    ) external returns (uint256);

    function withdrawalFullService(
        uint256 _vid,
        uint256 _trancheId,
        bool _harvestOnly,
        uint256 _maxMarketMovement
    ) external returns (uint256);

    function withdrawalFullServiceFromXChain(
        address _account,
        bytes memory _foreignAccount,
        uint256 _vid,
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
        uint256 _fromVid,
        uint256 _fromTrancheId,
        uint256 _toVid,
        uint256 _maxMarketMovement
    ) external;

    function withdrawAll(uint256 _vid) external;

    function repatriateRewards(uint256 _rewardsDue, address _destination) external;

    function handleAccXChainRewards(uint256 _totalMinted, uint256 _totalSlashed) external;
}

/// @title IZorroControllerVaultMgmt
interface IZorroControllerVaultMgmt is IZorroControllerBase {
    function add(
        uint256 _allocPoint,
        IERC20Upgradeable _want,
        bool _withUpdate,
        address _vault
    ) external;

    function set(
        uint256 _vid,
        uint256 _allocPoint,
        bool _withUpdate
    ) external;

    function massUpdateVaults() external returns (uint256);
}

/// @title IZorroController: Interface for Zorro Controller
interface IZorroController is
    IZorroControllerBase,
    IZorroControllerVaultMgmt,
    IZorroControllerInvestment,
    IZorroControllerAnalytics
{

}
