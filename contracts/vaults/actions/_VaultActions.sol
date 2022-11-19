// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../../libraries/SafeSwap.sol";

import "../../libraries/PriceFeed.sol";

import "../../interfaces/Alpaca/IAlpacaFairLaunch.sol";

import "../../interfaces/Alpaca/IAlpacaVault.sol";

import "../../interfaces/IAMMRouter02.sol";

// TODO: Unit tests

contract VaultActions is OwnableUpgradeable {
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
        uint256 stablecoinExchangeRate;
    }

    /* Constructor */

    /// @notice Constructor
    /// @param _uniRouterAddress Address of Uniswap style router
    function initialize(address _uniRouterAddress)
        public
        initializer
    {
        uniRouterAddress = _uniRouterAddress;
        burnAddress = 0x000000000000000000000000000000000000dEaD;
    }

    /* State */

    address public uniRouterAddress;
    address public burnAddress;

    /* Setters */

    function setUniRouterAddress(address _uniRouterAddress) external onlyOwner {
        uniRouterAddress = _uniRouterAddress;
    }

    function setBurnAddress(address _burnAddress) external onlyOwner {
        burnAddress = _burnAddress;
    }

    /* Functions */

    // TODO: DRY: Convert all .addLiquidity() and .removeLiquidity() across the protocol
    // to use joinPool, exitPool, below.

    /// @notice Adds liquidity to the pool of this contract
    /// @dev NOTE: Requires spending approval by caller
    /// @param _token0 The address of Token0
    /// @param _token1 The address of Token1
    /// @param _token0Amt Quantity of Token0 to add
    /// @param _token1Amt Quantity of Token1 to add
    /// @param _maxMarketMovementAllowed The max slippage allowed for swaps. 1000 = 0 %, 995 = 0.5%, etc.
    /// @param _recipient The recipient of the LP token
    function joinPool(
        address _token0,
        address _token1,
        uint256 _token0Amt,
        uint256 _token1Amt,
        uint256 _maxMarketMovementAllowed,
        address _recipient
    ) public {
        // Transfer funds in
        IERC20Upgradeable(_token0).safeTransferFrom(
            msg.sender,
            address(this),
            _token0Amt
        );
        IERC20Upgradeable(_token1).safeTransferFrom(
            msg.sender,
            address(this),
            _token1Amt
        );

        // Call internal function to add liquidity
        _joinPool(
            _token0,
            _token1,
            _token0Amt,
            _token1Amt,
            _maxMarketMovementAllowed,
            _recipient
        );
    }

    /// @notice Internal function for adding liquidity to the pool of this contract
    /// @dev NOTE: Unlike public function, does not transfer tokens into contract (assumes already tokens already present)
    /// @param _token0 The address of Token0
    /// @param _token1 The address of Token1
    /// @param _token0Amt Quantity of Token0 to add
    /// @param _token1Amt Quantity of Token1 to add
    /// @param _maxMarketMovementAllowed The max slippage allowed for swaps. 1000 = 0 %, 995 = 0.5%, etc.
    /// @param _recipient The recipient of the LP token
    function _joinPool(
        address _token0,
        address _token1,
        uint256 _token0Amt,
        uint256 _token1Amt,
        uint256 _maxMarketMovementAllowed,
        address _recipient
    ) internal {
        // Transfer funds in
        IERC20Upgradeable(_token0).safeTransferFrom(
            msg.sender,
            address(this),
            _token0Amt
        );
        IERC20Upgradeable(_token1).safeTransferFrom(
            msg.sender,
            address(this),
            _token1Amt
        );

        // Approve spending
        IERC20Upgradeable(_token0).safeIncreaseAllowance(
            uniRouterAddress,
            _token0Amt
        );
        IERC20Upgradeable(_token1).safeIncreaseAllowance(
            uniRouterAddress,
            _token1Amt
        );

        // Add liquidity
        IAMMRouter02(uniRouterAddress).addLiquidity(
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
        address wantAddress;
    }

    /// @notice Removes liquidity from a pool and sends tokens back to this address
    /// @dev NOTE: Requires caller to approve want token spending
    /// @param _amountLP The amount of LP (Want) tokens to remove
    /// @param _maxMarketMovementAllowed The max slippage allowed for swaps. 1000 = 0 %, 995 = 0.5%, etc.
    /// @param _recipient The recipient of the underlying tokens at pool exit
    function exitPool(
        uint256 _amountLP,
        uint256 _maxMarketMovementAllowed,
        address _recipient,
        ExitPoolParams memory _exitPoolParams
    ) public {
        // Transfer LP token in
        IERC20Upgradeable(_exitPoolParams.wantAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _amountLP
        );

        // Call internal exitPool()
        _exitPool(
            _amountLP,
            _maxMarketMovementAllowed,
            _recipient,
            _exitPoolParams
        );
    }

    /// @notice Internal version of exitPool() (Does not transfer tokens IN)
    /// @dev NOTE: Assumes LP token is already on contract
    /// @param _amountLP The amount of LP (Want) tokens to remove
    /// @param _maxMarketMovementAllowed The max slippage allowed for swaps. 1000 = 0 %, 995 = 0.5%, etc.
    /// @param _recipient The recipient of the underlying tokens at pool exit
    function _exitPool(
        uint256 _amountLP,
        uint256 _maxMarketMovementAllowed,
        address _recipient,
        ExitPoolParams memory _exitPoolParams
    ) internal {
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
            uniRouterAddress,
            _amountLP
        );

        // Remove liquidity
        IAMMRouter02(uniRouterAddress).removeLiquidity(
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


    /// @notice Safely swaps tokens using the most suitable protocol based on token
    /// @dev NOTE: Caller must approve tokens for spending beforehand
    /// @param _swapParams SafeSwapParams for swap
    function safeSwap(SafeSwapParams memory _swapParams) public {
        // Transfer tokens in
        IERC20Upgradeable(_swapParams.token0).safeTransferFrom(
            msg.sender,
            address(this),
            _swapParams.amountIn
        );

        // Call internal swap function
        _safeSwap(_swapParams);
    }

    /// @notice Internal function for swapping
    /// @dev Does not transfer tokens to this contract (assumes they are already here)
    /// @param _swapParams SafeSwapParams for swap
    function _safeSwap(SafeSwapParams memory _swapParams) internal {
        // Allowance
        IERC20Upgradeable(_swapParams.token0).safeIncreaseAllowance(
            uniRouterAddress,
            _swapParams.amountIn
        );

        // Get decimal info
        uint8[] memory _decimals = new uint8[](2);
        _decimals[0] = ERC20Upgradeable(_swapParams.token0).decimals();
        _decimals[1] = ERC20Upgradeable(_swapParams.token1).decimals();

        // Determine exchange rates using price feed oracle
        uint256[] memory _priceTokens = new uint256[](2);
        _priceTokens[0] = _swapParams.priceToken0;
        _priceTokens[1] = _swapParams.priceToken1;

        // Swap
        IAMMRouter02(uniRouterAddress).safeSwap(
            _swapParams.amountIn,
            _priceTokens,
            _swapParams.maxMarketMovementAllowed,
            _swapParams.path,
            _decimals,
            _swapParams.destination,
            block.timestamp.add(600)
        );
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
