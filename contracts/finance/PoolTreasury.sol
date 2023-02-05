// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/finance/VestingWalletUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/// @title PoolTreasury: The treasury pool contract.
contract PoolTreasury is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    /* Libraries */
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /* Constructor */
    /// @notice Constructor
    /// @param _zorroTokenAddress The Zorro token address
    function initialize(
        address _zorroTokenAddress
    ) public initializer {
        // Set Zorro token address
        ZORRO = _zorroTokenAddress;

        // Set owner
        __Ownable_init();
    }

    /* State */
    address payable public vestingWallet; // Address of TreasuryVestingWallet
    address public ZORRO; // Address of ZOR token

    /* Setters */
    function setVestingWallet(address payable _vestingWallet) external onlyOwner {
        vestingWallet = _vestingWallet;
    }

    /* Functions */

    /// @notice Withdraws any ERC20 tokens from this contract
    /// @param _token The ERC20 token to withdraw
    /// @param _recipient The recipient of the withdrawn funds
    /// @param _quantity The amount of token to withdraw
    function withdraw(address _token, address _recipient, uint256 _quantity) public onlyOwner nonReentrant {
        IERC20Upgradeable(_token).safeTransfer(_recipient, _quantity);
    }

    /// @notice Withdraws any native ETH from this contract
    /// @param _recipient The recipient of the withdrawn funds
    /// @param _quantity The amount of token to withdraw
    function withdraw(address payable _recipient, uint256 _quantity) public onlyOwner nonReentrant {
        AddressUpgradeable.sendValue(_recipient, _quantity);
    }

    /// @notice Redeems vested ZOR token on the TreasuryVestingWallet contract to this contract
    function redeemZOR() public onlyOwner {
        TreasuryVestingWallet(vestingWallet).release(ZORRO);
    }

    /// @notice Allow this contract to receive ETH
    receive() external payable virtual {}
}

/// @title TreasuryVestingWallet: The vesting wallet for ZOR tokens, redeemable by PoolTreasury
contract TreasuryVestingWallet is VestingWalletUpgradeable {
    /* Constructor */

    /// @notice Constructor function to init the VestingWallet per OZ specs
    /// @param _beneficiaryAddress Address of beneficiary of vesting wallet
    /// @param _startTimestamp When to begin vesting
    /// @param _durationSeconds How long vesting period is
    function initialize(
        address _beneficiaryAddress,
        uint64 _startTimestamp,
        uint64 _durationSeconds
    ) public initializer {
        super.__VestingWallet_init(
            _beneficiaryAddress,
            _startTimestamp,
            _durationSeconds
        );
    }
}
