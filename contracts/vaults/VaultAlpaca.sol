// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../interfaces/Zorro/Vaults/IVaultAlpaca.sol";

import "./actions/VaultActionsAlpaca.sol";

import "./_VaultBase.sol";

/// @title Vault contract for Alpaca strategies
contract VaultAlpaca is IVaultAlpaca, VaultBase {
    /* Libraries */

    using SafeERC20Upgradeable for IERC20Upgradeable;
    using PriceFeed for AggregatorV3Interface;

    /* Constructor */

    /// @notice Upgradeable constructor
    /// @param _initValue A VaultAlpacaInit struct containing all init values
    /// @param _timelockOwner The designated timelock controller address to act as owner
    function initialize(
        address _timelockOwner,
        VaultAlpacaInit memory _initValue
    ) public initializer {
        // Super call
        VaultBase.initialize(_timelockOwner, _initValue.baseInit);
    }

    /* Investment Actions */

    /// @notice Performs necessary operations to convert USD into Want token
    /// @param _amountUSD The USD quantity to exchange (must already be deposited)
    /// @param _maxMarketMovementAllowed The max slippage allowed. 1000 = 0 %, 995 = 0.5%, etc.
    /// @return uint256 Amount of Want token obtained
    function exchangeUSDForWantToken(
        uint256 _amountUSD,
        uint256 _maxMarketMovementAllowed
    ) public override onlyZorroController whenNotPaused returns (uint256) {
        // Allow spending
        IERC20Upgradeable(defaultStablecoin).safeIncreaseAllowance(
            vaultActions,
            _amountUSD
        );

        // Exchange
        return
            VaultActionsAlpaca(vaultActions).exchangeUSDForWantToken(
                _amountUSD,
                VaultActionsAlpaca.ExchangeUSDForWantParams({
                    token0Address: token0Address,
                    stablecoin: defaultStablecoin,
                    tokenZorroAddress: ZORROAddress,
                    token0PriceFeed: priceFeeds[token0Address],
                    stablecoinPriceFeed: priceFeeds[defaultStablecoin],
                    stablecoinToToken0Path: swapPaths[defaultStablecoin][token0Address],
                    poolAddress: poolAddress,
                    wantAddress: wantAddress
                }),
                _maxMarketMovementAllowed
            );
    }

    /// @notice Public function for farming Want token.
    function farm() public virtual nonReentrant {
        _farm();
    }

    /// @notice Internal function for farming Want token. Responsible for staking Want token in a MasterChef/MasterApe-like contract
    function _farm() internal override {
        require(isFarmable, "!farmable");

        // Get the Want token stored on this contract
        uint256 _wantAmt = IERC20Upgradeable(wantAddress).balanceOf(
            address(this)
        );

        // Allow the farm contract (e.g. MasterChef) the ability to transfer up to the Want amount
        IERC20Upgradeable(wantAddress).safeIncreaseAllowance(
            farmContractAddress,
            _wantAmt
        );

        // Deposit the Want tokens in the Farm contract
        IFairLaunch(farmContractAddress).deposit(address(this), pid, _wantAmt);
    }

    /// @notice Internal function for unfarming Want token. Responsible for unstaking Want token from MasterChef/MasterApe contracts
    /// @param _wantAmt the amount of Want tokens to withdraw. If 0, will only harvest and not withdraw
    function _unfarm(uint256 _wantAmt) internal override {
        // Withdraw the Want tokens from the Farm contract
        IFairLaunch(farmContractAddress).withdraw(address(this), pid, _wantAmt);
    }

    /// @notice Converts Want token back into USD to be ready for withdrawal and transfers to sender
    /// @param _amount The Want token quantity to exchange (must be deposited beforehand)
    /// @param _maxMarketMovementAllowed The max slippage allowed for swaps. 1000 = 0 %, 995 = 0.5%, etc.
    /// @return uint256 Amount of USD token obtained
    function exchangeWantTokenForUSD(
        uint256 _amount,
        uint256 _maxMarketMovementAllowed
    )
        public
        virtual
        override
        onlyZorroController
        whenNotPaused
        returns (uint256)
    {
        // Allow spending
        IERC20Upgradeable(wantAddress).safeIncreaseAllowance(
            vaultActions,
            _amount
        );

        // Exchange
        return
            VaultActionsAlpaca(vaultActions).exchangeWantTokenForUSD(
                _amount,
                VaultActionsAlpaca.ExchangeWantTokenForUSDParams({
                    token0Address: token0Address,
                    stablecoin: defaultStablecoin,
                    wantAddress: wantAddress,
                    poolAddress: poolAddress,
                    token0PriceFeed: priceFeeds[token0Address],
                    stablecoinPriceFeed: priceFeeds[defaultStablecoin],
                    token0ToStablecoinPath: swapPaths[token0Address][defaultStablecoin]
                }),
                _maxMarketMovementAllowed
            );
    }
}

contract VaultAlpacaLeveragedBTCB is VaultAlpaca {}
