// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../interfaces/IAMMFarm.sol";

import "../interfaces/Zorro/Vaults/IVaultLiqStakeLP.sol";

import "./actions/_VaultActionsLiqStakeLP.sol";

import "./_VaultBase.sol";

/// @title Vault base contract for liquid staking + LP strategy
contract VaultBaseLiqStakeLP is IVaultLiqStakeLP, VaultBase {
    /* Libraries */

    using SafeERC20Upgradeable for IERC20Upgradeable;
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
        _setSwapPaths(_initValue.earnedToZORROPath);
        _setSwapPaths(_initValue.earnedToToken0Path);
        _setSwapPaths(_initValue.stablecoinToToken0Path);
        _setSwapPaths(_initValue.earnedToZORLPPoolOtherTokenPath);
        _setSwapPaths(_initValue.earnedToStablecoinPath);
        _setSwapPaths(_initValue.stablecoinToToken0Path);
        _setSwapPaths(_initValue.stablecoinToZORROPath);
        _setSwapPaths(_initValue.stablecoinToLPPoolOtherTokenPath);
        _setSwapPaths(_initValue.liquidStakeToToken0Path);
        _setSwapPaths(
            VaultActions(vaultActions).reversePath(
                _initValue.stablecoinToToken0Path
            )
        );
        _setSwapPaths(
            VaultActions(vaultActions).reversePath(
                _initValue.liquidStakeToToken0Path
            )
        );

        // Price feeds
        _setPriceFeed(token0Address, _initValue.priceFeeds.token0PriceFeed);
        _setPriceFeed(earnedAddress, _initValue.priceFeeds.earnTokenPriceFeed);
        _setPriceFeed(zorroLPPoolOtherToken, _initValue.priceFeeds.lpPoolOtherTokenPriceFeed);
        _setPriceFeed(ZORROAddress, _initValue.priceFeeds.ZORPriceFeed);
        _setPriceFeed(defaultStablecoin, _initValue.priceFeeds.stablecoinPriceFeed);
        _setPriceFeed(liquidStakeToken, _initValue.priceFeeds.liquidStakeTokenPriceFeed);

        // Other
        maxMarketMovementAllowed = _initValue.maxMarketMovementAllowed;

        // Super call
        VaultBase.initialize(_timelockOwner);
    }

    /* State */

    address public liquidStakeToken; // Synth token for liquid staking (e.g. sETH)
    address public liquidStakingPool; // Liquid staking pool (can sometimes be the same as liquidStakeToken)
    AggregatorV3Interface public liquidStakeTokenPriceFeed; // Price feed for sETH

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
            sharesAdded =
                (_wantAmt * sharesTotal * entranceFeeFactor) /
                (wantLockedTotal * feeDenominator);
        }
        // Increment the shares
        sharesTotal = sharesTotal + sharesAdded;

        // Increment want token locked qty. NOTE, no farming takes place here, as the lending protocol automatically takes care of it
        wantLockedTotal = wantLockedTotal + _wantAmt;

        // Farm the want token if applicable. Otherwise increment want locked
        if (isFarmable) {
            _farm();
        } else {
            wantLockedTotal = wantLockedTotal + _wantAmt;
        }
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
        sharesRemoved = (_wantAmt * sharesTotal) / wantLockedTotal;
        // Safety: cap the shares to the total number of shares
        if (sharesRemoved > sharesTotal) {
            sharesRemoved = sharesTotal;
        }
        // Decrement the total shares by the sharesRemoved
        sharesTotal = sharesTotal - sharesRemoved;

        // If a withdrawal fee is specified, discount the _wantAmt by the withdrawal fee
        if (withdrawFeeFactor < feeDenominator) {
            _wantAmt = (_wantAmt * withdrawFeeFactor) / feeDenominator;
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
        wantLockedTotal = wantLockedTotal - _wantAmt;

        // Finally, transfer the want amount from this contract, back to the ZorroController contract
        IERC20Upgradeable(wantAddress).safeTransfer(
            zorroControllerAddress,
            _wantAmt
        );
    }

    /// @notice Public function for farming Want token.
    function farm() public nonReentrant {
        _farm();
    }

    /// @notice Internal function for farming LP token. Responsible for staking LP token in a MasterChef/MasterApe-like contract
    function _farm() internal override {
        // Preflight checks
        require(isFarmable, "!farmable");

        // Calc balance of sETH on this contract
        uint256 _synthBal = IERC20Upgradeable(liquidStakeToken).balanceOf(
            address(this)
        );

        // Approve spending
        IERC20Upgradeable(liquidStakeToken).safeIncreaseAllowance(
            vaultActions,
            _synthBal
        );

        // Swap 1/2 sETH, to ETH and add liquidity to an LP Pool (sends LP token back to this address)
        VaultActionsLiqStakeLP(vaultActions).stakeInLPPool(
            _synthBal,
            VaultActionsLiqStakeLP.StakeLiqTokenInLPPoolParams({
                liquidStakeToken: liquidStakeToken,
                nativeToken: token0Address,
                liquidStakeTokenPriceFeed: liquidStakeTokenPriceFeed,
                nativeTokenPriceFeed: priceFeeds[token0Address],
                liquidStakeToNativePath: swapPaths[liquidStakeToken][token0Address]
            }),
            maxMarketMovementAllowed
        );

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
    function _unfarm(uint256 _lpAmt) internal override {
        // Withdraw the LP tokens from the Farm contract pool
        IAMMFarm(farmContractAddress).withdraw(pid, _lpAmt);

        // Calc balance
        uint256 _balLPToken = IERC20Upgradeable(poolAddress).balanceOf(
            address(this)
        );

        // Convert LP tokens to sETH + ETH and swap to sETH (want token)
        VaultActionsLiqStakeLP(vaultActions).unStakeFromLPPool(
            _balLPToken,
            VaultActionsLiqStakeLP.UnstakeLiqTokenFromLPPoolParams({
                liquidStakeToken: liquidStakeToken,
                nativeToken: token0Address,
                lpPoolToken: poolAddress,
                liquidStakeTokenPriceFeed: liquidStakeTokenPriceFeed,
                nativeTokenPriceFeed: priceFeeds[token0Address],
                nativeToLiquidStakePath: swapPaths[token0Address][liquidStakeToken]
            }),
            maxMarketMovementAllowed
        );
    }

    /// @notice Performs necessary operations to convert USD into Want token
    /// @param _amountUSD The USD quantity to exchange (must already be deposited)
    /// @param _maxMarketMovementAllowed The max slippage allowed. 1000 = 0 %, 995 = 0.5%, etc.
    /// @return uint256 Amount of Want token obtained
    function exchangeUSDForWantToken(
        uint256 _amountUSD,
        uint256 _maxMarketMovementAllowed
    ) public override onlyZorroController whenNotPaused returns (uint256) {
        // Increase allowance
        IERC20Upgradeable(defaultStablecoin).safeIncreaseAllowance(
            vaultActions,
            _amountUSD
        );

        // Exchange
        return
            VaultActionsLiqStakeLP(vaultActions).exchangeUSDForWantToken(
                _amountUSD,
                VaultActionsLiqStakeLP.ExchangeUSDForWantParams({
                    token0Address: token0Address,
                    stablecoin: defaultStablecoin,
                    liquidStakeToken: liquidStakeToken,
                    liquidStakePool: liquidStakingPool,
                    poolAddress: poolAddress,
                    token0PriceFeed: priceFeeds[token0Address],
                    liquidStakeTokenPriceFeed: liquidStakeTokenPriceFeed,
                    stablecoinPriceFeed: priceFeeds[defaultStablecoin],
                    stablecoinToToken0Path: swapPaths[defaultStablecoin][token0Address],
                    liquidStakeToToken0Path: swapPaths[liquidStakeToken][token0Address]
                }),
                _maxMarketMovementAllowed
            );
    }

    /// @notice Converts Want token back into USD to be ready for withdrawal and transfers to sender
    /// @param _amount The Want token quantity to exchange (must be deposited beforehand)
    /// @param _maxMarketMovementAllowed The max slippage allowed for swaps. 1000 = 0 %, 995 = 0.5%, etc.
    /// @return returnedUSD Amount of USD token obtained
    function exchangeWantTokenForUSD(
        uint256 _amount,
        uint256 _maxMarketMovementAllowed
    )
        public
        virtual
        override
        onlyZorroController
        whenNotPaused
        returns (uint256 returnedUSD)
    {
        // Allow spending
        IERC20Upgradeable(wantAddress).safeIncreaseAllowance(
            vaultActions,
            _amount
        );

        // Spending
        return
            VaultActionsLiqStakeLP(vaultActions).exchangeWantTokenForUSD(
                _amount,
                VaultActionsLiqStakeLP.ExchangeWantTokenForUSDParams({
                    token0Address: token0Address,
                    stablecoin: defaultStablecoin,
                    poolAddress: poolAddress,
                    liquidStakeToken: liquidStakeToken,
                    token0PriceFeed: priceFeeds[token0Address],
                    liquidStakeTokenPriceFeed: liquidStakeTokenPriceFeed,
                    stablecoinPriceFeed: priceFeeds[defaultStablecoin],
                    liquidStakeToToken0Path: swapPaths[liquidStakeToken][token0Address],
                    token0ToStablecoinPath: swapPaths[token0Address][defaultStablecoin]
                }),
                _maxMarketMovementAllowed
            );
    }
}

contract VaultAnkrBNBLiqStakeLP is VaultBaseLiqStakeLP {}

contract VaultBenqiAVAXLiqStakeLP is VaultBaseLiqStakeLP {}
