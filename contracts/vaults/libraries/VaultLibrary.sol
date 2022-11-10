// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../../libraries/SafeSwap.sol";

import "../../libraries/PriceFeed.sol";

import "../../interfaces/IAlpacaFairLaunch.sol";

import "../../interfaces/IAlpacaVault.sol";

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

library VaultLibraryAlpaca {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeSwapUni for IAMMRouter02;
    using SafeMathUpgradeable for uint256;
    using PriceFeed for AggregatorV3Interface;

    struct ExchangeUSDForWantParams {
        address token0Address;
        address stablecoin;
        address tokenZorroAddress;
        AggregatorV3Interface token0PriceFeed;
        AggregatorV3Interface stablecoinPriceFeed;
        address uniRouterAddress;
        address[] stablecoinToToken0Path;
        address poolAddress;
        address wantAddress;
    }

    /// @notice Performs necessary operations to convert USD into Want token
    /// @param _amountUSD The USD quantity to exchange (must already be deposited)
    /// @param _params A ExchangeUSDForWantParams struct
    /// @param _maxMarketMovementAllowed The max slippage allowed. 1000 = 0 %, 995 = 0.5%, etc.
    /// @return uint256 Amount of Want token obtained
    function exchangeUSDForWantToken(
        uint256 _amountUSD,
        ExchangeUSDForWantParams memory _params,
        uint256 _maxMarketMovementAllowed
    ) public returns (uint256) {
        // Get balance of deposited BUSD
        uint256 _balBUSD = IERC20Upgradeable(_params.stablecoin).balanceOf(
            address(this)
        );
        // Check that USD was actually deposited
        require(_amountUSD > 0, "dep<=0");
        require(_amountUSD <= _balBUSD, "amt>bal");

        // Use price feed to determine exchange rates
        uint256 _token0ExchangeRate = _params.token0PriceFeed.getExchangeRate();
        uint256 _stablecoinExchangeRate = _params
            .stablecoinPriceFeed
            .getExchangeRate();

        // Get decimal info
        uint8[] memory _decimals = new uint8[](2);
        _decimals[0] = ERC20Upgradeable(_params.stablecoin).decimals();
        _decimals[1] = ERC20Upgradeable(_params.token0Address).decimals();

        // Swap USD for token0
        // Increase allowance
        IERC20Upgradeable(_params.stablecoin).safeIncreaseAllowance(
            _params.uniRouterAddress,
            _amountUSD
        );
        // Single asset. Swap from USD directly to Token0
        if (_params.token0Address != _params.stablecoin) {
            VaultLibrary.safeSwap(
                _params.uniRouterAddress,
                SafeSwapParams({
                    amountIn: _amountUSD,
                    priceToken0: _stablecoinExchangeRate,
                    priceToken1: _token0ExchangeRate,
                    token0: _params.stablecoin,
                    token1: _params.token0Address,
                    maxMarketMovementAllowed: _maxMarketMovementAllowed,
                    path: _params.stablecoinToToken0Path,
                    destination: address(this)
                }),
                _decimals
            );
        }

        // Get new Token0 balance
        uint256 _token0Bal = IERC20Upgradeable(_params.token0Address).balanceOf(
            address(this)
        );

        // Increase allowance
        IERC20Upgradeable(_params.token0Address).safeIncreaseAllowance(
            _params.poolAddress,
            _token0Bal
        );

        // Deposit token to get Want token
        IAlpacaVault(_params.poolAddress).deposit(_token0Bal);

        // Calculate resulting want token balance
        uint256 _wantAmt = IERC20Upgradeable(_params.wantAddress).balanceOf(
            address(this)
        );

        // Transfer back to sender
        IERC20Upgradeable(_params.wantAddress).safeTransfer(
            msg.sender,
            _wantAmt
        );

        return _wantAmt;
    }

    struct ExchangeWantTokenForUSDParams {
        address token0Address;
        address stablecoin;
        address wantAddress;
        address poolAddress;
        AggregatorV3Interface token0PriceFeed;
        AggregatorV3Interface stablecoinPriceFeed;
        address[] token0ToStablecoinPath;
        address uniRouterAddress;
    }

    /// @notice Converts Want token back into USD to be ready for withdrawal and transfers to sender
    /// @param _amount The Want token quantity to exchange (must be deposited beforehand)
    /// @param _params A ExchangeWantTokenForUSDParams struct
    /// @param _maxMarketMovementAllowed The max slippage allowed for swaps. 1000 = 0 %, 995 = 0.5%, etc.
    /// @return uint256 Amount of USD token obtained
    function exchangeWantTokenForUSD(
        uint256 _amount,
        ExchangeWantTokenForUSDParams memory _params,
        uint256 _maxMarketMovementAllowed
    ) public returns (uint256) {
        // Preflight checks
        require(_amount > 0, "negWant");

        // Safely transfer Want token from sender
        IERC20Upgradeable(_params.wantAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        // Approve
        IERC20Upgradeable(_params.wantAddress).safeIncreaseAllowance(
            _params.poolAddress,
            _amount
        );

        // Withdraw Want token to get Token0
        IAlpacaVault(_params.poolAddress).withdraw(_amount);

        // Use price feed to determine exchange rates
        uint256 _token0ExchangeRate = _params.token0PriceFeed.getExchangeRate();
        uint256 _stablecoinExchangeRate = _params
            .stablecoinPriceFeed
            .getExchangeRate();

        // Get decimal info
        uint8[] memory _decimals = new uint8[](2);
        _decimals[0] = ERC20Upgradeable(_params.token0Address).decimals();
        _decimals[1] = ERC20Upgradeable(_params.stablecoin).decimals();

        // Swap Token0 for BUSD
        // Get Token0 balance
        uint256 _token0Bal = IERC20Upgradeable(_params.token0Address).balanceOf(
            address(this)
        );
        // Increase allowance
        IERC20Upgradeable(_params.token0Address).safeIncreaseAllowance(
            _params.uniRouterAddress,
            _token0Bal
        );
        // Swap Token0 -> BUSD
        if (_params.token0Address != _params.stablecoin) {
            VaultLibrary.safeSwap(
                _params.uniRouterAddress,
                SafeSwapParams({
                    amountIn: _token0Bal,
                    priceToken0: _token0ExchangeRate,
                    priceToken1: _stablecoinExchangeRate,
                    token0: _params.token0Address,
                    token1: _params.stablecoin,
                    maxMarketMovementAllowed: _maxMarketMovementAllowed,
                    path: _params.token0ToStablecoinPath,
                    destination: msg.sender
                }),
                _decimals
            );
        }

        // Calculate USD balance
        return IERC20Upgradeable(_params.stablecoin).balanceOf(msg.sender);
    }
}

library VaultLibraryStandardAMM {
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeSwapUni for IAMMRouter02;
    using PriceFeed for AggregatorV3Interface;

    /// @notice Adds liquidity to the pool of this contract
    /// @param _token0 The address of Token0
    /// @param _token1 The address of Token1
    /// @param _token0Amt Quantity of Token0 to add
    /// @param _token1Amt Quantity of Token1 to add
    /// @param _uniRouterAddress The address of the uni style router
    /// @param _maxMarketMovementAllowed The max slippage allowed for swaps. 1000 = 0 %, 995 = 0.5%, etc.
    /// @param _recipient The recipient of the LP token
    function joinPool(
        address _token0,
        address _token1,
        uint256 _token0Amt,
        uint256 _token1Amt,
        address _uniRouterAddress,
        uint256 _maxMarketMovementAllowed,
        address _recipient
    ) public {
        IAMMRouter02(_uniRouterAddress).addLiquidity(
            _token0,
            _token1,
            _token0Amt,
            _token1Amt,
            _token0Amt.mul(_maxMarketMovementAllowed).div(1000),
            _token1Amt.mul(_maxMarketMovementAllowed).div(1000),
            _recipient,
            block.timestamp.add(600)
        );
    }

    struct ExitPoolParams {
        address token0;
        address token1;
        address poolAddress;
        address uniRouterAddress;
        address wantAddress;
    }

    /// @notice Removes liquidity from a pool and sends tokens back to this address
    /// @param _amountLP The amount of LP (Want) tokens to remove
    /// @param _maxMarketMovementAllowed The max slippage allowed for swaps. 1000 = 0 %, 995 = 0.5%, etc.
    /// @param _recipient The recipient of the underlying tokens at pool exit
    function exitPool(
        uint256 _amountLP,
        uint256 _maxMarketMovementAllowed,
        address _recipient,
        ExitPoolParams memory _exitPoolParams
    ) public {
        // Init
        uint256 _amount0Min;
        uint256 _amount1Min;
        // Get total supply and calculate min amounts desired based on slippage
        uint256 _totalSupply = IERC20Upgradeable(_exitPoolParams.poolAddress)
            .totalSupply();

        {
            _amount0Min = _calcMinAmt(
                _amountLP,
                _exitPoolParams.token0,
                _exitPoolParams.poolAddress,
                _totalSupply,
                _maxMarketMovementAllowed
            );
            _amount1Min = _calcMinAmt(
                _amountLP,
                _exitPoolParams.token1,
                _exitPoolParams.poolAddress,
                _totalSupply,
                _maxMarketMovementAllowed
            );
        }

        // Approve
        IERC20Upgradeable(_exitPoolParams.wantAddress).safeIncreaseAllowance(
            _exitPoolParams.uniRouterAddress,
            _amountLP
        );

        // Remove liquidity
        IAMMRouter02(_exitPoolParams.uniRouterAddress).removeLiquidity(
            _exitPoolParams.token0,
            _exitPoolParams.token1,
            _amountLP,
            _amount0Min,
            _amount1Min,
            _recipient,
            block.timestamp.add(600)
        );
    }

    /// @notice Calculates minimum amount out for exiting LP pool
    /// @param _amountLP LP token qty
    /// @param _token Address of one of the tokens in the pair
    /// @param _poolAddress Address of LP pair
    /// @param _totalSupply Total supply of LP tokens
    /// @param _maxMarketMovementAllowed Slippage (990 = 1% etc.)
    function _calcMinAmt(
        uint256 _amountLP,
        address _token,
        address _poolAddress,
        uint256 _totalSupply,
        uint256 _maxMarketMovementAllowed
    ) internal view returns (uint256) {
        uint256 _balance = IERC20Upgradeable(_token).balanceOf(_poolAddress);
        return
            (_amountLP.mul(_balance).div(_totalSupply))
                .mul(_maxMarketMovementAllowed)
                .div(1000);
    }

    struct AddLiqAndBurnParams {
        address zorro;
        address zorroLPPoolOtherToken;
        address uniRouterAddress;
        address burnAddress;
    }

    /// @notice Adds liquidity and burns the associated LP token
    /// @param _maxMarketMovementAllowed Slippage factor (990 = 1% etc.)
    /// @param _params AddLiqAndBurnParams containing addresses
    function addLiqAndBurn(
        uint256 _maxMarketMovementAllowed,
        AddLiqAndBurnParams memory _params
    ) public {
        // Enter LP pool and send received token to the burn address
        uint256 zorroTokenAmt = IERC20Upgradeable(_params.zorro).balanceOf(
            address(this)
        );
        uint256 otherTokenAmt = IERC20Upgradeable(_params.zorroLPPoolOtherToken)
            .balanceOf(address(this));

        IERC20Upgradeable(_params.zorro).safeIncreaseAllowance(
            _params.uniRouterAddress,
            zorroTokenAmt
        );
        IERC20Upgradeable(_params.zorroLPPoolOtherToken).safeIncreaseAllowance(
            _params.uniRouterAddress,
            otherTokenAmt
        );

        IAMMRouter02(_params.uniRouterAddress).addLiquidity(
            _params.zorro,
            _params.zorroLPPoolOtherToken,
            zorroTokenAmt,
            otherTokenAmt,
            zorroTokenAmt.mul(_maxMarketMovementAllowed).div(1000),
            otherTokenAmt.mul(_maxMarketMovementAllowed).div(1000),
            _params.burnAddress,
            block.timestamp.add(600)
        );
    }

    struct SwapUSDAddLiqParams {
        address stablecoin;
        address token0Address;
        address token1Address;
        address uniRouterAddress;
        AggregatorV3Interface stablecoinPriceFeed;
        AggregatorV3Interface token0PriceFeed;
        AggregatorV3Interface token1PriceFeed;
        address[] stablecoinToToken0Path;
        address[] stablecoinToToken1Path;
        address wantAddress;
    }

    /// @notice Performs necessary operations to convert USD into Want token and transfer back to sender
    /// @param _amountUSD The amount of USD to exchange for Want token (must already be deposited on this contract)
    /// @param _params A SwapUSDAddLiqParams struct
    /// @param _maxMarketMovementAllowed Slippage (990 = 1% etc.)
    /// @return uint256 Amount of Want token obtained
    function exchangeUSDForWantToken(
        uint256 _amountUSD,
        SwapUSDAddLiqParams memory _params,
        uint256 _maxMarketMovementAllowed
    ) public returns (uint256) {
        // Get balance of deposited USD
        uint256 _balUSD = IERC20Upgradeable(_params.stablecoin)
            .balanceOf(address(this));
        // Check that USD was actually deposited
        require(_amountUSD > 0, "dep<=0");
        require(_amountUSD <= _balUSD, "amt>bal");

        // Determine exchange rates using price feed oracle
        uint256[] memory _priceTokens0 = new uint256[](2);
        _priceTokens0[0] = _params.stablecoinPriceFeed.getExchangeRate();
        _priceTokens0[1] = _params.token0PriceFeed.getExchangeRate();
        uint256[] memory _priceTokens1 = new uint256[](2);
        _priceTokens1[0] = _priceTokens0[0];
        _priceTokens1[1] = _params.token1PriceFeed.getExchangeRate();

        // Get decimal info
        uint8[] memory _decimals0 = new uint8[](2);
        _decimals0[0] = ERC20Upgradeable(_params.stablecoin).decimals();
        _decimals0[1] = ERC20Upgradeable(_params.token0Address).decimals();
        uint8[] memory _decimals1 = new uint8[](2);
        _decimals1[0] = _decimals0[0];
        _decimals1[1] = ERC20Upgradeable(_params.token1Address).decimals();

        // Increase allowance
        IERC20Upgradeable(_params.stablecoin).safeIncreaseAllowance(
            _params.uniRouterAddress,
            _amountUSD
        );

        // Swap USD for token0
        if (_params.token0Address != _params.stablecoin) {
            IAMMRouter02(_params.uniRouterAddress).safeSwap(
                _amountUSD.div(2),
                _priceTokens0,
                _maxMarketMovementAllowed,
                _params.stablecoinToToken0Path,
                _decimals0,
                address(this),
                block.timestamp.add(600)
            );
        }

        // Swap USD for token1 (if applicable)
        if (_params.token1Address != _params.stablecoin) {
            IAMMRouter02(_params.uniRouterAddress).safeSwap(
                _amountUSD.div(2),
                _priceTokens1,
                _maxMarketMovementAllowed,
                _params.stablecoinToToken1Path,
                _decimals1,
                address(this),
                block.timestamp.add(600)
            );
        }

        // Deposit token0, token1 into LP pool to get Want token (i.e. LP token)
        uint256 _token0Amt = IERC20Upgradeable(_params.token0Address).balanceOf(
            address(this)
        );
        uint256 _token1Amt = IERC20Upgradeable(_params.token1Address).balanceOf(
            address(this)
        );
        IERC20Upgradeable(_params.token0Address).safeIncreaseAllowance(
            _params.uniRouterAddress,
            _token0Amt
        );
        IERC20Upgradeable(_params.token1Address).safeIncreaseAllowance(
            _params.uniRouterAddress,
            _token1Amt
        );

        // Add liquidity
        joinPool(
            _params.token0Address,
            _params.token1Address,
            _token0Amt,
            _token1Amt,
            _params.uniRouterAddress,
            _maxMarketMovementAllowed,
            msg.sender
        );

        // Calculate resulting want token balance
        return IERC20Upgradeable(_params.wantAddress).balanceOf(msg.sender);
    }

    struct ExchWantToUSDParams {
        AggregatorV3Interface token0PriceFeed;
        AggregatorV3Interface token1PriceFeed;
        AggregatorV3Interface stablecoinPriceFeed;
        address token0Address;
        address token1Address;
        address stablecoin;
        address uniRouterAddress;
        address[] token0ToStablecoinPath;
        address[] token1ToStablecoinPath;
        address wantAddress;
        address poolAddress;
    }

    /// @notice Converts Want token back into USD to be ready for withdrawal, transfers back to sender
    /// @param _amount The Want token quantity to exchange
    /// @param _params ExchWantToUSDParams struct
    /// @param _maxMarketMovementAllowed The max slippage allowed for swaps. 1000 = 0 %, 995 = 0.5%, etc.
    /// @return uint256 Amount of USD token obtained
    function exchangeWantTokenForUSD(
        uint256 _amount,
        ExchWantToUSDParams memory _params,
        uint256 _maxMarketMovementAllowed
    ) public returns (uint256) {
        // Preflight checks
        require(_amount > 0, "negWant");

        // Safely transfer Want token from sender
        IERC20Upgradeable(_params.wantAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        // Exit LP pool
        exitPool(
            _amount,
            _maxMarketMovementAllowed,
            address(this),
            ExitPoolParams({
                token0: _params.token0Address,
                token1: _params.token1Address,
                poolAddress: _params.poolAddress,
                uniRouterAddress: _params.uniRouterAddress,
                wantAddress: _params.wantAddress
            })
        );

        // Swap tokens back to USD
        uint256 _token0Amt = IERC20Upgradeable(_params.token0Address).balanceOf(
            address(this)
        );
        uint256 _token1Amt = IERC20Upgradeable(_params.token1Address).balanceOf(
            address(this)
        );

        _swapTokensForUSD(
            _token0Amt,
            _token1Amt,
            _params,
            _maxMarketMovementAllowed
        );

        // Calculate USD balance
        return IERC20Upgradeable(_params.stablecoin).balanceOf(msg.sender);
    }

    function _swapTokensForUSD(
        uint256 _token0Amt,
        uint256 _token1Amt,
        ExchWantToUSDParams memory _params,
        uint256 _maxMarketMovementAllowed
    ) internal {
        // Increase allowance
        IERC20Upgradeable(_params.token0Address).safeIncreaseAllowance(
            _params.uniRouterAddress,
            _token0Amt
        );
        IERC20Upgradeable(_params.token1Address).safeIncreaseAllowance(
            _params.uniRouterAddress,
            _token1Amt
        );

        // Get decimal info
        uint8[] memory _decimals0 = new uint8[](2);
        _decimals0[0] = ERC20Upgradeable(_params.token0Address).decimals();
        _decimals0[1] = ERC20Upgradeable(_params.stablecoin).decimals();
        uint8[] memory _decimals1 = new uint8[](2);
        _decimals1[0] = ERC20Upgradeable(_params.token1Address).decimals();
        _decimals1[1] = _decimals0[1];

        // Exchange rates
        uint256[] memory _priceTokens0 = new uint256[](2);
        _priceTokens0[0] = _params.token0PriceFeed.getExchangeRate();
        _priceTokens0[1] = _params.stablecoinPriceFeed.getExchangeRate();
        uint256[] memory _priceTokens1 = new uint256[](2);
        _priceTokens1[0] = _params.token1PriceFeed.getExchangeRate();
        _priceTokens1[1] = _priceTokens0[1];

        // Swap token0 for USD
        if (_params.token0Address != _params.stablecoin) {
            IAMMRouter02(_params.uniRouterAddress).safeSwap(
                _token0Amt,
                _priceTokens0,
                _maxMarketMovementAllowed,
                _params.token0ToStablecoinPath,  
                _decimals0,
                msg.sender,
                block.timestamp.add(600)
            );
        }

        // Swap token1 for USD
        if (_params.token1Address != _params.stablecoin) {
            IAMMRouter02(_params.uniRouterAddress).safeSwap(
                _token1Amt,
                _priceTokens1,
                _maxMarketMovementAllowed,
                _params.token1ToStablecoinPath,
                _decimals1,
                msg.sender,
                block.timestamp.add(600)
            );
        }
    }
}
