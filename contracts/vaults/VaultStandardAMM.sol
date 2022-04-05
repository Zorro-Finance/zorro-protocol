// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "@openzeppelin/contracts/utils/Address.sol";

import "../interfaces/IAMMFarm.sol";

import "../interfaces/IAMMRouter02.sol";

import "./_VaultBase.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "../libraries/SafeSwap.sol";

import "../libraries/PriceFeed.sol";


/// @title VaultStandardAMM: abstract base class for all PancakeSwap style AMM contracts. Maximizes yield in AMM.
contract VaultStandardAMM is VaultBase {
    /* Libraries */
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using SafeSwapUni for IAMMRouter02;
    using PriceFeed for AggregatorV3Interface;

    /* Constructor */
    /// @notice Constructor
    /// @param _addresses Array of [govAddress, zorroControllerAddress, ZORROAddress, wantAddress, token0Address, token1Address, earnedAddress, farmContractAddress, rewardsAddress, poolAddress, uniRouterAddress, zorroLPPool, zorroLPPoolOtherToken]
    /// @param _pid Pool ID this Vault is associated with
    /// @param _isCOREStaking If true, is for staking just core token of AMM (e.g. CAKE for Pancakeswap, BANANA for Apeswap, etc.). Set to false for Zorro single staking vault
    /// @param _isSingleAssetDeposit Same asset token (not LP pair). Set to True for pools with single assets (ZOR, CAKE, BANANA, ADA, etc.)
    /// @param _isZorroComp This vault is for compounding. If true, will trigger farming/unfarming on earn events. Set to false for Zorro single staking vault
    /// @param _isHomeChain Whether this contract is deployed on the home chain
    /// @param _swapPaths A flattened array of swap paths for a Uniswap style router. Ordered as: [earnedToZORROPath, earnedToToken0Path, earnedToToken1Path, USDCToToken0Path, USDCToToken1Path, earnedToZORLPPoolOtherTokenPath, earnedToUSDCPath, USDCToZORROPath]
    /// @param _swapPathStartIndexes An array of start indexes within _swapPaths to represent the start of a new swap path
    /// @param _fees Array of [_controllerFee, _buyBackRate, _entranceFeeFactor, _withdrawFeeFactor]
    constructor(
        address[] memory _addresses,
        uint256 _pid,
        bool _isCOREStaking,
        bool _isSingleAssetDeposit,
        bool _isZorroComp,
        bool _isHomeChain,
        address[] memory _swapPaths,
        uint16[] memory _swapPathStartIndexes,
        uint256[] memory _fees
    ) {
        // Key addresses
        govAddress = _addresses[0];
        zorroControllerAddress = _addresses[1];
        ZORROAddress = _addresses[2];
        wantAddress = _addresses[3];
        token0Address = _addresses[4];
        token1Address = _addresses[5];
        earnedAddress = _addresses[6];
        farmContractAddress = _addresses[7];
        rewardsAddress = _addresses[8];
        poolAddress = _addresses[9];
        uniRouterAddress = _addresses[10];
        zorroLPPool = _addresses[11];
        zorroLPPoolOtherToken = _addresses[12];

        // Vault characteristics
        pid = _pid;
        isCOREStaking = _isCOREStaking;
        isSingleAssetDeposit = _isSingleAssetDeposit;
        isZorroComp = _isZorroComp;
        isHomeChain = _isHomeChain;

        // Swap paths by unflattening _swapPaths
        _unpackSwapPaths(_swapPaths, _swapPathStartIndexes);

        // Corresponding reverse paths
        token0ToEarnedPath = _reversePath(earnedToToken0Path);
        token1ToEarnedPath = _reversePath(earnedToToken1Path);
        token0ToUSDCPath = _reversePath(USDCToToken0Path);
        token1ToUSDCPath = _reversePath(USDCToToken1Path);

        // Fees
        controllerFee = _fees[0];
        buyBackRate = _fees[1];
        entranceFeeFactor = _fees[2];
        withdrawFeeFactor = _fees[3];
    }

    /* Investment Actions */

    /// @notice Receives new deposits from user
    /// @param _account The address of the end user account making the deposit
    /// @param _wantAmt The amount of Want token to deposit (must already be transferred)
    /// @return Number of shares added
    function depositWantToken(
        address _account,
        uint256 _wantAmt
    )
        public
        override
        onlyZorroController
        nonReentrant
        whenNotPaused
        returns (uint256)
    {
        // Preflight checks
        require(_wantAmt > 0, "Want token deposit must be > 0");

        // Transfer Want token from sender
        IERC20(wantAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _wantAmt
        );

        // Set sharesAdded to the Want token amount specified
        uint256 sharesAdded = _wantAmt;
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
        userShares[_account] = userShares[_account].add(sharesAdded);

        if (isZorroComp) {
            // If this contract is meant for Autocompounding, start to farm the staked token
            _farm();
        } else {
            // Otherwise, simply increment the quantity of total Want tokens locked
            wantLockedTotal = wantLockedTotal.add(_wantAmt);
        }

        return sharesAdded;
    }

    /// @notice Performs necessary operations to convert USDC into Want token and transfer back to sender
    /// @param _amountUSDC The amount of USDC to exchange for Want token (must already be deposited on this contract)
    /// @param _maxMarketMovementAllowed The max slippage allowed. 1000 = 0 %, 995 = 0.5%, etc.
    /// @return uint256 Amount of Want token obtained
    function exchangeUSDForWantToken(
        uint256 _amountUSDC,
        uint256 _maxMarketMovementAllowed
    ) public override onlyZorroController whenNotPaused returns (uint256) {
        // Get balance of deposited USDC
        uint256 _balUSDC = IERC20(tokenUSDCAddress).balanceOf(msg.sender);
        // Check that USDC was actually deposited
        require(_amountUSDC > 0, "USDC deposit must be > 0");
        require(_amountUSDC <= _balUSDC, "USDC desired exceeded bal");

        // Use price feed to determine exchange rates
        uint256 _token0ExchangeRate = token0PriceFeed.getExchangeRate();
        uint256 _token1ExchangeRate = token1PriceFeed.getExchangeRate();

        // For single token pools, simply swap to Want token right away
        if (isSingleAssetDeposit) {
            // Swap USDC for Want token
            IAMMRouter02(uniRouterAddress).safeSwap(
                _amountUSDC,
                1e12,
                _token0ExchangeRate,
                _maxMarketMovementAllowed,
                USDCToWantPath,
                msg.sender,
                block.timestamp.add(600)
            );
        } else {
            // For multi token pools (i.e. LP pools)

            // Swap USDC for token0
            IAMMRouter02(uniRouterAddress).safeSwap(
                _amountUSDC.div(2),
                1e12,
                _token0ExchangeRate,
                _maxMarketMovementAllowed,
                USDCToToken0Path,
                address(this),
                block.timestamp.add(600)
            );

            // Swap USDC for token1 (if applicable)
            IAMMRouter02(uniRouterAddress).safeSwap(
                _amountUSDC.div(2),
                1e12,
                _token1ExchangeRate,
                _maxMarketMovementAllowed,
                USDCToToken1Path,
                address(this),
                block.timestamp.add(600)
            );

            // Deposit token0, token1 into LP pool to get Want token (i.e. LP token)
            uint256 token0Amt = IERC20(token0Address).balanceOf(address(this));
            uint256 token1Amt = IERC20(token1Address).balanceOf(address(this));
            IERC20(token0Address).safeIncreaseAllowance(
                uniRouterAddress,
                token0Amt
            );
            IERC20(token1Address).safeIncreaseAllowance(
                uniRouterAddress,
                token1Amt
            );
            _joinPool(
                token0Amt,
                token1Amt,
                _maxMarketMovementAllowed,
                msg.sender
            );
        }

        // Calculate resulting want token balance
        return IERC20(wantAddress).balanceOf(msg.sender);
    }

    /// @notice Public function for farming Want token.
    function farm() public nonReentrant {
        _farm();
    }

    /// @notice Internal function for farming Want token. Responsible for staking Want token in a MasterChef/MasterApe-like contract
    function _farm() internal {
        // Farming should only occur if this contract is set for autocompounding
        require(isZorroComp, "!isZorroComp");

        // Get the Want token stored on this contract
        uint256 wantAmt = IERC20(wantAddress).balanceOf(address(this));
        // Increment the total Want tokens locked into this contract
        wantLockedTotal = wantLockedTotal.add(wantAmt);
        // Allow the farm contract (e.g. MasterChef/MasterApe) the ability to transfer up to the Want amount
        IERC20(wantAddress).safeIncreaseAllowance(farmContractAddress, wantAmt);

        if (isCOREStaking) {
            // If this contract is meant for staking a core asset of the underlying protocol (e.g. CAKE on Pancakeswap, BANANA on Apeswap),
            // Stake that token in a single-token-staking vault on the Farm contract
            IAMMFarm(farmContractAddress).enterStaking(wantAmt);
        } else {
            // Otherwise deposit the Want tokens in the Farm contract for the appropriate pool ID (PID)
            IAMMFarm(farmContractAddress).deposit(pid, wantAmt);
        }
    }

    /// @notice Internal function for unfarming Want token. Responsible for unstaking Want token from MasterChef/MasterApe contracts
    /// @param _wantAmt the amount of Want tokens to withdraw. If 0, will only harvest and not withdraw
    function _unfarm(uint256 _wantAmt) internal {
        if (isCOREStaking) {
            // If this is contract is meant for staking a core assets of the underlying protocol,
            // simply un-stake the asset from the single-token-staking vault on the Farm contract
            IAMMFarm(farmContractAddress).leaveStaking(_wantAmt); // Just for CAKE staking, we dont use withdraw()
        } else {
            // Otherwise simply withdraw the Want tokens from the Farm contract pool
            IAMMFarm(farmContractAddress).withdraw(pid, _wantAmt);
        }
    }

    /// @notice Fully withdraw Want tokens from the Farm contract (100% withdrawals only)
    /// @param _account Address of user
    /// @param _wantAmt The amount of Want token to withdraw
    /// @return uint256 The number of shares removed
    function withdrawWantToken(
        address _account,
        uint256 _wantAmt
    )
        public
        override
        onlyZorroController
        nonReentrant
        whenNotPaused
        returns (uint256)
    {
        // Preflight checks
        require(_wantAmt > 0, "want amt <= 0");

        // Shares removed is proportional to the % of total Want tokens locked that _wantAmt represents
        uint256 sharesRemoved = _wantAmt.mul(sharesTotal).div(wantLockedTotal);
        // Safety: cap the shares to the total number of shares
        if (sharesRemoved > sharesTotal) {
            sharesRemoved = sharesTotal;
        }
        // Decrement the total shares by the sharesRemoved
        sharesTotal = sharesTotal.sub(sharesRemoved);
        userShares[_account] = userShares[_account].sub(sharesRemoved);

        // If a withdrawal fee is specified, discount the _wantAmt by the withdrawal fee
        if (withdrawFeeFactor < withdrawFeeFactorMax) {
            _wantAmt = _wantAmt.mul(withdrawFeeFactor).div(
                withdrawFeeFactorMax
            );
        }

        // If this contract is designated for auto compounding, unfarm the Want tokens
        if (isZorroComp) {
            _unfarm(_wantAmt);
        }

        // Safety: Check balance of this contract's Want tokens held, and cap _wantAmt to that value
        uint256 _wantBal = IERC20(wantAddress).balanceOf(address(this));
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
        IERC20(wantAddress).safeTransfer(zorroControllerAddress, _wantAmt);

        return sharesRemoved;
    }

    /// @notice Converts Want token back into USD to be ready for withdrawal, transfers back to sender
    /// @param _amount The Want token quantity to exchange
    /// @param _maxMarketMovementAllowed The max slippage allowed for swaps. 1000 = 0 %, 995 = 0.5%, etc.
    /// @return uint256 Amount of USDC token obtained
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
        // Preflight checks
        require(_amount > 0, "Want amt must be > 0");

        // Safely transfer Want token from sender
        IERC20(wantAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        // Use price feed to determine exchange rates
        uint256 _token0ExchangeRate = token0PriceFeed.getExchangeRate();
        uint256 _token1ExchangeRate = token1PriceFeed.getExchangeRate();

        // Check if vault is for single asset staking
        if (isSingleAssetDeposit) {
            // If so, immediately swap the Want token for USDC

            IAMMRouter02(uniRouterAddress).safeSwap(
                _amount,
                _token0ExchangeRate,
                1e12,
                _maxMarketMovementAllowed,
                token0ToUSDCPath,
                msg.sender,
                block.timestamp.add(600)
            );
        } else {
            // If not, exit the LP pool and swap assets to USDC

            // Exit LP pool
            _exitPool(_amount, _maxMarketMovementAllowed, address(this));

            // Swap tokens back to USDC
            uint256 token0Amt = IERC20(token0Address).balanceOf(address(this));
            uint256 token1Amt = IERC20(token1Address).balanceOf(address(this));
            // Swap token0 for USDC
            IAMMRouter02(uniRouterAddress).safeSwap(
                token0Amt,
                _token0ExchangeRate,
                1e12,
                _maxMarketMovementAllowed,
                token0ToUSDCPath,
                msg.sender,
                block.timestamp.add(600)
            );

            // Swap token1 for USDC (if applicable)
            if (token1Address != address(0)) {
                IAMMRouter02(uniRouterAddress).safeSwap(
                    token1Amt,
                    _token1ExchangeRate,
                    1e12,
                    _maxMarketMovementAllowed,
                    token1ToUSDCPath,
                    msg.sender,
                    block.timestamp.add(600)
                );
            }
        }

        // Calculate USDC balance
        return IERC20(tokenUSDCAddress).balanceOf(msg.sender);
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
        IAMMRouter02(uniRouterAddress).addLiquidity(
            token0Address,
            token1Address,
            _token0Amt,
            _token1Amt,
            _token0Amt.mul(_maxMarketMovementAllowed).div(1000),
            _token1Amt.mul(_maxMarketMovementAllowed).div(1000),
            _recipient,
            block.timestamp.add(600)
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
        // Get token balances in LP pool
        uint256 _balance0 = IERC20(token0Address).balanceOf(poolAddress);
        uint256 _balance1 = IERC20(token1Address).balanceOf(poolAddress);

        // Get total supply and calculate min amounts desired based on slippage
        uint256 _totalSupply = IERC20(poolAddress).totalSupply();
        uint256 _amount0Min = (_amountLP.mul(_balance0).div(_totalSupply))
            .mul(_maxMarketMovementAllowed)
            .div(1000);
        uint256 _amount1Min = (_amountLP.mul(_balance1).div(_totalSupply))
            .mul(_maxMarketMovementAllowed)
            .div(1000);

        // Remove liquidity
        IAMMRouter02(uniRouterAddress).removeLiquidity(
            token0Address,
            token1Address,
            _amountLP,
            _amount0Min,
            _amount1Min,
            _recipient,
            block.timestamp.add(600)
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
        // Only to be run if this contract is configured for auto-comnpounding
        require(isZorroComp, "!isZorroComp");
        // If onlyGov is set to true, only allow to proceed if the current caller is the govAddress
        if (onlyGov) {
            require(msg.sender == govAddress, "!gov");
        }

        // Harvest farm tokens
        _unfarm(0);

        // Get the balance of the Earned token on this contract (CAKE, BANANA, etc.)
        uint256 earnedAmt = IERC20(earnedAddress).balanceOf(address(this));

        // Get exchange rate from price feed
        uint256 _earnTokenExchangeRate = earnTokenPriceFeed.getExchangeRate();
        uint256 _token0ExchangeRate = token0PriceFeed.getExchangeRate();
        uint256 _token1ExchangeRate = token1PriceFeed.getExchangeRate();
        uint256 _ZORExchangeRate = ZORPriceFeed.getExchangeRate();
        uint256 _lpPoolOtherTokenExchangeRate = ZORPriceFeed.getExchangeRate();
        // Create rates struct
        ExchangeRates memory _rates = ExchangeRates({
            earn: _earnTokenExchangeRate,
            ZOR: _ZORExchangeRate,
            lpPoolOtherToken: _lpPoolOtherTokenExchangeRate
        });

        // Reassign value of earned amount after distributing fees
        earnedAmt = _distributeFees(earnedAmt);
        // Reassign value of earned amount after buying back a certain amount of Zorro and sharing revenue w/ ZOR stakeholders
        earnedAmt = _buyBackAndRevShare(
            earnedAmt,
            _maxMarketMovementAllowed,
            _rates
        );

        // If staking a single token (CAKE, BANANA), farm that token and exit
        if (isCOREStaking || isSingleAssetDeposit) {
            // Update the last earn block
            lastEarnBlock = block.number;
            _farm();
            return;
        }

        // Approve the router contract
        IERC20(earnedAddress).safeApprove(uniRouterAddress, 0);
        // Allow the router contract to spen up to earnedAmt
        IERC20(earnedAddress).safeIncreaseAllowance(
            uniRouterAddress,
            earnedAmt
        );

        // Swap Earned token to token0 if token0 is not the Earned token
        if (earnedAddress != token0Address) {
            // Swap half earned to token0
            IAMMRouter02(uniRouterAddress).safeSwap(
                earnedAmt.div(2),
                _earnTokenExchangeRate,
                _token0ExchangeRate,
                slippageFactor,
                earnedToToken0Path,
                address(this),
                block.timestamp.add(600)
            );
        }

        // Swap Earned token to token1 if token0 is not the Earned token
        if (earnedAddress != token1Address) {
            // Swap half earned to token1
            IAMMRouter02(uniRouterAddress).safeSwap(
                earnedAmt.div(2),
                _earnTokenExchangeRate,
                _token1ExchangeRate,
                slippageFactor,
                earnedToToken1Path,
                address(this),
                block.timestamp.add(600)
            );
        }

        // Get values of tokens 0 and 1
        uint256 token0Amt = IERC20(token0Address).balanceOf(address(this));
        uint256 token1Amt = IERC20(token1Address).balanceOf(address(this));
        // Provided that token0 and token1 are both > 0, add liquidity
        if (token0Amt > 0 && token1Amt > 0) {
            // Increase the allowance of the router to spend token0
            IERC20(token0Address).safeIncreaseAllowance(
                uniRouterAddress,
                token0Amt
            );
            // Increase the allowance of the router to spend token1
            IERC20(token1Address).safeIncreaseAllowance(
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
        ExchangeRates memory _rates
    ) internal override {
        // Authorize spending beforehand
        IERC20(earnedAddress).safeIncreaseAllowance(uniRouterAddress, _amount);

        // Swap to ZOR Token
        IAMMRouter02(uniRouterAddress).safeSwap(
            _amount.div(2),
            _rates.earn,
            _rates.ZOR,
            _maxMarketMovementAllowed,
            earnedToZORROPath,
            address(this),
            block.timestamp.add(600)
        );

        // Swap to Other token
        IAMMRouter02(uniRouterAddress).safeSwap(
            _amount.div(2),
            _rates.earn,
            _rates.lpPoolOtherToken,
            _maxMarketMovementAllowed,
            earnedToZORLPPoolOtherTokenPath,
            address(this),
            block.timestamp.add(600)
        );

        // Enter LP pool and send received token to the burn address
        uint256 zorroTokenAmt = IERC20(ZORROAddress).balanceOf(address(this));
        uint256 otherTokenAmt = IERC20(zorroLPPoolOtherToken).balanceOf(address(this));
        IERC20(ZORROAddress).safeIncreaseAllowance(
            uniRouterAddress,
            zorroTokenAmt
        );
        IERC20(zorroLPPoolOtherToken).safeIncreaseAllowance(
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
    function _revShareOnChain(
        uint256 _amount,
        uint256 _maxMarketMovementAllowed,
        ExchangeRates memory _rates
    ) internal override {
        // Authorize spending beforehand
        IERC20(earnedAddress).safeIncreaseAllowance(uniRouterAddress, _amount);

        // Swap to ZOR
        IAMMRouter02(uniRouterAddress).safeSwap(
            _amount,
            _rates.earn,
            _rates.ZOR,
            _maxMarketMovementAllowed,
            earnedToZORROPath,
            zorroStakingVault,
            block.timestamp.add(600)
        );
    }

    /// @notice Swaps Earn token to USDC and sends to destination specified
    /// @param _earnedAmount Quantity of Earned tokens
    /// @param _destination Address to send swapped USDC to
    /// @param _maxMarketMovementAllowed Slippage factor. 950 = 5%, 990 = 1%, etc.
    function _swapEarnedToUSDC(
        uint256 _earnedAmount,
        address _destination,
        uint256 _maxMarketMovementAllowed,
        ExchangeRates memory _rates
    ) internal override {
        // Perform swap with Uni router
        IAMMRouter02(uniRouterAddress).safeSwap(
            _earnedAmount,
            _rates.earn,
            1e12,
            _maxMarketMovementAllowed,
            earnedToUSDCPath,
            _destination,
            block.timestamp.add(600)
        );
    }
}
