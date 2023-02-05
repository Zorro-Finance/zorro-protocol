// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "./PoolTeam.sol";

/// @title PoolAdvisory: The advisory pool contract (for advisors).
/// @dev Follows a factory method to create vesting wallets for each new advisor
contract PoolAdvisory is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    /* Libraries */
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /* Constructor */
    /// @notice Constructor
    /// @param _zorroTokenAddress The Zorro token address
    /// @param _cliffSeconds The min time (cliff) before vested tokens can be redeemed
    /// @param _durationSeconds The total vesting period for tokens
    function initialize(
        address _zorroTokenAddress,
        uint64 _cliffSeconds,
        uint64 _durationSeconds
    ) public initializer {
        // Set Zorro token address
        ZORRO = _zorroTokenAddress;
        // Set vesting params
        cliffSeconds = _cliffSeconds;
        durationSeconds = _durationSeconds;

        // Set owner to deployer (initially)
        __Ownable_init();
    }

    /* State */

    address[] public advisors; // All registered advisors
    mapping(address => address) public vestingWallets; // Mapping of advisors to their VestingWallet addresses
    address public ZORRO; // Address of ZOR token
    uint64 public cliffSeconds; // Cliff period
    uint64 public durationSeconds; // Vesting period

    /* Functions */

    /// @notice Registers a new advisor and creates a corresponding vesting wallet
    /// @dev Starts vesting immediately
    /// @param _advisor The beneficiary address representing the advisor
    /// @param _amount The total amount of ZOR to vest for this advisor
    function registerAdvisor(address _advisor, uint256 _amount) external onlyOwner {
        // Calc existing ZOR balance on contract. Make sure _amount does not exceed
        uint256 _balZOR = IERC20Upgradeable(ZORRO).balanceOf(address(this));
        require(_balZOR >= _amount, "Exceeds advisory shares avail");

        // Instantiate VestingWallet
        address _vWallet = address(
            new TeamVestingWallet(
                _advisor,
                uint64(block.timestamp),
                durationSeconds,
                cliffSeconds
            )
        );

        // Save factory params in storage
        advisors.push(_advisor);
        vestingWallets[_advisor] = _vWallet;

        // Transfer funds to new wallet 
        IERC20Upgradeable(ZORRO).safeTransfer(_vWallet, _amount);
    }
}
