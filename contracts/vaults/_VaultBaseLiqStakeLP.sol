// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

import "./_VaultBase.sol";

import "../libraries/PriceFeed.sol";

import "./libraries/VaultLibrary.sol";

import "../interfaces/IAMMRouter02.sol";

import "../interfaces/IAMMFarm.sol";

/// @title Vault base contract for liquid staking + LP strategy
contract VaultBaseLiqStakeLP is VaultBase {
    /* Libraries */
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeSwapUni for IAMMRouter02;
    using PriceFeed for AggregatorV3Interface;

    /* Constructor */
    /// @notice Upgradeable constructor
    /// @param _initValue A VaultAlpacaInit struct containing all init values
    /// @param _timelockOwner The designated timelock controller address to act as owner
    function initialize(
        address _timelockOwner,
        VaultBaseLiqStakeLPInit memory _initValue
    ) public initializer {
        // Vault config
        pid = _initValue.pid;
        isHomeChain = _initValue.isHomeChain;
        isFarmable = _initValue.isFarmable;

        // Addresses
        govAddress = _initValue.keyAddresses.govAddress;
        onlyGov = true;
        zorroControllerAddress = _initValue.keyAddresses.zorroControllerAddress;
        zorroXChainController = _initValue.keyAddresses.zorroXChainController;
        ZORROAddress = _initValue.keyAddresses.ZORROAddress;
        zorroStakingVault = _initValue.keyAddresses.zorroStakingVault;
        wantAddress = _initValue.keyAddresses.wantAddress;
        token0Address = _initValue.keyAddresses.token0Address;
        earnedAddress = _initValue.keyAddresses.earnedAddress;
        farmContractAddress = _initValue.keyAddresses.farmContractAddress;
        rewardsAddress = _initValue.keyAddresses.rewardsAddress;
        poolAddress = _initValue.keyAddresses.poolAddress;
        uniRouterAddress = _initValue.keyAddresses.uniRouterAddress;
        zorroLPPool = _initValue.keyAddresses.zorroLPPool;
        zorroLPPoolOtherToken = _initValue.keyAddresses.zorroLPPoolOtherToken;
        defaultStablecoin = _initValue.keyAddresses.defaultStablecoin;
        liquidStakeToken = _initValue.liquidStakeToken;
        liquidStakingPool = _initValue.liquidStakingPool;

        // Fees
        controllerFee = _initValue.fees.controllerFee;
        buyBackRate = _initValue.fees.buyBackRate;
        revShareRate = _initValue.fees.revShareRate;
        entranceFeeFactor = _initValue.fees.entranceFeeFactor;
        withdrawFeeFactor = _initValue.fees.withdrawFeeFactor;

        // Swap paths
        earnedToZORROPath = _initValue.earnedToZORROPath;
        earnedToToken0Path = _initValue.earnedToToken0Path;
        stablecoinToToken0Path = _initValue.stablecoinToToken0Path;
        earnedToZORLPPoolOtherTokenPath = _initValue
            .earnedToZORLPPoolOtherTokenPath;
        earnedToStablecoinPath = _initValue.earnedToStablecoinPath;
        stablecoinToToken0Path = _initValue.stablecoinToToken0Path;
        stablecoinToZORROPath = _initValue.stablecoinToZORROPath;
        stablecoinToLPPoolOtherTokenPath = _initValue
            .stablecoinToLPPoolOtherTokenPath;
        // Corresponding reverse paths
        token0ToStablecoinPath = VaultLibrary.reversePath(
            stablecoinToToken0Path
        );
        liquidStakeToToken0Path = _initValue.liquidStakeToToken0Path;

        // Price feeds
        token0PriceFeed = AggregatorV3Interface(
            _initValue.priceFeeds.token0PriceFeed
        );
        earnTokenPriceFeed = AggregatorV3Interface(
            _initValue.priceFeeds.earnTokenPriceFeed
        );
        lpPoolOtherTokenPriceFeed = AggregatorV3Interface(
            _initValue.priceFeeds.lpPoolOtherTokenPriceFeed
        );
        ZORPriceFeed = AggregatorV3Interface(
            _initValue.priceFeeds.ZORPriceFeed
        );
        stablecoinPriceFeed = AggregatorV3Interface(
            _initValue.priceFeeds.stablecoinPriceFeed
        );
        liquidStakeTokenPriceFeed = AggregatorV3Interface(_initValue.priceFeeds.liquidStakeTokenPriceFeed);

        maxMarketMovementAllowed = _initValue.maxMarketMovementAllowed;

        // Super call
        VaultBase.initialize(_timelockOwner);
    }

    /* Structs */

    struct VaultBaseLiqStakeLPInit {
        uint256 pid;
        bool isHomeChain;
        bool isFarmable;
        VaultLibrary.VaultAddresses keyAddresses;
        address liquidStakeToken;
        address liquidStakingPool;
        address[] earnedToZORROPath;
        address[] earnedToToken0Path;
        address[] stablecoinToToken0Path;
        address[] earnedToZORLPPoolOtherTokenPath;
        address[] earnedToStablecoinPath;
        address[] stablecoinToZORROPath;
        address[] stablecoinToLPPoolOtherTokenPath;
        address[] liquidStakeToToken0Path;
        VaultLibrary.VaultFees fees;
        VaultBaseLiqStakeLPPriceFeeds priceFeeds;
        uint256 maxMarketMovementAllowed;
    }

    struct VaultBaseLiqStakeLPPriceFeeds {
        address token0PriceFeed;
        address earnTokenPriceFeed;
        address ZORPriceFeed;
        address lpPoolOtherTokenPriceFeed;
        address stablecoinPriceFeed;
        address liquidStakeTokenPriceFeed;
    }

    /* State */

    address[] public stablecoinToZORROPath; // Swap path from BUSD to ZOR (PCS)
    address[] public stablecoinToLPPoolOtherTokenPath; // Swap path from BUSD to ZOR LP Pool's "other token" (PCS)
    address[] public liquidStakeToToken0Path; // Swap path from sAVAX to wAVAX
    address public liquidStakeToken; // Synth token for liquid staking (e.g. sAvax)
    address public liquidStakingPool; // Liquid staking pool (can sometimes be the same as liquidStakeToken)
    AggregatorV3Interface public liquidStakeTokenPriceFeed; // Price feed for sAVAX

    /* Setters */

    function setStablecoinSwapPaths(uint8 _idx, address[] calldata _path)
        external
        onlyOwner
    {
        if (_idx == 0) {
            stablecoinToToken0Path = _path;
        } else if (_idx == 1) {
            stablecoinToZORROPath = _path;
        } else if (_idx == 2) {
            stablecoinToLPPoolOtherTokenPath = _path;
        } else {
            revert("unsupported idx swap path");
        }
    }

    /* Investment Actions */

    /// @notice Receives new deposits from user
    /// @param _wantAmt amount of underlying token to deposit/stake
    /// @return sharesAdded uint256 Number of shares added
    function depositWantToken(uint256 _wantAmt)
        public
        virtual
        override
        onlyZorroController
        nonReentrant
        whenNotPaused
        returns (uint256 sharesAdded)
    {
        // Preflight checks
        require(_wantAmt > 0, "Want token deposit must be > 0");

        // Transfer Want token from sender
        IERC20Upgradeable(wantAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _wantAmt
        );

        // Set sharesAdded to the Want token amount specified
        sharesAdded = _wantAmt;
        // If the total number of shares and want tokens locked both exceed 0, the shares added is the proportion of Want tokens locked,
        // discounted by the entrance fee
        if (wantLockedTotal > 0 && sharesTotal > 0) {
            sharesAdded = _wantAmt
                .mul(sharesTotal)
                .mul(entranceFeeFactor)
                .div(wantLockedTotal)
                .div(entranceFeeFactorMax);
        }
        // Increment the shares
        sharesTotal = sharesTotal.add(sharesAdded);

        // Increment want token locked qty. NOTE, no farming takes place here, as the lending protocol automatically takes care of it
        wantLockedTotal = wantLockedTotal.add(_wantAmt);

        // Farm the want token if applicable. Otherwise increment want locked
        if (isFarmable) {
            _farm();
        } else {
            wantLockedTotal = wantLockedTotal.add(_wantAmt);
        }
    }

    /// @notice Supplies sAVAX token to Aave
    /// @param _amount Quantity of synth token to supply to lending protocol
    function _addLiquidity(uint256 _amount) internal whenNotPaused {
        // Allow spending
        IERC20Upgradeable(liquidStakeToken).safeIncreaseAllowance(
            uniRouterAddress,
            _amount
        );

        // Swap half of sAVAX to wAVAX
        // Get decimal info
        uint8[] memory _decimals = new uint8[](2);
        _decimals[0] = ERC20Upgradeable(liquidStakeToken).decimals(); // sAVAX
        _decimals[1] = ERC20Upgradeable(token0Address).decimals(); // wAVAX

        // Swap
        _safeSwap(
            SafeSwapParams({
                amountIn: _amount.div(2),
                priceToken0: liquidStakeTokenPriceFeed.getExchangeRate(),
                priceToken1: token0PriceFeed.getExchangeRate(),
                token0: liquidStakeToken,
                token1: token0Address,
                maxMarketMovementAllowed: maxMarketMovementAllowed,
                path: liquidStakeToToken0Path,
                destination: address(this)
            }),
            _decimals
        );
        
        // Calc balances
        uint256 _liqStakeBal = IERC20Upgradeable(liquidStakeToken).balanceOf(address(this));
        uint256 _token0Bal = IERC20Upgradeable(token0Address).balanceOf(address(this));

        // Add liqudity
        IAMMRouter02(uniRouterAddress).addLiquidity(
            token0Address,
            liquidStakeToken,
            _token0Bal,
            _liqStakeBal,
            _token0Bal.mul(maxMarketMovementAllowed).div(1000),
            _liqStakeBal.mul(maxMarketMovementAllowed).div(1000),
            address(this),
            block.timestamp.add(600)
        );
    }

    /// @notice Removes liquidity from AMM pool and withdraws to sAVAX
    /// @param _amount Quantity of LP token to exchange
    function _removeLiquidity(uint256 _amount) internal whenNotPaused {
        VaultLibraryStandardAMM.exitPool(
            _amount,
            maxMarketMovementAllowed,
            address(this),
            VaultLibraryStandardAMM.ExitPoolParams({
                token0: liquidStakeToken,
                token1: token0Address,
                poolAddress: poolAddress,
                uniRouterAddress: uniRouterAddress,
                wantAddress: poolAddress
            })
        );
    }

    /// @notice Safely swaps tokens using the most suitable protocol based on token
    /// @param _swapParams SafeSwapParams for swap
    /// @param _decimals Array of decimals for amount In, amount Out
    function _safeSwap(
        SafeSwapParams memory _swapParams,
        uint8[] memory _decimals
    ) internal {
        VaultLibrary.safeSwap(uniRouterAddress, _swapParams, _decimals);
    }

    /// @notice Fully withdraw Want tokens from the Farm contract (100% withdrawals only)
    /// @param _wantAmt The amount of Want token to withdraw
    /// @return sharesRemoved The number of shares removed
    function withdrawWantToken(uint256 _wantAmt)
        public
        virtual
        override
        onlyZorroController
        nonReentrant
        whenNotPaused
        returns (uint256 sharesRemoved)
    {
        // Preflight checks
        require(_wantAmt > 0, "negWant");

        // Shares removed is proportional to the % of total Want tokens locked that _wantAmt represents
        sharesRemoved = _wantAmt.mul(sharesTotal).div(wantLockedTotal);
        // Safety: cap the shares to the total number of shares
        if (sharesRemoved > sharesTotal) {
            sharesRemoved = sharesTotal;
        }
        // Decrement the total shares by the sharesRemoved
        sharesTotal = sharesTotal.sub(sharesRemoved);

        // If a withdrawal fee is specified, discount the _wantAmt by the withdrawal fee
        if (withdrawFeeFactor < withdrawFeeFactorMax) {
            _wantAmt = _wantAmt.mul(withdrawFeeFactor).div(
                withdrawFeeFactorMax
            );
        }

        // Unfarm Want token if applicable
        if (isFarmable) {
            _unfarm(_wantAmt);
        }

        // Safety: Check balance of this contract's Want tokens held, and cap _wantAmt to that value
        uint256 _wantBal = IERC20Upgradeable(wantAddress).balanceOf(
            address(this)
        );
        if (_wantAmt > _wantBal) {
            _wantAmt = _wantBal;
        }

        // Safety: cap _wantAmt at the total quantity of Want tokens locked
        if (wantLockedTotal < _wantAmt) {
            _wantAmt = wantLockedTotal;
        }

        // Decrement the total Want locked tokens by the _wantAmt
        wantLockedTotal = wantLockedTotal.sub(_wantAmt);

        // Finally, transfer the want amount from this contract, back to the ZorroController contract
        IERC20Upgradeable(wantAddress).safeTransfer(
            zorroControllerAddress,
            _wantAmt
        );
    }

    /// @notice Buys back the earned token on-chain, swaps it to add liquidity to the ZOR pool, then burns the associated LP token
    /// @dev Requires funds to be sent to this address before calling. Can be called internally OR by controller
    /// @param _amount The amount of Earn token to buy back
    /// @param _maxMarketMovementAllowed The max slippage allowed. 1000 = 0 %, 995 = 0.5%, etc.
    /// @param _rates ExchangeRates struct with realtime rates information for swaps
    function _buybackOnChain(
        uint256 _amount,
        uint256 _maxMarketMovementAllowed,
        VaultLibrary.ExchangeRates memory _rates
    ) internal override {
        // Self contained block to limit stack depth
        {
            // Get exchange rate
            uint256 _earnedExchangeRate = earnTokenPriceFeed
                .getExchangeRate();

            // Get decimal info
            uint8[] memory _decimals0 = new uint8[](2);
            _decimals0[0] = ERC20Upgradeable(earnedAddress).decimals();
            _decimals0[1] = ERC20Upgradeable(ZORROAddress).decimals();
            uint8[] memory _decimals1 = new uint8[](2);
            _decimals1[0] = _decimals0[0];
            _decimals1[1] = ERC20Upgradeable(zorroLPPoolOtherToken).decimals();

            // 1. Swap 1/2 Earned -> ZOR
            _safeSwap(
                SafeSwapParams({
                    amountIn: _amount.div(2),
                    priceToken0: _earnedExchangeRate,
                    priceToken1: _rates.ZOR,
                    token0: earnedAddress,
                    token1: ZORROAddress,
                    maxMarketMovementAllowed: _maxMarketMovementAllowed,
                    path: earnedToZORROPath,
                    destination: address(this)
                }),
                _decimals0
            );

            // 2. Swap 1/2 Earned -> LP "other token"
            _safeSwap(
                SafeSwapParams({
                    amountIn: _amount.div(2),
                    priceToken0: _earnedExchangeRate,
                    priceToken1: _rates.lpPoolOtherToken,
                    token0: earnedAddress,
                    token1: zorroLPPoolOtherToken,
                    maxMarketMovementAllowed: _maxMarketMovementAllowed,
                    path: earnedToZORLPPoolOtherTokenPath,
                    destination: address(this)
                }),
                _decimals1
            );
        }

        // Enter LP pool and send received token to the burn address
        uint256 zorroTokenAmt = IERC20Upgradeable(ZORROAddress).balanceOf(
            address(this)
        );
        uint256 otherTokenAmt = IERC20Upgradeable(zorroLPPoolOtherToken)
            .balanceOf(address(this));
        IERC20Upgradeable(ZORROAddress).safeIncreaseAllowance(
            uniRouterAddress,
            zorroTokenAmt
        );
        IERC20Upgradeable(zorroLPPoolOtherToken).safeIncreaseAllowance(
            uniRouterAddress,
            otherTokenAmt
        );
        IAMMRouter02(uniRouterAddress).addLiquidity(
            ZORROAddress,
            zorroLPPoolOtherToken,
            zorroTokenAmt,
            otherTokenAmt,
            zorroTokenAmt.mul(_maxMarketMovementAllowed).div(1000),
            otherTokenAmt.mul(_maxMarketMovementAllowed).div(1000),
            burnAddress,
            block.timestamp.add(600)
        );
    }

    /// @notice Sends the specified earnings amount as revenue share to ZOR stakers
    /// @param _amount The amount of Earn token to share as revenue with ZOR stakers
    /// @param _maxMarketMovementAllowed Max slippage. 950 = 5%, 990 = 1%, etc.
    /// @param _rates ExchangeRates struct with realtime rates information for swaps
    function _revShareOnChain(
        uint256 _amount,
        uint256 _maxMarketMovementAllowed,
        VaultLibrary.ExchangeRates memory _rates
    ) internal override {
        // Get decimal info
        uint8[] memory _decimals0 = new uint8[](2);
        _decimals0[0] = ERC20Upgradeable(earnedAddress).decimals();
        _decimals0[1] = ERC20Upgradeable(ZORROAddress).decimals();

        // Authorize spending beforehand
        IERC20Upgradeable(earnedAddress).safeIncreaseAllowance(
            uniRouterAddress,
            _amount
        );

        // Swap Earn to ZOR
        _safeSwap(
            SafeSwapParams({
                amountIn: _amount,
                priceToken0: _rates.earn,
                priceToken1: _rates.ZOR,
                token0: earnedAddress,
                token1: ZORROAddress,
                maxMarketMovementAllowed: _maxMarketMovementAllowed,
                path: earnedToZORROPath,
                destination: zorroStakingVault
            }),
            _decimals0
        );
    }

    /// @notice Swaps Earn token to USD and sends to destination specified
    /// @param _earnedAmount Quantity of Earned tokens
    /// @param _destination Address to send swapped USD to
    /// @param _maxMarketMovementAllowed Slippage factor. 950 = 5%, 990 = 1%, etc.
    /// @param _rates ExchangeRates struct with realtime rates information for swaps
    function _swapEarnedToUSD(
        uint256 _earnedAmount,
        address _destination,
        uint256 _maxMarketMovementAllowed,
        VaultLibrary.ExchangeRates memory _rates
    ) internal override {
        VaultLibrary.swapEarnedToUSD(
            _earnedAmount,
            _destination,
            _maxMarketMovementAllowed,
            _rates,
            VaultLibrary.SwapEarnedToUSDParams({
                earnedAddress: earnedAddress,
                stablecoin: defaultStablecoin,
                earnedToStablecoinPath: earnedToStablecoinPath,
                uniRouterAddress: uniRouterAddress,
                stablecoinExchangeRate: _rates.stablecoin
            })
        );
    }

    /// @notice Public function for farming Want token.
    function farm() public nonReentrant {
        _farm();
    }

    /// @notice Internal function for farming LP token. Responsible for staking LP token in a MasterChef/MasterApe-like contract
    function _farm() internal {
        require(isFarmable, "!farmable");
        // Get the LP token stored on this contract
        uint256 _lpBal = IERC20Upgradeable(poolAddress).balanceOf(
            address(this)
        );

        // Allow the farm contract (e.g. MasterChef/MasterApe) the ability to transfer up to the Want amount
        IERC20Upgradeable(poolAddress).safeIncreaseAllowance(
            farmContractAddress,
            _lpBal
        );

        // Deposit the Want tokens in the Farm contract for the appropriate pool ID (PID)
        IAMMFarm(farmContractAddress).deposit(pid, _lpBal);
    }

    /// @notice Internal function for unfarming LP token. Responsible for unstaking LP token from MasterChef/MasterApe contracts
    /// @param _lpAmt the amount of LP tokens to withdraw. If 0, will only harvest and not withdraw
    function _unfarm(uint256 _lpAmt) internal {
        // Withdraw the LP tokens from the Farm contract pool
        IAMMFarm(farmContractAddress).withdraw(pid, _lpAmt);
    }

    /* Abstract functions - must be overriden in child contracts */

    function earn(uint256 _maxMarketMovementAllowed) public virtual override {}

    function _liquidStake(uint256 _amount) internal virtual {}

    function _liquidUnstake(uint256 _amount) internal virtual {}

    function exchangeUSDForWantToken(
        uint256 _amountUSD,
        uint256 _maxMarketMovementAllowed
    ) public virtual override returns (uint256) {}

    function exchangeWantTokenForUSD(
        uint256 _amount,
        uint256 _maxMarketMovementAllowed
    ) public virtual override returns (uint256) {}
}
