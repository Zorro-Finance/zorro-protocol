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

import "@openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol";

/// @title Vault factory for VaultStandardAMM
contract VaultFactoryStandardAMM is Initializable, OwnableUpgradeable {
    /* State */

    VaultStandardAMM[] public deployedVaults; // All deployed vaults
    address public masterVault; // Address of the upgradeable proxy that delegates to the master vault contract

    /* Constructor */

    function initialize(address _masterVault) public initializer {
        // Set master vault address
        masterVault = _masterVault;

        // Ownable
        __Ownable_init();
    }

    /* Factory functions */

    function createVault(
        address _timelockOwner,
        VaultStandardAMM.VaultStandardAMMInit memory _initValue
    ) external onlyOwner {
        // Create clone
        VaultStandardAMM _vault = VaultStandardAMM(
            ClonesUpgradeable.clone(masterVault)
        );
        // Initialize cloned contract
        _vault.initialize(_timelockOwner, _initValue);
        // Add to array of deployed vaults
        deployedVaults.push(_vault);
    }

    function numVaults() external view returns (uint256) {
        return deployedVaults.length;
    }
}

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

        // Addresses
        govAddress = _initValue.keyAddresses.govAddress;
        onlyGov = true;
        zorroControllerAddress = _initValue.keyAddresses.zorroControllerAddress;
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
        tokenUSDCAddress = _initValue.keyAddresses.tokenUSDCAddress;

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
        USDCToToken0Path = _initValue.USDCToToken0Path;
        USDCToToken1Path = _initValue.USDCToToken1Path;
        earnedToZORLPPoolOtherTokenPath = _initValue
            .earnedToZORLPPoolOtherTokenPath;
        earnedToUSDCPath = _initValue.earnedToUSDCPath;
        // Corresponding reverse paths
        token0ToUSDCPath = _reversePath(USDCToToken0Path);
        token1ToUSDCPath = _reversePath(USDCToToken1Path);

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

        // Super call
        VaultBase.initialize(_timelockOwner);
    }

    /* Structs */

    struct VaultStandardAMMInit {
        uint256 pid;
        bool isHomeChain;
        VaultAddresses keyAddresses;
        address[] earnedToZORROPath;
        address[] earnedToToken0Path;
        address[] earnedToToken1Path;
        address[] USDCToToken0Path;
        address[] USDCToToken1Path;
        address[] earnedToZORLPPoolOtherTokenPath;
        address[] earnedToUSDCPath;
        VaultFees fees;
        VaultPriceFeeds priceFeeds;
    }

    /* Investment Actions */

    /// @notice Receives new deposits from user
    /// @param _account The address of the end user account making the deposit
    /// @param _wantAmt The amount of Want token to deposit (must already be transferred)
    /// @return sharesAdded Number of shares added
    function depositWantToken(address _account, uint256 _wantAmt)
        public
        override
        onlyZorroController
        nonReentrant
        whenNotPaused
        returns (uint256 sharesAdded)
    {
        // Preflight checks
        require(_wantAmt > 0, "Want dep < 0");

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
        userShares[_account] = userShares[_account].add(sharesAdded);

        // Farm Want token
        _farm();
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
        uint256 _balUSDC = IERC20(tokenUSDCAddress).balanceOf(address(this));
        // Check that USDC was actually deposited
        require(_amountUSDC > 0, "USDC deposit must be > 0");
        require(_amountUSDC <= _balUSDC, "USDC desired exceeded bal");

        // Use price feed to determine exchange rates
        uint256 _token0ExchangeRate = token0PriceFeed.getExchangeRate();
        uint256 _token1ExchangeRate = token1PriceFeed.getExchangeRate();

        // Increase allowance
        IERC20Upgradeable(tokenUSDCAddress).safeIncreaseAllowance(
            uniRouterAddress,
            _amountUSDC
        );

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
        uint256 token0Amt = IERC20Upgradeable(token0Address).balanceOf(
            address(this)
        );
        uint256 token1Amt = IERC20Upgradeable(token1Address).balanceOf(
            address(this)
        );
        IERC20Upgradeable(token0Address).safeIncreaseAllowance(
            uniRouterAddress,
            token0Amt
        );
        IERC20Upgradeable(token1Address).safeIncreaseAllowance(
            uniRouterAddress,
            token1Amt
        );

        _joinPool(token0Amt, token1Amt, _maxMarketMovementAllowed, msg.sender);

        // Calculate resulting want token balance
        return IERC20Upgradeable(wantAddress).balanceOf(msg.sender);
    }

    /// @notice Public function for farming Want token.
    function farm() public nonReentrant {
        _farm();
    }

    /// @notice Internal function for farming Want token. Responsible for staking Want token in a MasterChef/MasterApe-like contract
    function _farm() internal {
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
    /// @return wantUnfarmed The net amount of Want tokens unfarmed
    function _unfarm(uint256 _wantAmt) internal returns (uint256 wantUnfarmed) {
        // Withdraw the Want tokens from the Farm contract pool
        IAMMFarm(farmContractAddress).withdraw(pid, _wantAmt);

        // Init
        wantUnfarmed = _wantAmt;

        // Safety: Check balance of this contract's Want tokens held, and cap _wantAmt to that value
        uint256 _wantBal = IERC20Upgradeable(wantAddress).balanceOf(
            address(this)
        );
        if (wantUnfarmed > _wantBal) {
            wantUnfarmed = _wantBal;
        }
        // Safety: cap _wantAmt at the total quantity of Want tokens locked
        if (wantLockedTotal < _wantAmt) {
            wantUnfarmed = wantLockedTotal;
        }

        // Decrement the total Want locked tokens by the _wantAmt
        wantLockedTotal = wantLockedTotal.sub(wantUnfarmed);
    }

    /// @notice Fully withdraw Want tokens from the Farm contract (100% withdrawals only)
    /// @param _account Address of user
    /// @param _wantAmt The amount of Want token to withdraw
    /// @return sharesRemoved uint256 The number of shares removed
    function withdrawWantToken(address _account, uint256 _wantAmt)
        public
        override
        onlyZorroController
        nonReentrant
        whenNotPaused
        returns (uint256 sharesRemoved)
    {
        // Preflight checks
        require(_wantAmt > 0, "want amt <= 0");

        // Shares removed is proportional to the % of total Want tokens locked that _wantAmt represents
        sharesRemoved = _wantAmt.mul(sharesTotal).div(wantLockedTotal);
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

        // Unfarm Want token
        uint256 _wantUnfarmed = _unfarm(_wantAmt);

        // Finally, transfer the want amount from this contract, back to the ZorroController contract
        IERC20Upgradeable(wantAddress).safeTransfer(
            zorroControllerAddress,
            _wantUnfarmed
        );
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
        IERC20Upgradeable(wantAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        // Use price feed to determine exchange rates
        uint256 _token0ExchangeRate = token0PriceFeed.getExchangeRate();
        uint256 _token1ExchangeRate = token1PriceFeed.getExchangeRate();

        // Exit LP pool
        _exitPool(_amount, _maxMarketMovementAllowed, address(this));

        // Swap tokens back to USDC
        uint256 token0Amt = IERC20Upgradeable(token0Address).balanceOf(
            address(this)
        );
        uint256 token1Amt = IERC20Upgradeable(token1Address).balanceOf(
            address(this)
        );

        // Increase allowance
        IERC20Upgradeable(token0Address).safeIncreaseAllowance(
            uniRouterAddress,
            token0Amt
        );
        IERC20Upgradeable(token1Address).safeIncreaseAllowance(
            uniRouterAddress,
            token1Amt
        );

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

        // Swap token1 for USDC
        IAMMRouter02(uniRouterAddress).safeSwap(
            token1Amt,
            _token1ExchangeRate,
            1e12,
            _maxMarketMovementAllowed,
            token1ToUSDCPath,
            msg.sender,
            block.timestamp.add(600)
        );

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
        uint256 _balance0 = IERC20Upgradeable(token0Address).balanceOf(
            poolAddress
        );
        uint256 _balance1 = IERC20Upgradeable(token1Address).balanceOf(
            poolAddress
        );

        // Get total supply and calculate min amounts desired based on slippage
        uint256 _totalSupply = IERC20Upgradeable(poolAddress).totalSupply();
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

        // Create rates struct
        ExchangeRates memory _rates = ExchangeRates({
            earn: earnTokenPriceFeed.getExchangeRate(),
            ZOR: ZORPriceFeed.getExchangeRate(),
            lpPoolOtherToken: lpPoolOtherTokenPriceFeed.getExchangeRate()
        });

        // Distribute fees
        uint256 _controllerFee = _distributeFees(_earnedAmt);

        // Buyback & rev share
        (uint256 _buybackAmt, uint256 _revShareAmt) = _buyBackAndRevShare(
            _earnedAmt,
            _maxMarketMovementAllowed,
            _rates
        );

        // Allow the router contract to spen up to earnedAmt
        IERC20Upgradeable(earnedAddress).safeIncreaseAllowance(
            uniRouterAddress,
            _earnedAmt
        );

        // Swap Earned token to token0 if token0 is not the Earned token
        if (earnedAddress != token0Address) {
            // Swap half earned to token0
            IAMMRouter02(uniRouterAddress).safeSwap(
                (_earnedAmt.sub(_controllerFee).sub(_buybackAmt).sub(_revShareAmt)).div(2),
                _rates.earn,
                token0PriceFeed.getExchangeRate(),
                _maxMarketMovementAllowed,
                earnedToToken0Path,
                address(this),
                block.timestamp.add(600)
            );
        }

        // Swap Earned token to token1 if token0 is not the Earned token
        if (earnedAddress != token1Address) {
            // Swap half earned to token1
            IAMMRouter02(uniRouterAddress).safeSwap(
                (_earnedAmt.sub(_controllerFee).sub(_buybackAmt).sub(_revShareAmt)).div(2),
                _rates.earn,
                token1PriceFeed.getExchangeRate(),
                _maxMarketMovementAllowed,
                earnedToToken1Path,
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
        ExchangeRates memory _rates
    ) internal override {
        // Authorize spending beforehand
        IERC20Upgradeable(earnedAddress).safeIncreaseAllowance(
            uniRouterAddress,
            _amount
        );

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
    function _revShareOnChain(
        uint256 _amount,
        uint256 _maxMarketMovementAllowed,
        ExchangeRates memory _rates
    ) internal override {
        // Authorize spending beforehand
        IERC20Upgradeable(earnedAddress).safeIncreaseAllowance(
            uniRouterAddress,
            _amount
        );

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
        // Increase allowance
        IERC20Upgradeable(earnedAddress).safeIncreaseAllowance(
            uniRouterAddress,
            _earnedAmount
        );

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
