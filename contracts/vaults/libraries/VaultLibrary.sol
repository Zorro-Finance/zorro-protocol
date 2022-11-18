// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../../libraries/SafeSwap.sol";

import "../../libraries/PriceFeed.sol";

import "../../interfaces/Alpaca/IAlpacaFairLaunch.sol";

import "../../interfaces/Alpaca/IAlpacaVault.sol";

import "../../interfaces/IAMMRouter02.sol";

library VaultLibrary {
    /* Libs */
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeSwapUni for IAMMRouter02;

    /* Structs */
    struct VaultAddresses {
        address govAddress;
        address zorroControllerAddress;
        address zorroXChainController;
        address ZORROAddress;
        address zorroStakingVault;
        address wantAddress;
        address token0Address;
        address token1Address;
        address earnedAddress;
        address farmContractAddress;
        address rewardsAddress;
        address poolAddress;
        address uniRouterAddress;
        address zorroLPPool;
        address zorroLPPoolOtherToken;
        address defaultStablecoin;
    }

    struct VaultFees {
        uint256 controllerFee;
        uint256 buyBackRate;
        uint256 revShareRate;
        uint256 entranceFeeFactor;
        uint256 withdrawFeeFactor;
    }

    struct VaultPriceFeeds {
        address token0PriceFeed;
        address token1PriceFeed;
        address earnTokenPriceFeed;
        address ZORPriceFeed;
        address lpPoolOtherTokenPriceFeed;
        address stablecoinPriceFeed;
    }

    struct ExchangeRates {
        uint256 earn; // Exchange rate of earn token, times 1e12
        uint256 ZOR; // Exchange rate of ZOR token, times 1e12
        uint256 lpPoolOtherToken; // Exchange rate of token paired with ZOR in LP pool, times 1e12
        uint256 stablecoin; // Exchange rate of stablecoin (e.g. USDC), times 1e12
    }

    struct SwapEarnedToUSDParams {
        address earnedAddress;
        address stablecoin;
        address[] earnedToStablecoinPath;
        address uniRouterAddress;
        uint256 stablecoinExchangeRate;
    }

    /* Utilities */

    /// @notice Gets the swap path in the opposite direction of a trade
    /// @param _path The swap path to be reversed
    /// @return _newPath An reversed path array
    function reversePath(address[] memory _path)
        public
        pure
        returns (address[] memory _newPath)
    {
        uint256 _pathLength = _path.length;
        _newPath = new address[](_pathLength);
        for (uint16 i = 0; i < _pathLength; ++i) {
            _newPath[i] = _path[_path.length.sub(1).sub(i)];
        }
    }

    /// @notice Safely swaps tokens using the most suitable protocol based on token
    /// @param _uniRouterAddress Address of IAMM router
    /// @param _swapParams SafeSwapParams for swap
    /// @param _decimals Array of decimals for amount In, amount Out
    function safeSwap(
        address _uniRouterAddress,
        SafeSwapParams memory _swapParams,
        uint8[] memory _decimals
    ) public {
        // Allowance
        IERC20Upgradeable(_swapParams.token0).safeIncreaseAllowance(
            _uniRouterAddress,
            _swapParams.amountIn
        );
        // Otherwise, swap on normal Pancakeswap (or Uniswap clone) for simplicity & liquidity
        // Determine exchange rates using price feed oracle
        uint256[] memory _priceTokens = new uint256[](2);
        _priceTokens[0] = _swapParams.priceToken0;
        _priceTokens[1] = _swapParams.priceToken1;
        IAMMRouter02(_uniRouterAddress).safeSwap(
            _swapParams.amountIn,
            _priceTokens,
            _swapParams.maxMarketMovementAllowed,
            _swapParams.path,
            _decimals,
            _swapParams.destination,
            block.timestamp.add(600)
        );
    }

    /// @notice Swaps Earn token to USD and sends to destination specified
    /// @param _earnedAmount Quantity of Earned tokens
    /// @param _destination Address to send swapped USD to
    /// @param _maxMarketMovementAllowed Slippage factor. 950 = 5%, 990 = 1%, etc.
    /// @param _rates ExchangeRates struct with realtime rates information for swaps
    function swapEarnedToUSD(
        uint256 _earnedAmount,
        address _destination,
        uint256 _maxMarketMovementAllowed,
        VaultLibrary.ExchangeRates memory _rates,
        SwapEarnedToUSDParams memory _swapEarnedToUSDParams
    ) public {
        // Get exchange rate

        // Get decimal info
        uint8[] memory _decimals0 = new uint8[](2);
        _decimals0[0] = ERC20Upgradeable(_swapEarnedToUSDParams.earnedAddress)
            .decimals();
        _decimals0[1] = ERC20Upgradeable(_swapEarnedToUSDParams.stablecoin)
            .decimals();

        // Swap earn to USD
        safeSwap(
            _swapEarnedToUSDParams.uniRouterAddress,
            SafeSwapParams({
                amountIn: _earnedAmount,
                priceToken0: _rates.earn,
                priceToken1: _swapEarnedToUSDParams.stablecoinExchangeRate,
                token0: _swapEarnedToUSDParams.earnedAddress,
                token1: _swapEarnedToUSDParams.stablecoin,
                maxMarketMovementAllowed: _maxMarketMovementAllowed,
                path: _swapEarnedToUSDParams.earnedToStablecoinPath,
                destination: _destination
            }),
            _decimals0
        );
    }
}