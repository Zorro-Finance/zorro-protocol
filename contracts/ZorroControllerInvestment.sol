// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ZorroControllerBase.sol";

import "./interfaces/IVault.sol";

import "./libraries/SafeERC20.sol";

import "./libraries/SafeMath.sol";

import "./libraries/Math.sol";

contract ZorroControllerInvestment is ZorroControllerBase {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using CustomMath for uint256;

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
        _deposit(_pid, msg.sender, _wantAmt, _weeksCommitted, block.timestamp);
    }

    /// @notice Internal function for depositing Want tokens into Vault
    /// @dev Because the vault entry date can be backdated, this is a dangerous method and should only be called indirectly through other functions
    /// @param _pid index of pool
    /// @param _user address of user
    /// @param _wantAmt how much Want token to deposit
    /// @param _weeksCommitted how many weeks the user is committing to on this vault
    /// @param _enteredVaultAt Date to backdate vault entry to
    function _deposit(
        uint256 _pid,
        address _user,
        uint256 _wantAmt,
        uint256 _weeksCommitted,
        uint256 _enteredVaultAt
    ) internal {
        // Preflight checks
        require(_wantAmt > 0, "_wantAmt must be > 0!");

        // Update the pool before anything to ensure rewards have been updated and transferred
        updatePool(_pid);

        // Get pool info
        PoolInfo storage pool = poolInfo[_pid];

        // Safely allow the underlying Zorro Vault contract to transfer the Want token
        pool.want.safeIncreaseAllowance(pool.vault, _wantAmt);
        // Perform the actual deposit function on the underlying Vault contract and get the number of shares to add
        uint256 sharesAdded = IVault(poolInfo[_pid].vault).depositWantToken(
            _wantAmt
        );
        // Determine the time multiplier value based on the duration committed to in weeks
        uint256 timeMultiplier = getTimeMultiplier(_weeksCommitted);
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
        trancheInfo[_pid][_user].push(
            TrancheInfo({
                contribution: contributionAdded,
                timeMultiplier: timeMultiplier,
                durationCommittedInWeeks: _weeksCommitted,
                enteredVaultAt: _enteredVaultAt,
                rewardDebt: rewardDebt
            })
        );
        // Emit deposit event
        emit Deposit(_user, _pid, _wantAmt);
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
        _depositFullService(
            _pid,
            msg.sender,
            _valueUSDC,
            _weeksCommitted,
            block.timestamp,
            _maxMarketMovement
        );
    }

    /// @notice Private function for depositing
    /// @dev Dangerous method, as vaultEnteredAt can be backdated
    /// @param _pid index of pool to deposit into
    /// @param _user address of user
    /// @param _valueUSDC value in USDC (in ether units) to deposit
    /// @param _weeksCommitted how many weeks to commit to the Pool (can be 0 or any uint)
    /// @param _vaultEnteredAt date that the vault was entered at
    /// @param _maxMarketMovement factor to account for max market movement/slippage. The definition varies by Vault, so consult the associated Vault contract for info
    function _depositFullService(
        uint256 _pid,
        address _user,
        uint256 _valueUSDC,
        uint256 _weeksCommitted,
        uint256 _vaultEnteredAt,
        uint256 _maxMarketMovement
    ) internal {
        // Get Vault contract
        IVault vault = IVault(poolInfo[_pid].vault);

        // Exchange USDC for Want token in the Vault contract
        uint256 wantAmt = vault.exchangeUSDForWantToken(
            _user,
            _valueUSDC,
            _maxMarketMovement
        );

        // Make deposit or record claim depending on whether exchange is synchronous
        // Call core deposit function
        _deposit(_pid, _user, wantAmt, _weeksCommitted, _vaultEnteredAt);
    }

    /// @notice Withdraw Want tokens from underlying Vault.
    /// @param _pid index of pool
    /// @param _trancheId index of tranche
    /// @param _wantAmt how much Want token to withdraw. If 0 is specified, function will only harvest Zorro rewards and not actually withdraw
    /// @return Amount of Want token withdrawn
    function withdraw(
        uint256 _pid,
        uint256 _trancheId,
        uint256 _wantAmt
    ) public nonReentrant returns (uint256) {
        return _withdraw(_pid, msg.sender, _trancheId, _wantAmt);
    }

    /// @notice Internal function for withdrawing Want tokens from underlying Vault.
    /// @param _pid index of pool
    /// @param _trancheId index of tranche
    /// @param _wantAmt how much Want token to withdraw. If 0 is specified, function will only harvest Zorro rewards and not actually withdraw
    /// @return Amount of Want token withdrawn
    function _withdraw(
        uint256 _pid,
        address _user,
        uint256 _trancheId,
        uint256 _wantAmt
    ) internal returns (uint256) {
        // Update the pool before anything to ensure rewards have been updated and transferred
        updatePool(_pid);

        // Get pool and current tranche info
        PoolInfo storage pool = poolInfo[_pid];
        TrancheInfo storage tranche = trancheInfo[_pid][_user][_trancheId];

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
            if (timeRemainingInCommitment > 0) {
                rewardsDue = pendingRewards.sub(
                    pendingRewards.mul(timeRemainingInCommitment).div(
                        tranche.durationCommittedInWeeks.mul(oneWeek)
                    )
                );
            } else {
                rewardsDue = pendingRewards;
            }
            safeZORROTransfer(_user, rewardsDue);
        }

        // Get current amount in tranche
        uint256 amount = tranche.contribution.mul(1e12).div(
            tranche.timeMultiplier
        );
        // Establish cap for safety
        if (_wantAmt > amount) {
            _wantAmt = amount;
        }
        // If the _wantAmt is > 0, transfer Want tokens from the underlying Zorro Vault contract and update shares. If NOT, user shares will NOT be updated.
        if (_wantAmt > 0) {
            // Perform the actual withdrawal function on the underlying Vault contract and get the number of shares to remove
            uint256 sharesRemoved = IVault(poolInfo[_pid].vault)
                .withdrawWantToken(_wantAmt);
            uint256 contributionRemoved = getUserContribution(
                sharesRemoved,
                tranche.timeMultiplier
            );
            // Update shares safely
            if (contributionRemoved > tranche.contribution) {
                tranche.contribution = 0;
                pool.totalTrancheContributions = pool
                    .totalTrancheContributions
                    .sub(tranche.contribution);
            } else {
                tranche.contribution = tranche.contribution.sub(
                    contributionRemoved
                );
                pool.totalTrancheContributions = pool
                    .totalTrancheContributions
                    .sub(contributionRemoved);
            }
            // Withdraw Want tokens from this contract to sender
            uint256 wantBal = IERC20(pool.want).balanceOf(address(this));
            if (wantBal < _wantAmt) {
                _wantAmt = wantBal;
            }
            pool.want.safeTransfer(address(_user), _wantAmt);

            // Remove tranche from this user if it's a full withdrawal
            if (_wantAmt == amount) {
                deleteTranche(_pid, _trancheId, _user);
            }
        }
        // Note: Tranche's reward debt is issued on every deposit/withdrawal so that we don't count the full pool accumulation of ZORRO rewards.
        uint256 newTrancheShare = tranche.contribution.mul(1e12).div(
            pool.totalTrancheContributions
        );
        tranche.rewardDebt = pool.accZORRORewards.mul(newTrancheShare).div(
            1e12
        );
        emit Withdraw(_user, _pid, _trancheId, _wantAmt);

        return _wantAmt;
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
    /// @param _wantAmt value in Want tokens to withdraw (0 will result in harvest and uint256(-1) will result in max value)
    /// @param _maxMarketMovement factor to account for max market movement/slippage. The definition varies by Vault, so consult the associated Vault contract for info
    /// @return Amount (in USDC) returned
    function withdrawalFullService(
        uint256 _pid,
        uint256 _trancheId,
        uint256 _wantAmt,
        uint256 _maxMarketMovement
    ) public nonReentrant returns (uint256) {
        uint256 amount = _withdrawalFullService(
            _pid,
            msg.sender,
            _trancheId,
            _wantAmt,
            _maxMarketMovement
        );
        return amount;
    }

    /// @notice Private function for withdrawing funds from a pool and converting the Want token into USDC
    /// @param _pid index of pool to deposit into
    /// @param _user address of user
    /// @param _trancheId index of tranche
    /// @param _wantAmt value in Want tokens to withdraw (0 will result in harvest and uint256(-1) will result in max value)
    /// @param _maxMarketMovement factor to account for max market movement/slippage. The definition varies by Vault, so consult the associated Vault contract for info
    /// @return Amount (in USDC) returned
    function _withdrawalFullService(
        uint256 _pid,
        address _user,
        uint256 _trancheId,
        uint256 _wantAmt,
        uint256 _maxMarketMovement
    ) internal returns (uint256) {
        // Get Vault contract
        IVault vault = IVault(poolInfo[_pid].vault);

        // Call core withdrawal function (returns actual amount withdrawn)
        uint256 wantAmtWithdrawn = _withdraw(_pid, _user, _trancheId, _wantAmt);

        uint256 amount = vault.exchangeWantTokenForUSD(_user, wantAmtWithdrawn, _maxMarketMovement);

        return amount;
    }

    /// @notice Transfer all assets from a tranche in one vault to a new vault
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
            _fromPid,
            msg.sender,
            _fromTrancheId,
            type(uint256).max,
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
            withdraw(_pid, type(uint256).max, tid);
        }
    }

    /* Allocations */

    /// @notice Calculate time multiplier based on duration committed
    /// @param durationInWeeks number of weeks committed into Vault
    /// @return multiplier factor, times 1e12
    function getTimeMultiplier(uint256 durationInWeeks)
        private
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
    ) private pure returns (uint256) {
        return _liquidityCommitted.mul(_timeMultiplier).div(1e12);
    }
}
