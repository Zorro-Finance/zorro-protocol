// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../../interfaces/Alpaca/IAlpacaFairLaunch.sol";

import "../../interfaces/Alpaca/IAlpacaVault.sol";

import "../../interfaces/IAMMRouter02.sol";

import "../../interfaces/Zorro/Vaults/IVault.sol";

import "../../libraries/SafeSwap.sol";

import "../../libraries/PriceFeed.sol";


// TODO: Unit tests

abstract contract VaultActions is OwnableUpgradeable {
    /* Libraries */

    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeSwapUni for IAMMRouter02;
    using PriceFeed for AggregatorV3Interface;

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

    struct ExitPoolParams {
        address token0;
        address token1;
        address poolAddress;
        address lpTokenAddress;
    }

    struct DistributeEarningsParams {
        address earnedAddress;
        address ZORROAddress;
        address rewardsAddress;
        address stablecoin;
        address zorroStakingVault;
        address zorroLPPoolOtherToken;
        address wantAddress;
        AggregatorV3Interface earnTokenPriceFeed;
        AggregatorV3Interface ZORPriceFeed;
        AggregatorV3Interface lpPoolOtherTokenPriceFeed;
        AggregatorV3Interface stablecoinPriceFeed;
        address[] earnedToZORROPath;
        address[] earnedToZORLPPoolOtherTokenPath;
        address[] earnedToStablecoinPath;
        uint16 controllerFeeBP; // BP = basis points
        uint16 buybackBP;
        uint16 revShareBP;
        bool isHomeChain;
    }

    struct BuybackBurnLPParams {
        address earnedAddress;
        address ZORROAddress;
        address zorroLPPoolOtherToken;
        address[] earnedToZORROPath;
        address[] earnedToZORLPPoolOtherTokenPath;
        AggregatorV3Interface earnTokenPriceFeed;
        AggregatorV3Interface ZORPriceFeed;
        AggregatorV3Interface lpPoolOtherTokenPriceFeed;
    }

    struct RevShareParams {
        address earnedAddress;
        address ZORROAddress;
        address zorroStakingVault;
        address[] earnedToZORROPath;
        AggregatorV3Interface earnTokenPriceFeed;
        AggregatorV3Interface ZORPriceFeed;
    }

    struct EarnToWantParams {
        address wantAddress;
        address token0;
        address token1;
        address[] earnedToToken0Path;
        address[] earnedToToken1Path;
        AggregatorV3Interface earnTokenPriceFeed;
        AggregatorV3Interface token0PriceFeed;
        AggregatorV3Interface token1PriceFeed;
    }

    /* Constructor */

    /// @notice Constructor
    /// @param _uniRouterAddress Address of Uniswap style router
    function initialize(address _uniRouterAddress) public initializer {
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

    // TODO: Docstrings
    /// @notice Distributes earnings and reinvests remainder into Want token
    function distributeAndReinvestEarnings(
        uint256 _earnedAmt,
        uint256 _maxMarketMovementAllowed,
        DistributeEarningsParams memory _params
    )
        public
        returns (
            uint256 wantObtained,
            uint256 xChainBuybackAmt,
            uint256 xChainRevShareAmt
        )
    {
        // Transfer funds IN
        IERC20Upgradeable(_params.earnedAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _earnedAmt
        );

        // Distribute earnings (fees + buyback + rev share)
        uint256 _remainingEarnAmt;
        (
            _remainingEarnAmt,
            xChainBuybackAmt,
            xChainRevShareAmt
        ) = _distributeEarnings(_earnedAmt, _maxMarketMovementAllowed, _params);

        // Convert remainder to Want token and send back to sender
        wantObtained = _convertRemainingEarnedToWant(
            _remainingEarnAmt,
            _maxMarketMovementAllowed,
            msg.sender
        );
    }

    // TODO: Docstrings
    /// @notice Takes earnings and distributes fees, buyback, revshare etc.
    /// @return remainingEarnings The remaining earnings after all fees and fund distribution
    function _distributeEarnings(
        uint256 _earnedAmt,
        uint256 _maxMarketMovementAllowed,
        DistributeEarningsParams memory _params
    )
        internal
        returns (
            uint256 remainingEarnings,
            uint256 xChainBuybackAmt,
            uint256 xChainRevShareAmt
        )
    {
        // Collect protocol fees
        uint256 _controllerFee = _collectProtocolFees(
            _params.earnedAddress,
            _params.rewardsAddress,
            _earnedAmt,
            _params.controllerFeeBP
        );

        // Calculate buyback and revshare amounts
        uint256 _buybackAmt = (_earnedAmt * _params.buybackBP) / 10000;
        uint256 _revShareAmt = (_earnedAmt * _params.revShareBP) / 10000;

        // Routing: Perform buyback & revshare if on home chain. Otherwise,
        // return buyback & revshare amounts for cross chain earnings distribution.
        if (_params.isHomeChain) {
            // If on home chain, perform buyback, revshare locally
            _buybackOnChain(
                _buybackAmt,
                _maxMarketMovementAllowed,
                BuybackBurnLPParams({
                    earnedAddress: _params.earnedAddress,
                    ZORROAddress: _params.ZORROAddress,
                    zorroLPPoolOtherToken: _params.zorroLPPoolOtherToken,
                    earnedToZORROPath: _params.earnedToZORROPath,
                    earnedToZORLPPoolOtherTokenPath: _params
                        .earnedToZORLPPoolOtherTokenPath,
                    earnTokenPriceFeed: _params.earnTokenPriceFeed,
                    ZORPriceFeed: _params.ZORPriceFeed,
                    lpPoolOtherTokenPriceFeed: _params.lpPoolOtherTokenPriceFeed
                })
            );
            _revShareOnChain(
                _revShareAmt,
                _maxMarketMovementAllowed,
                RevShareParams({
                    earnedAddress: _params.earnedAddress,
                    ZORROAddress: _params.ZORROAddress,
                    zorroStakingVault: _params.zorroStakingVault,
                    earnedToZORROPath: _params.earnedToZORROPath,
                    earnTokenPriceFeed: _params.earnTokenPriceFeed,
                    ZORPriceFeed: _params.ZORPriceFeed
                })
            );
        } else {
            // Otherwise, swap to USD and earmark for cross chain earnings distribution
            // Return reserved xchain amounts
            xChainBuybackAmt = _buybackAmt;
            xChainRevShareAmt = _revShareAmt;

            // Calc sum
            uint256 _swappableAmt = _buybackAmt + _revShareAmt;

            // Swap to Earn to USD and send to sender
            _safeSwap(
                SafeSwapUni.SafeSwapParams({
                    amountIn: _swappableAmt,
                    priceToken0: _params.earnTokenPriceFeed.getExchangeRate(),
                    priceToken1: _params.stablecoinPriceFeed.getExchangeRate(),
                    token0: _params.earnedAddress,
                    token1: _params.stablecoin,
                    maxMarketMovementAllowed: _maxMarketMovementAllowed,
                    path: _params.earnedToStablecoinPath,
                    destination: msg.sender
                })
            );
        }

        // Return remainder after distribution
        remainingEarnings =
            _earnedAmt -
            _controllerFee -
            _buybackAmt -
            _revShareAmt;
    }

    // TODO: Docstrings
    /// @notice Combines buyback and rev share operations
    /// @notice distribute controller (performance) fees
    /// @param _earnedAmt The Earned token amount (profits)
    /// @return fee The amount of controller fees collected for the treasury
    function _collectProtocolFees(
        address _earnedAddress,
        address _rewardsAddress,
        uint256 _earnedAmt,
        uint16 _controllerFeeBP
    ) internal virtual returns (uint256 fee) {
        if (_earnedAmt > 0) {
            // If the Earned token amount is > 0, assess a controller fee, if the controller fee is > 0
            if (_controllerFeeBP > 0) {
                // Calculate the fee from the controllerFee parameters
                fee = (_earnedAmt * _controllerFeeBP) / 10000;

                // Transfer the fee to the rewards address
                IERC20Upgradeable(_earnedAddress).safeTransfer(
                    _rewardsAddress,
                    fee
                );
            }
        }
    }

    // TODO: Docstrings
    /// @notice Sends the specified earnings amount as revenue share to ZOR stakers
    /// @param _amount The amount of Earn token to share as revenue with ZOR stakers
    function _revShareOnChain(
        uint256 _amount,
        uint256 _maxMarketMovementAllowed,
        RevShareParams memory _params
    ) internal virtual {
        if (_amount > 0) {
            _safeSwap(
                SafeSwapUni.SafeSwapParams({
                    amountIn: _amount,
                    priceToken0: _params.earnTokenPriceFeed.getExchangeRate(),
                    priceToken1: _params.ZORPriceFeed.getExchangeRate(),
                    token0: _params.earnedAddress,
                    token1: _params.ZORROAddress,
                    maxMarketMovementAllowed: _maxMarketMovementAllowed,
                    path: _params.earnedToZORROPath,
                    destination: _params.zorroStakingVault
                })
            );
        }
    }

    /// @notice Buys back earn token, adds liquidity, and burns the LP token
    /// @param _amount The amount of Earn token to swap and buy back
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
        uint256 _earnTokenPrice = _params.earnTokenPriceFeed.getExchangeRate();

        // Swap to ZOR Token
        if (_params.earnedAddress != _params.ZORROAddress) {
            _safeSwap(
                SafeSwapUni.SafeSwapParams({
                    amountIn: _amount / 2,
                    priceToken0: _earnTokenPrice,
                    priceToken1: _params.ZORPriceFeed.getExchangeRate(),
                    token0: _params.earnedAddress,
                    token1: _params.ZORROAddress,
                    maxMarketMovementAllowed: _maxMarketMovementAllowed,
                    path: _params.earnedToZORROPath,
                    destination: address(this)
                })
            );
        }
        // Swap to Other token
        if (_params.earnedAddress != _params.zorroLPPoolOtherToken) {
            _safeSwap(
                SafeSwapUni.SafeSwapParams({
                    amountIn: _amount / 2,
                    priceToken0: _earnTokenPrice,
                    priceToken1: _params
                        .lpPoolOtherTokenPriceFeed
                        .getExchangeRate(),
                    token0: _params.earnedAddress,
                    token1: _params.zorroLPPoolOtherToken,
                    maxMarketMovementAllowed: _maxMarketMovementAllowed,
                    path: _params.earnedToZORLPPoolOtherTokenPath,
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

    // TODO: Docstrings
    /// @notice Abstract function to convert remaining earn token to Want.
    /// @dev To be implemented by child contracts
    function _convertRemainingEarnedToWant(
        uint256 _remainingEarnAmt,
        uint256 _maxMarketMovementAllowed,
        address _destination
    ) internal virtual returns (uint256 wantObtained);

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
