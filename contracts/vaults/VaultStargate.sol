// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../interfaces/Uniswap/IAMMFarm.sol";

import "../interfaces/Stargate/IStargateRouter.sol";

import "../interfaces/Stargate/IStargateLPStaking.sol";

import "../interfaces/Zorro/Vaults/IVaultStargate.sol";

import "./actions/VaultActionsStargate.sol";

import "./_VaultBase.sol";

/// @title Vault contract for Stargate single token strategies (e.g. for lending bridgeable tokens)
contract VaultStargate is IVaultStargate, VaultBase {
    /* Libraries */

    using SafeERC20Upgradeable for IERC20Upgradeable;
    using PriceFeed for AggregatorV3Interface;

    /* Constructor */

    /// @notice Upgradeable constructor
    /// @param _initValue A VaultStargateInit struct containing all init values
    /// @param _timelockOwner The designated timelock controller address to act as owner
    function initialize(
        address _timelockOwner,
        VaultStargateInit memory _initValue
    ) public initializer {
        // Addresses
        stargateRouter = _initValue.stargateRouter;
        stargatePoolId = _initValue.stargatePoolId;

        // Super call
        VaultBase.initialize(_timelockOwner, _initValue.baseInit);
    }

    /* State */

    address public stargateRouter; // Stargate Router for adding/removing liquidity etc.
    uint16 public stargatePoolId; // Stargate Pool that tokens shall be lent to

    /* Setters */

    function setStargatePoolId(uint16 _poolId) external onlyOwner {
        stargatePoolId = _poolId;
    }

    function setStargateRouter(address _router) external onlyOwner {
        stargateRouter = _router;
    }

    /* Investment Actions */

    /// @notice Public function for farming Want token.
    function farm() public virtual nonReentrant {
        _farm();
    }

    /// @notice Internal function for farming Want token. Responsible for staking Want token in a MasterChef/MasterApe-like contract
    function _farm() internal override {
        // Get the Want token stored on this contract
        uint256 _wantAmt = IERC20Upgradeable(wantAddress).balanceOf(
            address(this)
        );

        // Increase allowance
        IERC20Upgradeable(wantAddress).safeIncreaseAllowance(
            stargateRouter,
            _wantAmt
        );

        // Deposit token to get Want token
        IStargateRouter(stargateRouter).addLiquidity(
            stargatePoolId,
            _wantAmt,
            address(this)
        );

        // Calc LP balance
        uint256 _lpBal = IERC20Upgradeable(poolAddress).balanceOf(address(this));

        // Allow the farm contract (e.g. MasterChef) the ability to transfer up to the Want amount
        IERC20Upgradeable(wantAddress).safeIncreaseAllowance(
            farmContractAddress,
            _lpBal
        );

        // Deposit the Want tokens in the Farm contract
        IStargateLPStaking(farmContractAddress).deposit(pid, _lpBal);
    }

    /// @notice Internal function for unfarming Want token. Responsible for unstaking Want token from MasterChef/MasterApe contracts
    /// @param _wantAmt the amount of Want tokens to withdraw. If 0, will only harvest and not withdraw
    function _unfarm(uint256 _wantAmt) internal override {
        // Withdraw the Want tokens from the Farm contract
        IStargateLPStaking(farmContractAddress).withdraw(pid, _wantAmt);

        // Calc lp balance
        uint256 _lpBal = IERC20Upgradeable(poolAddress).balanceOf(address(this));

        // Approve
        IERC20Upgradeable(poolAddress).safeIncreaseAllowance(
            stargateRouter,
            _lpBal
        );

        // Withdraw Want token to get Token0
        IStargateRouter(stargateRouter).instantRedeemLocal(
            stargatePoolId,
            _lpBal,
            address(this)
        );
    }
}

contract StargateUSDCOnAVAX is VaultStargate {}
