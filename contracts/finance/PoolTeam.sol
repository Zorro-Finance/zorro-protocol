// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

import "@openzeppelin/contracts/finance/VestingWallet.sol";

/// @title PoolTeam: The team pool contract (for founders).
contract PoolTeam is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
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
    }

    /* State */
    address payable public vestingWallet; // Address of TeamVestingWallet
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

    /// @notice Redeems vested ZOR token on the TeamVestingWallet contract to this contract
    function redeemZOR() public onlyOwner {
        TeamVestingWallet(vestingWallet).release(ZORRO);
    }

    /// @notice Allow this contract to receive ETH
    receive() external payable virtual {}
}

/// @title TreasuryVestingWallet: The vesting wallet for ZOR tokens, redeemable by PoolTeam
contract TeamVestingWallet is VestingWallet, Ownable {
    /* Constructor */
    constructor(
        address beneficiaryAddress,
        uint64 startTimestamp,
        uint64 durationSeconds,
        uint64 _cliffSeconds
    ) payable VestingWallet(beneficiaryAddress, startTimestamp, durationSeconds) {
        require(cliffSeconds < durationSeconds, "cliff too large");
        cliffSeconds = _cliffSeconds;
    }

    /* State */
    uint256 public cliffSeconds; // Cliff duration in seconds from start()

    /* Functions */

    /// @notice Modified version of VestingWallet.release() (checks to see if cliff is met first)
    /// @param token The token to release
    function release(address token) public override {
        // Check cliff period
        require(block.timestamp - start() >= cliffSeconds, "cliff not yet reached");

        // Run release() as normal
        super.release(token);
    }
}