// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import "../interfaces/IAMMFarm.sol";

import "../interfaces/IAMMRouter02.sol";

import "./_VaultBase.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

import "../libraries/SafeSwap.sol";

import "../libraries/PriceFeed.sol";

import "./libraries/VaultLibraryStandardAMM.sol";

/// @title VaultStandardAMM: abstract base class for all PancakeSwap style AMM contracts. Maximizes yield in AMM.
contract VaultStandardAMM is VaultBase {
    /* Libraries */
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint256;
    using SafeSwapUni for IAMMRouter02;
    using PriceFeed for AggregatorV3Interface;

    /* Constructor */
    /// @notice Upgradeable constructor
    /// @param _initValue A VaultStandardAMMInit struct with all constructor params
    /// @param _timelockOwner The designated timelock controller address to act as owner
    function initialize(
        address _timelockOwner,
        VaultStandardAMMInit memory _initValue
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
        token1Address = _initValue.keyAddresses.token1Address;
        earnedAddress = _initValue.keyAddresses.earnedAddress;
        farmContractAddress = _initValue.keyAddresses.farmContractAddress;
        rewardsAddress = _initValue.keyAddresses.rewardsAddress;
        poolAddress = _initValue.keyAddresses.poolAddress;
        uniRouterAddress = _initValue.keyAddresses.uniRouterAddress;
        zorroLPPool = _initValue.keyAddresses.zorroLPPool;
        zorroLPPoolOtherToken = _initValue.keyAddresses.zorroLPPoolOtherToken;
        defaultStablecoin = _initValue.keyAddresses.defaultStablecoin;

        // Fees
        controllerFee = _initValue.fees.controllerFee;
        buyBackRate = _initValue.fees.buyBackRate;
        revShareRate = _initValue.fees.revShareRate;
        entranceFeeFactor = _initValue.fees.entranceFeeFactor;
        withdrawFeeFactor = _initValue.fees.withdrawFeeFactor;

        // Swap paths
        earnedToZORROPath = _initValue.earnedToZORROPath;
        earnedToToken0Path = _initValue.earnedToToken0Path;
        earnedToToken1Path = _initValue.earnedToToken1Path;
        stablecoinToToken0Path = _initValue.stablecoinToToken0Path;
        stablecoinToToken1Path = _initValue.stablecoinToToken1Path;
        earnedToZORLPPoolOtherTokenPath = _initValue
            .earnedToZORLPPoolOtherTokenPath;
        earnedToStablecoinPath = _initValue.earnedToStablecoinPath;
        // Corresponding reverse paths
        token0ToStablecoinPath = VaultLibrary.reversePath(stablecoinToToken0Path);
        token1ToStablecoinPath = VaultLibrary.reversePath(stablecoinToToken1Path);

        // Price feeds
        token0PriceFeed = AggregatorV3Interface(
            _initValue.priceFeeds.token0PriceFeed
        );
        token1PriceFeed = AggregatorV3Interface(
            _initValue.priceFeeds.token1PriceFeed
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

        // Super call
        VaultBase.initialize(_timelockOwner);
    }

    /* Structs */

    struct VaultStandardAMMInit {
        uint256 pid;
        bool isHomeChain;
        bool isFarmable;
        VaultLibrary.VaultAddresses keyAddresses;
        address[] earnedToZORROPath;
        address[] earnedToToken0Path;
        address[] earnedToToken1Path;
        address[] stablecoinToToken0Path;
        address[] stablecoinToToken1Path;
        address[] earnedToZORLPPoolOtherTokenPath;
        address[] earnedToStablecoinPath;
        VaultLibrary.VaultFees fees;
        VaultLibrary.VaultPriceFeeds priceFeeds;
    }

    /* Investment Actions */

    /// @notice Receives new deposits from user
    /// @param _wantAmt The amount of Want token to deposit (must already be transferred)
    /// @return sharesAdded Number of shares added
    function depositWantToken(uint256 _wantAmt)
        public
        override
        onlyZorroController
        nonReentrant
        whenNotPaused
        returns (uint256 sharesAdded)
    {
        // Preflight checks
        require(_wantAmt > 0, "want<0");

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

        // Farm the want token if applicable. Otherwise increment want locked
        if (isFarmable) {
            _farm();
        } else {
            wantLockedTotal = wantLockedTotal.add(_wantAmt);
        }
    }

    /// @notice Performs necessary operations to convert USD into Want token and transfer back to sender
    /// @param _amountUSD The amount of USD to exchange for Want token (must already be deposited on this contract)
    /// @param _maxMarketMovementAllowed The max slippage allowed. 1000 = 0 %, 995 = 0.5%, etc.
    /// @return uint256 Amount of Want token obtained
    function exchangeUSDForWantToken(
        uint256 _amountUSD,
        uint256 _maxMarketMovementAllowed
    ) public override onlyZorroController whenNotPaused returns (uint256) {
        return VaultLibraryStandardAMM.exchangeUSDForWantToken(
            _amountUSD, 
            VaultLibraryStandardAMM.SwapUSDAddLiqParams({
                stablecoin: defaultStablecoin,
                token0Address: token0Address,
                token1Address: token1Address,
                uniRouterAddress: uniRouterAddress,
                stablecoinPriceFeed: stablecoinPriceFeed,
                token0PriceFeed: token0PriceFeed,
                token1PriceFeed: token1PriceFeed,
                stablecoinToToken0Path: stablecoinToToken0Path,
                stablecoinToToken1Path: stablecoinToToken1Path,
                wantAddress: wantAddress
            }),
            _maxMarketMovementAllowed
        );
    }

    /// @notice Public function for farming Want token.
    function farm() public nonReentrant {
        _farm();
    }

    /// @notice Internal function for farming Want token. Responsible for staking Want token in a MasterChef/MasterApe-like contract
    function _farm() internal {
        require(isFarmable, "!farmable");
        // Get the Want token stored on this contract
        uint256 wantBal = IERC20Upgradeable(wantAddress).balanceOf(
            address(this)
        );
        // Increment the total Want tokens locked into this contract
        wantLockedTotal = wantLockedTotal.add(wantBal);
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
    function _unfarm(uint256 _wantAmt) internal {
        // Withdraw the Want tokens from the Farm contract pool
        IAMMFarm(farmContractAddress).withdraw(pid, _wantAmt);
    }

    /// @notice Fully withdraw Want tokens from the Farm contract (100% withdrawals only)
    /// @param _wantAmt The amount of Want token to withdraw
    /// @return sharesRemoved The number of shares removed
    function withdrawWantToken(uint256 _wantAmt)
        public
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
        return VaultLibraryStandardAMM.exchangeWantTokenForUSD(
            _amount,
            VaultLibraryStandardAMM.ExchWantToUSDParams({
                token0PriceFeed: token0PriceFeed,
                token1PriceFeed: token1PriceFeed,
                stablecoinPriceFeed: stablecoinPriceFeed,
                token0Address: token0Address,
                token1Address: token1Address,
                stablecoin: defaultStablecoin,
                uniRouterAddress: uniRouterAddress,
                token0ToStablecoinPath: token0ToStablecoinPath,
                token1ToStablecoinPath: token1ToStablecoinPath,
                wantAddress: wantAddress,
                poolAddress: poolAddress
            }), 
            _maxMarketMovementAllowed
        );
    }

    /// @notice Adds liquidity to the pool of this contract
    /// @param _token0Amt Quantity of Token0 to add
    /// @param _token1Amt Quantity of Token1 to add
    /// @param _maxMarketMovementAllowed The max slippage allowed for swaps. 1000 = 0 %, 995 = 0.5%, etc.
    /// @param _recipient The recipient of the LP token
    function _joinPool(
        uint256 _token0Amt,
        uint256 _token1Amt,
        uint256 _maxMarketMovementAllowed,
        address _recipient
    ) internal {
        VaultLibraryStandardAMM.joinPool(
            token0Address,
            token1Address,
            _token0Amt,
            _token1Amt,
            uniRouterAddress,
            _maxMarketMovementAllowed,
            _recipient
        );
    }

    /// @notice Removes liquidity from a pool and sends tokens back to this address
    /// @param _amountLP The amount of LP (Want) tokens to remove
    /// @param _maxMarketMovementAllowed The max slippage allowed for swaps. 1000 = 0 %, 995 = 0.5%, etc.
    /// @param _recipient The recipient of the underlying tokens at pool exit
    function _exitPool(
        uint256 _amountLP,
        uint256 _maxMarketMovementAllowed,
        address _recipient
    ) internal {
        VaultLibraryStandardAMM.exitPool(
            _amountLP,
            _maxMarketMovementAllowed,
            _recipient,
            VaultLibraryStandardAMM.ExitPoolParams({
                token0: token0Address,
                token1: token1Address,
                poolAddress: poolAddress,
                uniRouterAddress: uniRouterAddress,
                wantAddress: wantAddress
            })
        );
    }

    /// @notice The main compounding (earn) function. Reinvests profits since the last earn event.
    /// @param _maxMarketMovementAllowed The max slippage allowed. 1000 = 0 %, 995 = 0.5%, etc.
    function earn(uint256 _maxMarketMovementAllowed)
        public
        override
        nonReentrant
        whenNotPaused
    {
        require(isFarmable, "!farmable");

        // If onlyGov is set to true, only allow to proceed if the current caller is the govAddress
        if (onlyGov) {
            require(msg.sender == govAddress, "!gov");
        }

        // Harvest farm tokens
        _unfarm(0);

        // Get the balance of the Earned token on this contract (CAKE, BANANA, etc.)
        uint256 _earnedAmt = IERC20Upgradeable(earnedAddress).balanceOf(
            address(this)
        );

        // Require pending rewards in order to continue
        require(_earnedAmt > 0, "0earn");

        // Create rates struct
        VaultLibrary.ExchangeRates memory _rates;
        uint256[] memory _priceTokens0 = new uint256[](2);
        uint256[] memory _priceTokens1 = new uint256[](2);
        {
            _rates = VaultLibrary.ExchangeRates({
                earn: earnTokenPriceFeed.getExchangeRate(),
                ZOR: ZORPriceFeed.getExchangeRate(),
                lpPoolOtherToken: lpPoolOtherTokenPriceFeed.getExchangeRate(),
                stablecoin: stablecoinPriceFeed.getExchangeRate()
            });
            _priceTokens0[0] = _rates.earn;
            _priceTokens0[1] = token0PriceFeed.getExchangeRate();
            _priceTokens1[0] = _rates.earn;
            _priceTokens1[1] = token1PriceFeed.getExchangeRate();
        }

        // Calc remainder
        uint256 _remainingAmt;

        {
            // Distribute fees
            uint256 _controllerFee = _distributeFees(_earnedAmt);

            // Buyback & rev share
            (uint256 _buybackAmt, uint256 _revShareAmt) = _buyBackAndRevShare(
                _earnedAmt,
                _maxMarketMovementAllowed,
                _rates
            );

            _remainingAmt = _earnedAmt.sub(_controllerFee).sub(_buybackAmt).sub(
                    _revShareAmt
                );
        }

        // Allow the router contract to spen up to earnedAmt
        IERC20Upgradeable(earnedAddress).safeIncreaseAllowance(
            uniRouterAddress,
            _earnedAmt
        );

        // Swap Earned token to token0 if token0 is not the Earned token
        if (earnedAddress != token0Address) {
            // Get decimal info
            uint8[] memory _decimals0 = new uint8[](2);
            _decimals0[0] = ERC20Upgradeable(earnedAddress).decimals();
            _decimals0[1] = ERC20Upgradeable(token0Address).decimals();

            // Swap half earned to token0
            IAMMRouter02(uniRouterAddress).safeSwap(
                _remainingAmt.div(2),
                _priceTokens0,
                _maxMarketMovementAllowed,
                earnedToToken0Path,
                _decimals0,
                address(this),
                block.timestamp.add(600)
            );
        }

        // Swap Earned token to token1 if token0 is not the Earned token
        if (earnedAddress != token1Address) {
            // Get decimal info
            uint8[] memory _decimals1 = new uint8[](2);
            _decimals1[0] = ERC20Upgradeable(earnedAddress).decimals();
            _decimals1[1] = ERC20Upgradeable(token1Address).decimals();

            // Swap half earned to token1
            IAMMRouter02(uniRouterAddress).safeSwap(
                _remainingAmt.div(2),
                _priceTokens1,
                _maxMarketMovementAllowed,
                earnedToToken1Path,
                _decimals1,
                address(this),
                block.timestamp.add(600)
            );
        }

        // Get values of tokens 0 and 1
        uint256 token0Amt = IERC20Upgradeable(token0Address).balanceOf(
            address(this)
        );
        uint256 token1Amt = IERC20Upgradeable(token1Address).balanceOf(
            address(this)
        );

        // Provided that token0 and token1 are both > 0, add liquidity
        if (token0Amt > 0 && token1Amt > 0) {
            // Increase the allowance of the router to spend token0
            IERC20Upgradeable(token0Address).safeIncreaseAllowance(
                uniRouterAddress,
                token0Amt
            );
            // Increase the allowance of the router to spend token1
            IERC20Upgradeable(token1Address).safeIncreaseAllowance(
                uniRouterAddress,
                token1Amt
            );
            // Add liquidity
            _joinPool(
                token0Amt,
                token1Amt,
                _maxMarketMovementAllowed,
                address(this)
            );
        }

        // Update last earned block
        lastEarnBlock = block.number;

        // Farm Want token
        _farm();
    }

    /// @notice Buys back the earned token on-chain, swaps it to add liquidity to the ZOR pool, then burns the associated LP token
    /// @dev Requires funds to be sent to this address before calling. Can be called internally OR by controller
    /// @param _amount The amount of Earn token to buy back
    /// @param _maxMarketMovementAllowed Slippage factor. 950 = 5%, 990 = 1%, etc.
    function _buybackOnChain(
        uint256 _amount,
        uint256 _maxMarketMovementAllowed,
        VaultLibrary.ExchangeRates memory _rates
    ) internal override {
        // Get decimal, exch rate info
        uint8[] memory _decimals0 = new uint8[](2);
        uint8[] memory _decimals1 = new uint8[](2);
        uint256[] memory _priceTokens0 = new uint256[](2);
        uint256[] memory _priceTokens1 = new uint256[](2);
        {
            _decimals0[0] = ERC20Upgradeable(earnedAddress).decimals();
            _decimals0[1] = ERC20Upgradeable(ZORROAddress).decimals();
            _decimals1[0] = _decimals0[0];
            _decimals1[1] = ERC20Upgradeable(zorroLPPoolOtherToken).decimals();

            _priceTokens0[0] = _rates.earn;
            _priceTokens0[1] = _rates.ZOR;
            _priceTokens1[0] = _rates.earn;
            _priceTokens1[1] = _rates.lpPoolOtherToken;
        }

        // Authorize spending beforehand
        IERC20Upgradeable(earnedAddress).safeIncreaseAllowance(
            uniRouterAddress,
            _amount
        );

        // Swap to ZOR Token
        if (earnedAddress != ZORROAddress) {
            IAMMRouter02(uniRouterAddress).safeSwap(
                _amount.div(2),
                _priceTokens0,
                _maxMarketMovementAllowed,
                earnedToZORROPath,
                _decimals0,
                address(this),
                block.timestamp.add(600)
            );
        }
        // Swap to Other token
        if (earnedAddress != zorroLPPoolOtherToken) {
            IAMMRouter02(uniRouterAddress).safeSwap(
                _amount.div(2),
                _priceTokens1,
                _maxMarketMovementAllowed,
                earnedToZORLPPoolOtherTokenPath,
                _decimals1,
                address(this),
                block.timestamp.add(600)
            );
        }

        // Add liquidity and burn
        VaultLibraryStandardAMM.addLiqAndBurn(
            _maxMarketMovementAllowed,
            VaultLibraryStandardAMM.AddLiqAndBurnParams({
                zorro: ZORROAddress,
                zorroLPPoolOtherToken: zorroLPPoolOtherToken,
                uniRouterAddress: uniRouterAddress,
                burnAddress: burnAddress
            })
        );
    }

    /// @notice Sends the specified earnings amount as revenue share to ZOR stakers
    /// @param _amount The amount of Earn token to share as revenue with ZOR stakers
    function _revShareOnChain(
        uint256 _amount,
        uint256 _maxMarketMovementAllowed,
        VaultLibrary.ExchangeRates memory _rates
    ) internal override {
        // Get decimal info
        uint8[] memory _decimals = new uint8[](2);
        _decimals[0] = ERC20Upgradeable(earnedAddress).decimals();
        _decimals[1] = ERC20Upgradeable(ZORROAddress).decimals();

        // Exchange rates
        uint256[] memory _priceTokens = new uint256[](2);
        _priceTokens[0] = _rates.earn;
        _priceTokens[1] = _rates.ZOR;

        // Authorize spending beforehand
        IERC20Upgradeable(earnedAddress).safeIncreaseAllowance(
            uniRouterAddress,
            _amount
        );

        // Swap to ZOR
        if (earnedAddress != ZORROAddress) {
            IAMMRouter02(uniRouterAddress).safeSwap(
                _amount,
                _priceTokens,
                _maxMarketMovementAllowed,
                earnedToZORROPath,
                _decimals,
                zorroStakingVault,
                block.timestamp.add(600)
            );
        }
    }

    /// @notice Swaps Earn token to USD and sends to destination specified
    /// @param _earnedAmount Quantity of Earned tokens
    /// @param _destination Address to send swapped USD to
    /// @param _maxMarketMovementAllowed Slippage factor. 950 = 5%, 990 = 1%, etc.
    function _swapEarnedToUSD(
        uint256 _earnedAmount,
        address _destination,
        uint256 _maxMarketMovementAllowed,
        VaultLibrary.ExchangeRates memory _rates
    ) internal override {
        // Get decimal info
        uint8[] memory _decimals = new uint8[](2);
        _decimals[0] = ERC20Upgradeable(earnedAddress).decimals();
        _decimals[1] = ERC20Upgradeable(defaultStablecoin).decimals();

        // Get exchange rates
        uint256[] memory _priceTokens = new uint256[](2);
        _priceTokens[0] = _rates.earn;
        _priceTokens[1] = _rates.stablecoin;

        // Increase allowance
        IERC20Upgradeable(earnedAddress).safeIncreaseAllowance(
            uniRouterAddress,
            _earnedAmount
        );

        // Perform swap with Uni router
        IAMMRouter02(uniRouterAddress).safeSwap(
            _earnedAmount,
            _priceTokens,
            _maxMarketMovementAllowed,
            earnedToStablecoinPath,
            _decimals,
            _destination,
            block.timestamp.add(600)
        );
    }
}

contract TraderJoe_ZOR_WAVAX is VaultStandardAMM {}
contract TraderJoe_WAVAX_USDC is VaultStandardAMM {}
