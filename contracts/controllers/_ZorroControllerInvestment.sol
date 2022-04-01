// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./_ZorroControllerBase.sol";

import "../interfaces/IVault.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "../libraries/Math.sol";

import "../tokens/ZorroTokens.sol";

import "../libraries/SafeSwap.sol";

// TODO||: VERY IMPORTANT: Once code is done, convert all ABI encoded raw strings to .selector calls
// TODO: VERY IMPORTANT: Make sure all .call()s are followed by a require(success). Otherwise danger.
// TODO: Do an overall audit of the code base to see where we should emit events.

contract ZorroControllerInvestment is ZorroControllerBase {
    /* Libraries */
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using CustomMath for uint256;
    using SafeSwapUni for IAMMRouter02;

    /* Cash flow */

    /// @notice Deposit Want tokens to associated Vault
    /// @param _pid index of pool
    /// @param _wantAmt how much Want token to deposit
    /// @param _weeksCommitted how many weeks the user is committing to on this vault
    function deposit(
        uint256 _pid,
        uint256 _wantAmt,
        uint256 _weeksCommitted
    ) public nonReentrant {
        // Get pool info
        PoolInfo storage pool = poolInfo[_pid];

        // Safely allow this contract to transfer the Want token from the sender to the underlying Vault contract
        pool.want.safeIncreaseAllowance(address(this), _wantAmt);

        // Transfer the Want token from the user to the Vault contract
        IERC20(pool.want).safeTransferFrom(msg.sender, pool.vault, _wantAmt);

        // Call core deposit function
        _deposit(_pid, msg.sender, "", _wantAmt, _weeksCommitted, block.timestamp);
    }

    /// @notice Internal function for depositing Want tokens into Vault
    /// @dev Because the vault entry date can be backdated, this is a dangerous method and should only be called indirectly through other functions
    /// @param _pid index of pool
    /// @param _account address of on-chain user
    /// @param _wantAmt how much Want token to deposit (must already be sent to vault contract)
    /// @param _weeksCommitted how many weeks the user is committing to on this vault
    /// @param _enteredVaultAt Date to backdate vault entry to
    function _deposit(
        uint256 _pid,
        address _account,
        bytes memory _foreignAccount,
        uint256 _wantAmt,
        uint256 _weeksCommitted,
        uint256 _enteredVaultAt
    ) internal {
        // Get pool info
        PoolInfo storage pool = poolInfo[_pid];

        // Preflight checks
        require(_wantAmt > 0, "_wantAmt must be > 0!");

        // Update the pool before anything to ensure rewards have been updated and transferred
        updatePool(_pid);

        // Perform the actual deposit function on the underlying Vault contract and get the number of shares to add
        uint256 sharesAdded = IVault(poolInfo[_pid].vault).depositWantToken(
            _account,
            _foreignAccount,
            _wantAmt
        );
        // Determine time multiplier value. Set to 1e12 if the vault is the Zorro staking vault (because we don't do time multipliers on this vault)
        uint256 timeMultiplier = 1e12;
        if (pool.vault != zorroStakingVault) {
            // Determine the time multiplier value based on the duration committed to in weeks
            timeMultiplier = getTimeMultiplier(_weeksCommitted);
        }
        // Determine the individual user contribution based on the quantity of tokens to stake and the time multiplier
        uint256 contributionAdded = getUserContribution(
            sharesAdded,
            timeMultiplier
        );
        // Increment the pool's total contributions by the contribution added
        pool.totalTrancheContributions = pool.totalTrancheContributions.add(
            contributionAdded
        );
        // Update the reward debt that the user owes by multiplying user share % by the pool's accumulated Zorro rewards
        uint256 newTrancheShare = contributionAdded.mul(1e12).div(
            pool.totalTrancheContributions
        );
        uint256 rewardDebt = pool.accZORRORewards.mul(newTrancheShare).div(
            1e12
        );
        // Push a new tranche for this user
        trancheInfo[_pid][_account].push(
            TrancheInfo({
                contribution: contributionAdded,
                timeMultiplier: timeMultiplier,
                rewardDebt: rewardDebt,
                durationCommittedInWeeks: _weeksCommitted,
                enteredVaultAt: _enteredVaultAt,
                exitedVaultStartingAt: 0
            })
        );
        // Emit deposit event
        emit Deposit(_account, _pid, _wantAmt);
    }

    /// @notice Deposits funds in a full service manner (performs autoswaps and obtains Want tokens)
    /// @param _pid index of pool to deposit into
    /// @param _valueUSDC value in USDC (in ether units) to deposit
    /// @param _weeksCommitted how many weeks to commit to the Pool (can be 0 or any uint)
    /// @param _maxMarketMovement factor to account for max market movement/slippage. The definition varies by Vault, so consult the associated Vault contract for info
    function depositFullService(
        uint256 _pid,
        uint256 _valueUSDC,
        uint256 _weeksCommitted,
        uint256 _maxMarketMovement
    ) public nonReentrant {
        // Get Pool, Vault contract
        address vaultAddr = poolInfo[_pid].vault;

        // Approve spending of USDC (from user to this contract)
        IERC20(defaultStablecoin).safeIncreaseAllowance(
            address(this),
            _valueUSDC
        );
        // Safe transfer to Vault contract
        IERC20(defaultStablecoin).safeTransferFrom(
            msg.sender,
            vaultAddr,
            _valueUSDC
        );

        // Run core full deposit
        _depositFullService(
            _pid,
            msg.sender,
            "",
            _valueUSDC,
            _weeksCommitted,
            block.timestamp,
            _maxMarketMovement
        );
    }

    /// @notice Private function for depositing
    /// @dev Dangerous method, as vaultEnteredAt can be backdated
    /// @param _pid index of pool to deposit into
    /// @param _account address of user on-chain
    /// @param _foreignAccount the cross chain wallet that initiated this call, if applicable.
    /// @param _valueUSDC value in USDC (in ether units) to deposit
    /// @param _weeksCommitted how many weeks to commit to the Pool (can be 0 or any uint)
    /// @param _vaultEnteredAt date that the vault was entered at
    /// @param _maxMarketMovement factor to account for max market movement/slippage. The definition varies by Vault, so consult the associated Vault contract for info
    function _depositFullService(
        uint256 _pid,
        address _account,
        bytes memory _foreignAccount,
        uint256 _valueUSDC,
        uint256 _weeksCommitted,
        uint256 _vaultEnteredAt,
        uint256 _maxMarketMovement
    ) internal {
        // Get Pool, Vault contract
        address vaultAddr = poolInfo[_pid].vault;
        IVault vault = IVault(vaultAddr);

        // Exchange USDC for Want token in the Vault contract
        uint256 _wantAmt = vault.exchangeUSDForWantToken(
            _valueUSDC,
            _maxMarketMovement
        );

        // Safe increase allowance and xfer Want to vault contract
        IERC20(poolInfo[_pid].want).safeIncreaseAllowance(vaultAddr, _wantAmt);

        // Make deposit
        // Call core deposit function
        _deposit(_pid, _account, _foreignAccount, _wantAmt, _weeksCommitted, _vaultEnteredAt);
    }

    /// @notice Fully withdraw Want tokens from underlying Vault.
    /// @param _pid index of pool
    /// @param _trancheId index of tranche
    /// @param _harvestOnly If true, will only harvest Zorro tokens but not do a withdrawal
    /// @return Amount of Want token withdrawn
    function withdraw(
        uint256 _pid,
        uint256 _trancheId,
        bool _harvestOnly
    ) public nonReentrant returns (uint256) {
        // Withdraw Want token
        uint256 _wantAmt = _withdraw(
            _pid,
            msg.sender,
            _trancheId,
            _harvestOnly
        );

        // Transfer to user and return Want amount
        IERC20(poolInfo[_pid].want).safeTransfer(msg.sender, _wantAmt);

        return _wantAmt;
    }

    /// @notice Internal function for withdrawing Want tokens from underlying Vault.
    /// @param _pid index of pool
    /// @param _account Address of the 
    /// @param _trancheId index of tranche
    /// @param _harvestOnly If true, will only harvest Zorro tokens but not do a withdrawal
    /// @return Amount of Want token withdrawn
    function _withdraw(
        uint256 _pid,
        address _account,
        uint256 _trancheId,
        bool _harvestOnly
    ) internal returns (uint256) {
        // Update the pool before anything to ensure rewards have been updated and transferred
        updatePool(_pid);

        // Get pool and current tranche info
        PoolInfo storage pool = poolInfo[_pid];
        TrancheInfo storage tranche = trancheInfo[_pid][_account][_trancheId];

        /* Preflight checks on contributions */
        require(tranche.contribution > 0, "tranche.contribution is 0");
        require(
            pool.totalTrancheContributions > 0,
            "totalTrancheContributions is 0"
        );

        // Withdraw pending ZORRO rewards (a.k.a. "Harvest")
        uint256 trancheShare = tranche.contribution.mul(1e12).div(
            pool.totalTrancheContributions
        );
        uint256 pendingRewards = trancheShare
            .mul(pool.accZORRORewards)
            .div(1e12)
            .sub(tranche.rewardDebt);
        if (pendingRewards > 0) {
            // Check if this is an early withdrawal
            // If so, slash the accumulated rewards proportionally to the % time remaining before maturity of the time commitment
            // If not, distribute rewards as normal
            uint256 oneWeek = 1 weeks;
            uint256 timeRemainingInCommitment = tranche
                .enteredVaultAt
                .add(tranche.durationCommittedInWeeks.mul(oneWeek))
                .sub(block.timestamp);
            uint256 rewardsDue = 0;
            uint256 slashedRewards = 0;
            if (timeRemainingInCommitment > 0) {
                slashedRewards = pendingRewards
                    .mul(timeRemainingInCommitment)
                    .div(tranche.durationCommittedInWeeks.mul(oneWeek));
                rewardsDue = pendingRewards.sub(slashedRewards);
            } else {
                rewardsDue = pendingRewards;
            }
            // Transfer ZORRO rewards to user, net of any applicable slashing
            _safeZORROTransfer(_account, rewardsDue);
            // Transfer any slashed rewards to single Zorro staking vault, if applicable
            if (slashedRewards > 0) {
                address singleStakingVaultZORRO = poolInfo[_pid].vault;
                // Transfer slashed rewards to vault to reward ZORRO stakers
                _safeZORROTransfer(singleStakingVaultZORRO, slashedRewards);
            }
        }

        // Perform the actual withdrawal function on the underlying Vault contract and get the number of shares to remove
        IVault(poolInfo[_pid].vault).withdrawWantToken(_account, _harvestOnly);

        // Update shares safely
        pool.totalTrancheContributions = pool.totalTrancheContributions.sub(
            tranche.contribution
        );

        // Calculate Want token balance
        uint256 _wantBal = IERC20(pool.want).balanceOf(address(this));

        // All withdrawals are full withdrawals so delete the tranche
        deleteTranche(_pid, _trancheId, _account);

        // Emit withdrawal event and return want balance
        emit Withdraw(_account, _pid, _trancheId, _wantBal);

        return _wantBal;
    }

    /// @notice Delete a tranche from a user's tranches
    /// @param _pid index of pool to deposit into
    /// @param _trancheId index of tranche
    /// @param _user User to remove tranche from
    function deleteTranche(
        uint256 _pid,
        uint256 _trancheId,
        address _user
    ) internal {
        // Determine the number of tranches
        uint256 _trancheLength = trancheInfo[_pid][_user].length;
        // Shift tranche to current index
        trancheInfo[_pid][_user][_trancheId] = trancheInfo[_pid][_user][
            _trancheLength - 1
        ];
        // Pop last item off of tranche array
        trancheInfo[_pid][_user].pop();
    }

    /// @notice Withdraws funds from a pool and converts the Want token into USDC
    /// @param _pid index of pool to deposit into
    /// @param _trancheId index of tranche
    /// @param _harvestOnly If true, will only harvest Zorro tokens but not do a withdrawal
    /// @param _maxMarketMovement factor to account for max market movement/slippage. The definition varies by Vault, so consult the associated Vault contract for info
    /// @return Amount (in USDC) returned
    function withdrawalFullService(
        uint256 _pid,
        uint256 _trancheId,
        bool _harvestOnly,
        uint256 _maxMarketMovement
    ) public nonReentrant returns (uint256) {
        // Withdraw Want token
        uint256 _amountUSDC = _withdrawalFullService(
            msg.sender,
            _pid,
            _trancheId,
            _harvestOnly,
            _maxMarketMovement
        );

        // Send USDC funds back to sender
        IERC20(defaultStablecoin).safeTransfer(msg.sender, _amountUSDC);

        return _amountUSDC;
    }

    /// @notice Private function for withdrawing funds from a pool and converting the Want token into USDC
    /// @param _account address of user
    /// @param _pid index of pool to deposit into
    /// @param _trancheId index of tranche
    /// @param _harvestOnly If true, will only harvest Zorro tokens but not do a withdrawal
    /// @param _maxMarketMovement factor to account for max market movement/slippage. The definition varies by Vault, so consult the associated Vault contract for info
    /// @return uint256 Amount (in USDC) returned
    function _withdrawalFullService(
        address _account,
        uint256 _pid,
        uint256 _trancheId,
        bool _harvestOnly,
        uint256 _maxMarketMovement
    ) internal returns (uint256) {
        // Update tranche status
        trancheInfo[_pid][_account][_trancheId].exitedVaultStartingAt = block
            .timestamp;
        // Get Vault contract
        address _vaultAddr = poolInfo[_pid].vault;
        IVault vault = IVault(_vaultAddr);

        // Call core withdrawal function (returns actual amount withdrawn)
        uint256 _wantAmtWithdrawn = _withdraw(
            _pid,
            _account,
            _trancheId,
            _harvestOnly
        );

        // Safe increase spending of Vault contract for Want token
        IERC20(poolInfo[_pid].want).safeIncreaseAllowance(
            _vaultAddr,
            _wantAmtWithdrawn
        );

        // Exchange Want for USD
        uint256 amount = vault.exchangeWantTokenForUSD(
            _wantAmtWithdrawn,
            _maxMarketMovement
        );

        return amount;
    }

    /// @notice Transfer all assets from a tranche in one vault to a new vault (works on-chain only)
    /// @param _fromPid index of pool FROM
    /// @param _fromTrancheId index of tranche FROM
    /// @param _toPid index of pool TO
    /// @param _maxMarketMovement factor to account for max market movement/slippage. The definition varies by Vault, so consult the associated Vault contract for info
    function transferInvestment(
        uint256 _fromPid,
        uint256 _fromTrancheId,
        uint256 _toPid,
        uint256 _maxMarketMovement
    ) public nonReentrant {
        // Get weeks committed and entered at
        uint256 weeksCommitted = trancheInfo[_fromPid][msg.sender][
            _fromTrancheId
        ].durationCommittedInWeeks;
        uint256 enteredVaultAt = trancheInfo[_fromPid][msg.sender][
            _fromTrancheId
        ].enteredVaultAt;
        // Withdraw
        uint256 withdrawnUSDC = _withdrawalFullService(
            msg.sender,
            _fromPid,
            _fromTrancheId,
            true,
            _maxMarketMovement
        );
        // Redeposit
        address[] memory sourceTokens;
        sourceTokens[0] = defaultStablecoin;
        _depositFullService(
            _toPid,
            msg.sender,
            withdrawnUSDC,
            weeksCommitted,
            enteredVaultAt,
            _maxMarketMovement
        );
        emit TransferInvestment(msg.sender, _fromPid, _fromTrancheId, _toPid);
    }

    /// @notice Withdraw the maximum number of Want tokens from a pool
    /// @param _pid index of pool
    function withdrawAll(uint256 _pid) public nonReentrant {
        uint256 numTranches = trancheLength(_pid, msg.sender);
        for (uint256 tid = 0; tid < numTranches; ++tid) {
            withdraw(_pid, tid, false);
        }
    }

    /* Earnings */

    /// @notice Pays the ZOR single staking pool the revenue share amount specified
    /// @param _amountUSDC Amount of USDC to send as ZOR revenue share
    /// @param _ZORROExchangeRate ZOR per USD, times 1e12
    function _revShareOnChain(uint256 _amountUSDC, uint256 _ZORROExchangeRate)
        internal
    {
        // Authorize spending beforehand
        IERC20(defaultStablecoin).safeIncreaseAllowance(
            uniRouterAddress,
            _amountUSDC
        );

        // Swap to ZOR
        IAMMRouter02(uniRouterAddress).safeSwap(
            _amountUSDC,
            1e12,
            _ZORROExchangeRate,
            defaultMaxMarketMovement,
            USDCToZorroPath,
            zorroStakingVault,
            block.timestamp.add(600)
        );
    }

    /// @notice Adds liquidity to the main ZOR LP pool and burns the resulting LP token
    /// @param _amountUSDC Amount of USDC to add as liquidity
    /// @param _ZORROExchangeRate ZOR per USD, times 1e12
    function _buybackOnChain(uint256 _amountUSDC, uint256 _ZORROExchangeRate)
        internal
    {
        // Authorize spending beforehand
        IERC20(defaultStablecoin).safeIncreaseAllowance(
            uniRouterAddress,
            _amountUSDC
        );

        // Determine exchange rates using Oracle as necessary
        uint256 _exchangeRateLPPoolToken0;
        uint256 _exchangeRateLPPoolToken1;
        // Assign ZOR exchange rate depending on which token it is in the pool (0, 1)
        if (zorroLPPoolToken0 == ZORRO) {
            _exchangeRateLPPoolToken0 = _ZORROExchangeRate;
            (, int256 _amount1, , , ) = _priceFeedLPPoolToken1
                .latestRoundData();
            _exchangeRateLPPoolToken1 = uint256(_amount1);
        } else if (zorroLPPoolToken1 == ZORRO) {
            (, int256 _amount0, , , ) = _priceFeedLPPoolToken0
                .latestRoundData();
            _exchangeRateLPPoolToken0 = uint256(_amount0);
            _exchangeRateLPPoolToken1 = _ZORROExchangeRate;
        }

        // Swap to Token 0
        IAMMRouter02(uniRouterAddress).safeSwap(
            _amountUSDC.div(2),
            1e12,
            _exchangeRateLPPoolToken0,
            defaultMaxMarketMovement,
            USDCToZorroLPPoolToken0Path,
            address(this),
            block.timestamp.add(600)
        );

        // Swap to Token 1
        IAMMRouter02(uniRouterAddress).safeSwap(
            _amountUSDC.div(2),
            1e12,
            _exchangeRateLPPoolToken1,
            defaultMaxMarketMovement,
            USDCToZorroLPPoolToken1Path,
            address(this),
            block.timestamp.add(600)
        );

        // Enter LP pool
        uint256 token0Amt = IERC20(zorroLPPoolToken0).balanceOf(address(this));
        uint256 token1Amt = IERC20(zorroLPPoolToken1).balanceOf(address(this));
        IERC20(zorroLPPoolToken0).safeIncreaseAllowance(
            uniRouterAddress,
            token0Amt
        );
        IERC20(zorroLPPoolToken1).safeIncreaseAllowance(
            uniRouterAddress,
            token1Amt
        );
        IAMMRouter02(uniRouterAddress).addLiquidity(
            zorroLPPoolToken0,
            zorroLPPoolToken1,
            token0Amt,
            token1Amt,
            token0Amt.mul(defaultMaxMarketMovement).div(1000),
            token1Amt.mul(defaultMaxMarketMovement).div(1000),
            burnAddress,
            block.timestamp.add(600)
        );
    }

    /* Allocations */

    /// @notice Calculate time multiplier based on duration committed
    /// @param durationInWeeks number of weeks committed into Vault
    /// @return multiplier factor, times 1e12
    function getTimeMultiplier(uint256 durationInWeeks)
        public
        view
        returns (uint256)
    {
        if (isTimeMultiplierActive) {
            return
                (
                    uint256(1).add(
                        (uint256(2).div(10)).mul(durationInWeeks.sqrt())
                    )
                ).mul(1e12);
        } else {
            return 1e12;
        }
    }

    /// @notice The contribution of the user, meant to be used in rewards allocations
    /// @param _liquidityCommitted How many tokens staked (e.g. LP tokens)
    /// @param _timeMultiplier Time multiplier value (from getTimeMultiplier())
    /// @return The relative contribution of the user (unitless)
    function getUserContribution(
        uint256 _liquidityCommitted,
        uint256 _timeMultiplier
    ) public pure returns (uint256) {
        return _liquidityCommitted.mul(_timeMultiplier).div(1e12);
    }
}
