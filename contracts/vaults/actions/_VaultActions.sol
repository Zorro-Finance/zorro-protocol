// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../../interfaces/Uniswap/IAMMRouter02.sol";

import "../../interfaces/Zorro/Vaults/IVault.sol";

import "../../interfaces/Zorro/Vaults/Actions/IVaultActions.sol";

import "../../libraries/SafeSwap.sol";

import "../../libraries/PriceFeed.sol";

abstract contract VaultActions is IVaultActions, OwnableUpgradeable {
    /* Libraries */

    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeSwapUni for IAMMRouter02;
    using PriceFeed for AggregatorV3Interface;

    /* Constructor */

    /// @notice Constructor
    /// @param _uniRouterAddress Address of Uniswap style router
    /// @param _owner The designated owner of this contract (usually a Timelock)
    function initialize(address _uniRouterAddress, address _owner) public initializer {
        uniRouterAddress = _uniRouterAddress;
        burnAddress = 0x000000000000000000000000000000000000dEaD;
        _transferOwnership(_owner);
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
            (_token0Amt * _maxMarketMovementAllowed) / 1000,
            (_token1Amt * _maxMarketMovementAllowed) / 1000,
            _recipient,
            block.timestamp + 600
        );
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
        IERC20Upgradeable(_exitPoolParams.lpTokenAddress).safeTransferFrom(
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

        {
            _amount0Min = _calcMinAmt(
                _amountLP,
                _exitPoolParams.token0,
                _exitPoolParams.poolAddress,
                _maxMarketMovementAllowed
            );
            _amount1Min = _calcMinAmt(
                _amountLP,
                _exitPoolParams.token1,
                _exitPoolParams.poolAddress,
                _maxMarketMovementAllowed
            );
        }

        // Approve
        IERC20Upgradeable(_exitPoolParams.lpTokenAddress).safeIncreaseAllowance(
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
            block.timestamp + 600
        );
    }

    /// @notice Calculates minimum amount out for exiting LP pool
    /// @param _amountLP LP token qty
    /// @param _token Address of one of the tokens in the pair
    /// @param _poolAddress Address of LP pair
    /// @param _maxMarketMovementAllowed Slippage (990 = 1% etc.)
    function _calcMinAmt(
        uint256 _amountLP,
        address _token,
        address _poolAddress,
        uint256 _maxMarketMovementAllowed
    ) internal view returns (uint256) {
        // Get total supply and calculate min amounts desired based on slippage
        uint256 _totalSupply = IERC20Upgradeable(_poolAddress).totalSupply();

        // Get balance of token in pool
        uint256 _balance = IERC20Upgradeable(_token).balanceOf(_poolAddress);

        // Return min token amount out
        return
            (_amountLP * _balance * _maxMarketMovementAllowed) /
            (1000 * _totalSupply);
    }

    /// @notice Safely swaps tokens using the most suitable protocol based on token
    /// @dev NOTE: Caller must approve tokens for spending beforehand
    /// @param _swapParams SafeSwapParams for swap
    function safeSwap(SafeSwapUni.SafeSwapParams memory _swapParams) public {
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
    function _safeSwap(SafeSwapUni.SafeSwapParams memory _swapParams) internal {
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
            block.timestamp + 600
        );
    }

    /// @notice Distributes earnings (in the form of Want token) and reinvests remainder into Want token
    /// @dev To be run by Vault's earn() func after earnings have been unfarmed
    /// @param _amount Amount of Want token to distribute
    /// @param _maxMarketMovementAllowed Slippage (990 = 1%)
    /// @param _params A DistributeEarningsParams struct
    /// @return wantRemaining Remaining Want token after distribution (will be sent back to sender)
    /// @return xChainBuybackAmt Amount of Want token reserved for cross chain buyback, if applicable
    /// @return xChainRevShareAmt Amount of Want token reserved for cross chain revshare, if applicable
    function distributeAndReinvestEarnings(
        uint256 _amount,
        uint256 _maxMarketMovementAllowed,
        DistributeEarningsParams memory _params
    )
        public
        returns (
            uint256 wantRemaining,
            uint256 xChainBuybackAmt,
            uint256 xChainRevShareAmt
        )
    {
        // Prep
        address _want = IVault(_msgSender()).wantAddress();
        address _stablecoin = IVault(_msgSender()).defaultStablecoin();

        // Transfer funds IN
        IERC20Upgradeable(_want).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        // Distribute earnings (fees + buyback + rev share)
        uint256 _usdRemaining;
        (
            _usdRemaining,
            xChainBuybackAmt,
            xChainRevShareAmt
        ) = _distributeEarnings(_amount, _maxMarketMovementAllowed, _params);

        // Change USD (not including cross chain earnings) back to Want
        wantRemaining = _exchangeUSDForWantToken(
            _usdRemaining - xChainBuybackAmt - xChainRevShareAmt,
            _maxMarketMovementAllowed
        );

        // Send remaining Want back to sender
        IERC20Upgradeable(_want).safeTransfer(msg.sender, wantRemaining);

        // Readjust USD amounts in case of slippage
        uint256 _balUSD = IERC20Upgradeable(_stablecoin).balanceOf(
            address(this)
        );
        xChainBuybackAmt =
            (xChainBuybackAmt * _balUSD) /
            (xChainBuybackAmt + xChainRevShareAmt);
        xChainRevShareAmt = _balUSD - xChainBuybackAmt;

        // Send USD back to sender
        IERC20Upgradeable(_want).safeTransfer(msg.sender, _balUSD);

        // Emit log
        emit DistributedEarnings(
            wantRemaining,
            xChainBuybackAmt,
            xChainRevShareAmt
        );
    }

    /// @notice Takes earnings (in Want) and distributes fees, buyback, revshare etc.
    /// @dev (Internal version): Assumes transfers in and out happen before and after by calling function
    /// @param _amount Amount of want token to distribute
    /// @param _maxMarketMovementAllowed Slippage (990 = 1%)
    /// @param _params A DistributeEarningsParams struct
    /// @return usdRemaining Remaining earnings (in USD) after distribution (will be sent back to sender)
    /// @return xChainBuybackAmt Amount of USD reserved for cross chain buyback, if applicable
    /// @return xChainRevShareAmt Amount of USD reserved for cross chain revshare, if applicable
    function _distributeEarnings(
        uint256 _amount,
        uint256 _maxMarketMovementAllowed,
        DistributeEarningsParams memory _params
    )
        internal
        returns (
            uint256 usdRemaining,
            uint256 xChainBuybackAmt,
            uint256 xChainRevShareAmt
        )
    {
        // Convert want to USD
        uint256 _balUSD = _exchangeWantTokenForUSD(
            _amount,
            _maxMarketMovementAllowed
        );

        // Collect protocol fees
        uint256 _controllerFee = _collectProtocolFees(
            _amount,
            _params.stablecoin,
            _params.treasury,
            _params.controllerFeeBP
        );

        // Calculate buyback and revshare amounts
        uint256 _buybackAmt = (_balUSD * _params.buybackBP) / 10000;
        uint256 _revShareAmt = (_balUSD * _params.revShareBP) / 10000;

        // Routing: Perform buyback & revshare if on home chain. Otherwise,
        // return buyback & revshare amounts for cross chain earnings distribution.
        if (_params.isHomeChain) {
            // If on home chain, perform buyback, revshare locally
            _buybackOnChain(
                _buybackAmt,
                _maxMarketMovementAllowed,
                BuybackBurnLPParams({
                    stablecoin: _params.stablecoin,
                    ZORROAddress: _params.ZORROAddress,
                    zorroLPPoolOtherToken: _params.zorroLPPoolOtherToken,
                    stablecoinToZORROPath: _params.stablecoinToZORROPath,
                    stablecoinToZORLPPoolOtherTokenPath: _params
                        .stablecoinToZORLPPoolOtherTokenPath,
                    stablecoinPriceFeed: _params.stablecoinPriceFeed,
                    ZORPriceFeed: _params.ZORPriceFeed,
                    lpPoolOtherTokenPriceFeed: _params.lpPoolOtherTokenPriceFeed
                })
            );
            _revShareOnChain(
                _revShareAmt,
                _maxMarketMovementAllowed,
                RevShareParams({
                    stablecoin: _params.stablecoin,
                    ZORROAddress: _params.ZORROAddress,
                    zorroStakingVault: _params.zorroStakingVault,
                    stablecoinToZORROPath: _params.stablecoinToZORROPath,
                    stablecoinPriceFeed: _params.stablecoinPriceFeed,
                    ZORPriceFeed: _params.ZORPriceFeed
                })
            );
        } else {
            // Otherwise, earmark for cross chain earnings distribution
            // Return reserved xchain amounts
            xChainBuybackAmt = _buybackAmt;
            xChainRevShareAmt = _revShareAmt;
        }

        // Return remainder after distribution
        usdRemaining = _balUSD - _controllerFee - _buybackAmt - _revShareAmt;
    }

    /// @notice Distribute controller (performance) fees
    /// @param _amount The amount earned (profits) (in USD)
    /// @param _stablecoin The address of the stablecoin on this contract
    /// @param _treasury The treasury address
    /// @param _controllerFeeBP The controller fee in BP
    /// @return fee The amount of controller fees collected for the treasury (in Want token)
    function _collectProtocolFees(
        uint256 _amount,
        address _stablecoin,
        address _treasury,
        uint16 _controllerFeeBP
    ) internal virtual returns (uint256 fee) {
        if (_amount > 0) {
            // If the Earned token amount is > 0, assess a controller fee, if the controller fee is > 0
            if (_controllerFeeBP > 0) {
                // Calculate the fee from the controllerFee parameters
                fee = (_amount * _controllerFeeBP) / 10000;

                // Transfer the fee to the rewards address
                IERC20Upgradeable(_stablecoin).safeTransfer(_treasury, fee);
            }
        }
    }

    /// @notice Sends the specified earnings amount (in USD) as revenue share to ZOR stakers
    /// @param _amount The amount of USD to share as revenue with ZOR stakers
    function _revShareOnChain(
        uint256 _amount,
        uint256 _maxMarketMovementAllowed,
        RevShareParams memory _params
    ) internal virtual {
        if (_amount > 0) {
            _safeSwap(
                SafeSwapUni.SafeSwapParams({
                    amountIn: _amount,
                    priceToken0: _params.stablecoinPriceFeed.getExchangeRate(),
                    priceToken1: _params.ZORPriceFeed.getExchangeRate(),
                    token0: _params.stablecoin,
                    token1: _params.ZORROAddress,
                    maxMarketMovementAllowed: _maxMarketMovementAllowed,
                    path: _params.stablecoinToZORROPath,
                    destination: _params.zorroStakingVault
                })
            );
        }
    }

    /// @notice Buys back earn token, adds liquidity, and burns the LP token
    /// @param _amount The amount of USD token to swap and buy back
    /// @param _maxMarketMovementAllowed Acceptable slippage (990 = 1%)
    /// @param _params An BuybackBurnLPParams struct specifying buyback parameters
    function _buybackOnChain(
        uint256 _amount,
        uint256 _maxMarketMovementAllowed,
        BuybackBurnLPParams memory _params
    ) internal {
        // Skip if amount not > 0
        if (_amount == 0) {
            return;
        }

        // Prep
        uint256 _stablecoinPrice = _params
            .stablecoinPriceFeed
            .getExchangeRate();

        // Swap to ZOR Token
        if (_params.stablecoin != _params.ZORROAddress) {
            _safeSwap(
                SafeSwapUni.SafeSwapParams({
                    amountIn: _amount / 2,
                    priceToken0: _stablecoinPrice,
                    priceToken1: _params.ZORPriceFeed.getExchangeRate(),
                    token0: _params.stablecoin,
                    token1: _params.ZORROAddress,
                    maxMarketMovementAllowed: _maxMarketMovementAllowed,
                    path: _params.stablecoinToZORROPath,
                    destination: address(this)
                })
            );
        }
        // Swap to Other token
        if (_params.stablecoin != _params.zorroLPPoolOtherToken) {
            _safeSwap(
                SafeSwapUni.SafeSwapParams({
                    amountIn: _amount / 2,
                    priceToken0: _stablecoinPrice,
                    priceToken1: _params
                        .lpPoolOtherTokenPriceFeed
                        .getExchangeRate(),
                    token0: _params.stablecoin,
                    token1: _params.zorroLPPoolOtherToken,
                    maxMarketMovementAllowed: _maxMarketMovementAllowed,
                    path: _params.stablecoinToZORLPPoolOtherTokenPath,
                    destination: address(this)
                })
            );
        }

        // Calc balances
        uint256 _amtZorro = IERC20Upgradeable(_params.ZORROAddress).balanceOf(
            address(this)
        );
        uint256 _amtOtherToken = IERC20Upgradeable(
            _params.zorroLPPoolOtherToken
        ).balanceOf(address(this));

        // Add liquidity and burn
        _joinPool(
            _params.ZORROAddress,
            _params.zorroLPPoolOtherToken,
            _amtZorro,
            _amtOtherToken,
            _maxMarketMovementAllowed,
            burnAddress
        );
    }

    /// @notice Performs necessary operations to convert USD into Want token
    /// @param _amountUSD The USD quantity to exchange (must already be deposited)
    /// @param _maxMarketMovementAllowed The max slippage allowed. 1000 = 0 %, 995 = 0.5%, etc.
    /// @param _destination Where to send want token to
    /// @return wantObtained Amount of Want token obtained and transferred to sender
    function exchangeUSDForWantToken(
        uint256 _amountUSD,
        uint256 _maxMarketMovementAllowed,
        address _destination
    ) public virtual returns (uint256 wantObtained) {
        // Prep
        address _stablecoin = IVault(_msgSender()).defaultStablecoin();
        address _want = IVault(_msgSender()).wantAddress();

        // Safe transfer IN
        IERC20Upgradeable(_stablecoin).safeTransferFrom(
            msg.sender,
            address(this),
            _amountUSD
        );

        // Perform exchange
        wantObtained = _exchangeUSDForWantToken(
            _amountUSD,
            _maxMarketMovementAllowed
        );

        // Transfer back to sender
        IERC20Upgradeable(_want).safeTransfer(_destination, wantObtained);
    }

    /// @notice Converts Want token back into USD to be ready for withdrawal and transfers to sender
    /// @param _amount The Want token quantity to exchange (must be deposited beforehand)
    /// @param _maxMarketMovementAllowed The max slippage allowed for swaps. 1000 = 0 %, 995 = 0.5%, etc.
    /// @param _destination Where to send converted USD to
    /// @return usdObtained Amount of USD token obtained and transferred to sender
    function exchangeWantTokenForUSD(
        uint256 _amount,
        uint256 _maxMarketMovementAllowed,
        address _destination
    ) public virtual returns (uint256 usdObtained) {
        // Preflight checks
        require(_amount > 0, "negWant");

        // Prep
        address _want = IVault(_msgSender()).wantAddress();
        address _stablecoin = IVault(_msgSender()).defaultStablecoin();

        // Safely transfer Want/Underlying token from sender
        IERC20Upgradeable(_want).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        // Perform exchange
        usdObtained = _exchangeWantTokenForUSD(
            _amount,
            _maxMarketMovementAllowed
        );

        // Transfer back to sender
        IERC20Upgradeable(_stablecoin).safeTransfer(_destination, usdObtained);
    }

    /// @notice Calculates accumulated unrealized profits on a vault
    /// @param _vaultAddr The vault address
    /// @return accumulatedProfit Amount of unrealized profit accumulated on the vault (not accounting for past harvests)
    /// @return harvestableProfit Amount of immediately harvestable profits
    function unrealizedProfits(address _vaultAddr)
        public
        view
        virtual
        returns (uint256 accumulatedProfit, uint256 harvestableProfit)
    {
        // Accumulated profit
        uint256 _principalDebt = IVault(_vaultAddr).principalDebt();
        accumulatedProfit = this.currentWantEquity(_vaultAddr) - _principalDebt;

        // Harvestable earnings
        uint256 _profitDebt = IVault(_vaultAddr).profitDebt();
        harvestableProfit = accumulatedProfit - _profitDebt;
    }

    /* Abstract functions */

    /// @notice Measures the current (unrealized) position value (measured in Want token) of the provided vault
    /// @param _vault The vault address
    /// @return positionVal Position value, in units of Want token
    function currentWantEquity(address _vault)
        public
        view
        virtual
        returns (uint256 positionVal);

    /// @notice Converts USD to want token without token transfer
    function _exchangeUSDForWantToken(
        uint256 _amountUSD,
        uint256 _maxMarketMovementAllowed
    ) internal virtual returns (uint256 wantObtained);

    /// @notice Converts Want token to USD without token transfer
    function _exchangeWantTokenForUSD(
        uint256 _amount,
        uint256 _maxMarketMovementAllowed
    ) internal virtual returns (uint256 usdObtained);

    /* Utilities */

    /// @notice Gets the swap path in the opposite direction of a trade
    /// @param _path The swap path to be reversed
    /// @return newPath An reversed path array
    function reversePath(address[] memory _path)
        public
        pure
        returns (address[] memory newPath)
    {
        uint256 _pathLength = _path.length;
        newPath = new address[](_pathLength);
        for (uint16 i = 0; i < _pathLength; ++i) {
            newPath[i] = _path[_path.length - 1 - i];
        }
    }

    /// @notice Derives swap path given a start and end token (calls)
    /// @dev Only to be called from an IVault
    /// @param _startToken The origin token to swap from
    /// @param _endToken The desired token to swap to
    /// @return path An array of addresses describing the swap path
    function _getSwapPath(address _startToken, address _endToken)
        internal
        view
        returns (address[] memory path)
    {
        // Init
        IVault _vault = IVault(msg.sender);

        // Path length
        uint16 _swapPathLength = _vault.swapPathLength(_startToken, _endToken);
        path = new address[](_swapPathLength);

        // Populate path array
        for (uint16 i = 0; i < _swapPathLength; ++i) {
            path[i] = _vault.swapPaths(_startToken, _endToken, i);
        }
    }
}
