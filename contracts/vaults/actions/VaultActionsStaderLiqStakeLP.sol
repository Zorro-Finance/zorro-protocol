// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../../interfaces/Stader/IStakeManager.sol";

import "../../interfaces/IWETH.sol";

import "../../libraries/SafeSwap.sol";

import "./_VaultActionsLiqStakeLP.sol";

contract VaultActionsStaderLiqStakeLP is VaultActionsLiqStakeLP {
    /* Libraries */

    using PriceFeed for AggregatorV3Interface;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /* Functions */

    /// @notice Deposits liquid stake on protocol
    /// @param _amount The amount of ETH to liquid stake
    /// @param _token0 The base (underlying) token to supply
    /// @param _liqStakeToken The liquid staking synthetic token returned after staking the underlying
    /// @param _liqStakePool The liquid staking pool address
    function _liquidStake(
        uint256 _amount,
        address _token0,
        address _liqStakeToken,
        address _liqStakePool
    ) internal override {
        // Preflight checks
        require(_amount >= 0.5 ether, "minLiqStake");

        // Unwrap ETH
        IWETH(_token0).withdraw(_amount);

        // Get native ETH balance
        uint256 _bal = address(this).balance;

        // Require balance to be >= amount
        require(_bal >= _amount, "insufficientLiqStakeBal");

        // Call deposit func
        IStakeManager(_liqStakePool).deposit{value: _amount}();

        // Calc balance of liquid staking token
        uint256 _balLiqToken = IERC20Upgradeable(_liqStakeToken).balanceOf(
            address(this)
        );

        // Transfer synth token to sender
        IERC20Upgradeable(_liqStakeToken).safeTransfer(
            msg.sender,
            _balLiqToken
        );
    }

    /// @notice Withdraws liquid stake on protocol
    /// @param _swapParams The SafeSwapParams object with swap information
    function _liquidUnstake(SafeSwapUni.SafeSwapParams memory _swapParams)
        internal
        override
    {
        // Transfer amount IN
        IERC20Upgradeable(_swapParams.token0).safeTransferFrom(
            msg.sender,
            address(this),
            _swapParams.amountIn
        );

        // Swap sETH to WETH
        _safeSwap(_swapParams);
    }
}