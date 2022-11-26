// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import "../interfaces/IAMMFarm.sol";

import "../interfaces/Zorro/Vaults/IVaultStandardAMM.sol";

import "./actions/_VaultActionsStandardAMM.sol";

import "./_VaultBase.sol";

/// @title VaultStandardAMM: abstract base class for all PancakeSwap style AMM contracts. Maximizes yield in AMM.
contract VaultStandardAMM is IVaultStandardAMM, VaultBase {
    /* Libraries */

    using SafeERC20Upgradeable for IERC20Upgradeable;
    using PriceFeed for AggregatorV3Interface;

    /* Constructor */

    /// @notice Upgradeable constructor
    /// @param _initValue A VaultStandardAMMInit struct with all constructor params
    /// @param _timelockOwner The designated timelock controller address to act as owner
    function initialize(
        address _timelockOwner,
        VaultStandardAMMInit memory _initValue
    ) public initializer {
        // Super call
        VaultBase.initialize(_timelockOwner, _initValue.baseInit);
    }

    /* Investment Actions */

    /// @notice Performs necessary operations to convert USD into Want token and transfer back to sender
    /// @param _amountUSD The amount of USD to exchange for Want token (must already be deposited on this contract)
    /// @param _maxMarketMovementAllowed The max slippage allowed. 1000 = 0 %, 995 = 0.5%, etc.
    /// @return uint256 Amount of Want token obtained
    function exchangeUSDForWantToken(
        uint256 _amountUSD,
        uint256 _maxMarketMovementAllowed
    ) public override onlyZorroController whenNotPaused returns (uint256) {
        // Approve spending
        IERC20Upgradeable(defaultStablecoin).safeIncreaseAllowance(
            vaultActions,
            _amountUSD
        );

        // Perform exchange
        return
            VaultActionsStandardAMM(vaultActions).exchangeUSDForWantToken(
                _amountUSD,
                VaultActionsStandardAMM.ExchUSDToWantParams({
                    stablecoin: defaultStablecoin,
                    token0Address: token0Address,
                    token1Address: token1Address,
                    wantAddress: wantAddress,
                    stablecoinPriceFeed: priceFeeds[defaultStablecoin],
                    token0PriceFeed: priceFeeds[token0Address],
                    token1PriceFeed: priceFeeds[token1Address],
                    stablecoinToToken0Path: swapPaths[defaultStablecoin][token0Address],
                    stablecoinToToken1Path: swapPaths[defaultStablecoin][token1Address]
                }),
                _maxMarketMovementAllowed
            );
    }

    /// @notice Public function for farming Want token.
    function farm() public nonReentrant {
        _farm();
    }

    /// @notice Internal function for farming Want token. Responsible for staking Want token in a MasterChef/MasterApe-like contract
    function _farm() internal override {
        require(isFarmable, "!farmable");
        // Get the Want token stored on this contract
        uint256 wantBal = IERC20Upgradeable(wantAddress).balanceOf(
            address(this)
        );

        // Allow the farm contract (e.g. MasterChef/MasterApe) the ability to transfer up to the Want amount
        IERC20Upgradeable(wantAddress).safeIncreaseAllowance(
            farmContractAddress,
            wantBal
        );

        // Deposit the Want tokens in the Farm contract for the appropriate pool ID (PID)
        IAMMFarm(farmContractAddress).deposit(pid, wantBal);
    }

    /// @notice Internal function for unfarming Want token. Responsible for unstaking Want token from MasterChef/MasterApe contracts
    /// @param _wantAmt the amount of Want tokens to withdraw. If 0, will only harvest and not withdraw
    function _unfarm(uint256 _wantAmt) internal override {
        // Withdraw the Want tokens from the Farm contract pool
        IAMMFarm(farmContractAddress).withdraw(pid, _wantAmt);
    }

    /// @notice Converts Want token back into USD to be ready for withdrawal, transfers back to sender
    /// @param _amount The Want token quantity to exchange
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
        // Approve spending
        IERC20Upgradeable(wantAddress).safeIncreaseAllowance(
            vaultActions,
            _amount
        );

        // Perform exchange
        return
            VaultActionsStandardAMM(vaultActions).exchangeWantTokenForUSD(
                _amount,
                VaultActionsStandardAMM.ExchWantToUSDParams({
                    token0PriceFeed: priceFeeds[token0Address],
                    token1PriceFeed: priceFeeds[token1Address],
                    stablecoinPriceFeed: priceFeeds[defaultStablecoin],
                    token0Address: token0Address,
                    token1Address: token1Address,
                    stablecoin: defaultStablecoin,
                    token0ToStablecoinPath: swapPaths[token0Address][defaultStablecoin],
                    token1ToStablecoinPath: swapPaths[token1Address][defaultStablecoin],
                    wantAddress: wantAddress,
                    poolAddress: poolAddress
                }),
                _maxMarketMovementAllowed
            );
    }
}

contract TraderJoe_ZOR_WAVAX is VaultStandardAMM {}

contract TraderJoe_WAVAX_USDC is VaultStandardAMM {}
