// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../libraries/SafeSwap.sol";

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import "../libraries/PriceFeed.sol";

library VaultLibrary {
    /* Libs */
    using SafeMath for uint256;

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
        address tokenUSDCAddress;
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
}

library VaultLibraryAcryptosSingle {
    using SafeERC20 for IERC20;
    using SafeSwapBalancer for IBalancerVault;
    using SafeSwapUni for IAMMRouter02;
    using SafeMath for uint256;
    using PriceFeed for AggregatorV3Interface;

    /// @notice Safely swaps tokens using the most suitable protocol based on token
    /// @param _balancerVaultAddress Address of balancer vault
    /// @param _balancerPoolAddress Address of balancer pool
    /// @param _uniRouterAddress Address of IAMM router
    /// @param _swapParams SafeSwapParams for swap
    /// @param _decimals Array of decimals for amount In, amount Out
    /// @param _forAcryptos Whether one of the tokens is the ACS token
    function safeSwap(
        address _balancerVaultAddress,
        bytes32 _balancerPoolAddress,
        address _uniRouterAddress,
        SafeSwapParams memory _swapParams,
        uint8[] memory _decimals,
        bool _forAcryptos
    ) public {
        if (_forAcryptos) {
            // Allowance
            IERC20(_swapParams.token0).safeIncreaseAllowance(
                _balancerVaultAddress,
                _swapParams.amountIn
            );
            // If it's for the Acryptos tokens, swap on ACS Finance (Balancer clone) (Better liquidity for these tokens only)
            IBalancerVault(_balancerVaultAddress).safeSwap(
                _balancerPoolAddress,
                _swapParams,
                _decimals
            );
        } else {
            // Allowance
            IERC20(_swapParams.token0).safeIncreaseAllowance(
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
    }

    struct SwapEarnedToUSDCParams {
        AggregatorV3Interface tokenBUSDPriceFeed;
        address earnedAddress;
        address tokenBUSD;
        address tokenUSDCAddress;
        uint256 balancerACSWeightBasisPoints;
        uint256 balancerBUSDWeightBasisPoints;
        address[] earnedToUSDCPath;
        address uniRouterAddress;
        address balancerVaultAddress;
        bytes32 balancerPool;
    }

    /// @notice Swaps Earn token to USDC and sends to destination specified
    /// @param _earnedAmount Quantity of Earned tokens
    /// @param _destination Address to send swapped USDC to
    /// @param _maxMarketMovementAllowed Slippage factor. 950 = 5%, 990 = 1%, etc.
    /// @param _rates ExchangeRates struct with realtime rates information for swaps
    function swapEarnedToUSDC(
        uint256 _earnedAmount,
        address _destination,
        uint256 _maxMarketMovementAllowed,
        VaultLibrary.ExchangeRates memory _rates,
        SwapEarnedToUSDCParams memory _swapEarnedToUSDCParams
    ) public {
        // Get exchange rate
        uint256 _tokenBUSDExchangeRate = _swapEarnedToUSDCParams.tokenBUSDPriceFeed.getExchangeRate();

        // Get decimal info
        uint8[] memory _decimals0 = new uint8[](2);
        _decimals0[0] = ERC20(_swapEarnedToUSDCParams.earnedAddress).decimals();
        _decimals0[1] = ERC20(_swapEarnedToUSDCParams.tokenBUSD).decimals();
        // Get decimal info
        uint8[] memory _decimals1 = new uint8[](2);
        _decimals1[0] = _decimals0[1];
        _decimals1[1] = ERC20(_swapEarnedToUSDCParams.tokenUSDCAddress).decimals();
        
        // Swap ACS to BUSD (Balancer)
        safeSwap(
            _swapEarnedToUSDCParams.balancerVaultAddress,
            _swapEarnedToUSDCParams.balancerPool,
            _swapEarnedToUSDCParams.uniRouterAddress,
            SafeSwapParams({
                amountIn: _earnedAmount,
                priceToken0: _rates.earn,
                priceToken1: _tokenBUSDExchangeRate,
                token0: _swapEarnedToUSDCParams.earnedAddress,
                token1: _swapEarnedToUSDCParams.tokenBUSD,
                token0Weight: _swapEarnedToUSDCParams.balancerACSWeightBasisPoints,
                token1Weight: _swapEarnedToUSDCParams.balancerBUSDWeightBasisPoints,
                maxMarketMovementAllowed: _maxMarketMovementAllowed,
                path: _swapEarnedToUSDCParams.earnedToUSDCPath, // Unused
                destination: address(this)
            }),
            _decimals0,
            true
        );

        // BUSD balance
        uint256 _balBUSD = IERC20(_swapEarnedToUSDCParams.tokenBUSD).balanceOf(
            address(this)
        );

        // Swap path
        address[] memory _path = new address[](2);
        _path[0] = _swapEarnedToUSDCParams.tokenBUSD;
        _path[1] = _swapEarnedToUSDCParams.tokenUSDCAddress;

        // Swap BUSD to USDC (PCS)
        // Increase allowance
        IERC20(_swapEarnedToUSDCParams.tokenBUSD).safeIncreaseAllowance(
            _swapEarnedToUSDCParams.uniRouterAddress,
            _balBUSD
        );
        // Swap
        safeSwap(
            _swapEarnedToUSDCParams.balancerVaultAddress,
            _swapEarnedToUSDCParams.balancerPool,
            _swapEarnedToUSDCParams.uniRouterAddress,
            SafeSwapParams({
                amountIn: _balBUSD,
                priceToken0: _tokenBUSDExchangeRate,
                priceToken1: _rates.stablecoin,
                token0: _swapEarnedToUSDCParams.tokenBUSD,
                token1: _swapEarnedToUSDCParams.tokenUSDCAddress,
                token0Weight: 0,
                token1Weight: 0,
                maxMarketMovementAllowed: _maxMarketMovementAllowed,
                path: _path,
                destination: _destination
            }),
            _decimals1,
            false
        );
    }
}
