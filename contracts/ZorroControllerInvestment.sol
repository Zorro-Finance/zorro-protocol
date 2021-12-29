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
  using Math for uint256;

  /* Cash flow */

    /// @notice Deposit Want tokens to associated Vault
    /// @param _pid index of pool
    /// @param _wantAmt how much Want token to deposit
    /// @param _weeksCommitted how many weeks the user is committing to on this vault
    function deposit(uint256 _pid, uint256 _wantAmt, uint256 _weeksCommitted) public nonReentrant {
        _deposit(_pid, msg.sender, _wantAmt, _weeksCommitted, block.timestamp);
    }

    /// @notice Claim Want token and deposit (usually called after async settlement has occurred)
    /// @param _pid index of pool
    /// @param _user address of user
    /// @param _wantAmt amount of the Want token
    /// @param _token address of the Want token
    /// @param _weeksCommitted how many weeks the user is committing to on this vault
    function claimAndDeposit(uint256 _pid, address _user, uint256 _wantAmt, address _token, uint256 _weeksCommitted) external onlyOwner {
        // Claim 
        uint256 amountClaimed = _claimToken(_pid, _user, _wantAmt, _token);
        // Deposit
        _deposit(_pid, _user, amountClaimed, _weeksCommitted, block.timestamp);
    }

    /// @notice Internal function for depositing Want tokens into Vault
    /// @dev Because the vault entry date can be backdated, this is a dangerous method and should only be called indirectly through other functions
    /// @param _pid index of pool
    /// @param _user address of user
    /// @param _wantAmt how much Want token to deposit
    /// @param _weeksCommitted how many weeks the user is committing to on this vault
    /// @param _enteredVaultAt Date to backdate vault entry to
    function _deposit(uint256 _pid, address _user, uint256 _wantAmt, uint256 _weeksCommitted, uint256 _enteredVaultAt) internal {
        // Preflight checks
        require(_wantAmt > 0, "_wantAmt must be > 0!");

        // Update the pool before anything to ensure rewards have been updated and transferred
        updatePool(_pid);

        // Get pool info
        PoolInfo storage pool = poolInfo[_pid];

        // Safely allow the underlying Zorro Vault contract to transfer the Want token
        pool.want.safeIncreaseAllowance(pool.vault, _wantAmt);
        // Perform the actual deposit function on the underlying Vault contract and get the number of shares to add
        uint256 sharesAdded = IVault(poolInfo[_pid].vault).deposit(_user, _wantAmt);
        // Determine the time multiplier value based on the duration committed to in weeks
        uint256 timeMultiplier = getTimeMultiplier(_weeksCommitted);
        // Determine the individual user contribution based on the quantity of tokens to stake and the time multiplier
        uint256 contributionAdded = getUserContribution(sharesAdded, timeMultiplier);
        // Increment the pool's total contributions by the contribution added
        pool.totalTrancheContributions = pool.totalTrancheContributions.add(contributionAdded);
        // Update the reward debt that the user owes by multiplying user share % by the pool's accumulated Zorro rewards
        uint256 newTrancheShare = contributionAdded.mul(1e12).div(pool.totalTrancheContributions);
        uint256 rewardDebt = pool.accZORRORewards.mul(newTrancheShare).div(1e12);
        // Push a new tranche for this user
        trancheInfo[_pid][_user].push(TrancheInfo({
            contribution: contributionAdded,
            timeMultiplier: timeMultiplier,
            durationCommittedInWeeks: _weeksCommitted,
            enteredVaultAt: _enteredVaultAt,
            rewardDebt: rewardDebt
        }));
        // Emit deposit event
        emit Deposit(_user, _pid, _wantAmt);
    }

    /// @notice Deposits funds in a full service manner (performs autoswaps and obtains Want tokens)
    /// @param _pid index of pool to deposit into
    /// @param _valueUSDC value in USDC (in ether units) to deposit
    /// @param _sourceTokens list of tokens to autoswap from 
    /// @param _weeksCommitted how many weeks to commit to the Pool (can be 0 or any uint)
    function depositFullService(uint256 _pid, uint256 _valueUSDC, address[] memory _sourceTokens, uint256 _weeksCommitted) public nonReentrant {
        _depositFullService(_pid, msg.sender, _valueUSDC, _sourceTokens, _weeksCommitted, block.timestamp);
    }

    /// @notice Private function for depositing
    /// @dev Dangerous method, as vaultEnteredAt can be backdated
    /// @param _pid index of pool to deposit into
    /// @param _user address of user
    /// @param _valueUSDC value in USDC (in ether units) to deposit
    /// @param _sourceTokens list of tokens to autoswap from 
    /// @param _weeksCommitted how many weeks to commit to the Pool (can be 0 or any uint)
    /// @param _vaultEnteredAt date that the vault was entered at
    function _depositFullService(uint256 _pid, address _user, uint256 _valueUSDC, address[] memory _sourceTokens, uint256 _weeksCommitted, uint256 _vaultEnteredAt) internal {
        // Get library from pool
        address lib = poolInfo[_pid].lib;
        // Perform delegate call to autoswap and receive tokens and enter underlying vaults
        (bool success, bytes memory data) = lib.call(abi.encodeWithSignature("deposit(address, uint256, address[])", _user, _valueUSDC, _sourceTokens));
        require(success, "call to deposit() failed");
        (uint256 wantAmt, bool isSynchronous) = abi.decode(data, (uint256, bool));
        if (isSynchronous) {
            // Call core deposit function
            _deposit(_pid, _user, wantAmt, _weeksCommitted, _vaultEnteredAt);
        } else {
            // Record claim
            recordClaim(_pid, _user, wantAmt, address(poolInfo[_pid].want), 0);
        }
    }

    /// @notice Withdraw Want tokens from underlying Vault.
    /// @param _pid index of pool
    /// @param _trancheId index of tranche
    /// @param _wantAmt how much Want token to withdraw. If 0 is specified, function will only harvest Zorro rewards and not actually withdraw
    /// @return Amount of Want token withdrawn
    function withdraw(uint256 _pid, uint256 _trancheId, uint256 _wantAmt) public nonReentrant returns (uint256) {
        return _withdraw(_pid, msg.sender, _trancheId, _wantAmt);
    }

    /// @notice Claim Intermediary token and withdraw (usually called after async settlement has occurred)
    /// @param _pid index of pool
    /// @param _user address of user
    /// @param _wantAmt address of user
    /// @param _user address of user
    /// @param _user address of user
    // TODO: need to fix docstrings
    function claimAndWithdraw(uint256 _pid, address _user, uint256 _wantAmt, address _token) external onlyOwner {
        // Claim 
        uint256 amountClaimed = _claimToken(_pid, _user, _wantAmt, _token);
        // Withdraw claimed intermediary token
        address lib = poolInfo[_pid].lib;
        (bool success, bytes memory data) = lib.call(abi.encodeWithSignature("withdrawClaimedIntermedToken(address, uint256)", _user, amountClaimed));
        require(success, "call to withdrawClaimedIntermedToken() failed");
        uint valueUSDC = abi.decode(data, (uint256));
        require(valueUSDC > 0, "withdrawClaimedIntermedToken() yielded zero value");
    }

    /// @notice Internal function for withdrawing Want tokens from underlying Vault.
    /// @param _pid index of pool
    /// @param _trancheId index of tranche
    /// @param _wantAmt how much Want token to withdraw. If 0 is specified, function will only harvest Zorro rewards and not actually withdraw
    /// @return Amount of Want token withdrawn
    function _withdraw(uint256 _pid, address _user, uint256 _trancheId, uint256 _wantAmt) internal returns (uint256) {
        // Update the pool before anything to ensure rewards have been updated and transferred
        updatePool(_pid);

        // Get pool and current tranche info
        PoolInfo storage pool = poolInfo[_pid];
        TrancheInfo storage tranche = trancheInfo[_pid][_user][_trancheId];

        /* Preflight checks on contributions */
        require(tranche.contribution > 0, "tranche.contribution is 0");
        require(pool.totalTrancheContributions > 0, "totalTrancheContributions is 0");

        // Withdraw pending ZORRO rewards (a.k.a. "Harvest")
        uint256 trancheShare = tranche.contribution.mul(1e12).div(pool.totalTrancheContributions);
        uint256 pendingRewards = trancheShare.mul(pool.accZORRORewards).div(1e12).sub(tranche.rewardDebt);
        if (pendingRewards > 0) {
            // Check if this is an early withdrawal
            // If so, slash the accumulated rewards proportionally to the % time remaining before maturity of the time commitment
            // If not, distribute rewards as normal
            uint256 oneWeek = 1 weeks;
            uint256 timeRemainingInCommitment = tranche.enteredVaultAt.add(tranche.durationCommittedInWeeks.mul(oneWeek)).sub(block.timestamp);
            uint256 rewardsDue = 0;
            if (timeRemainingInCommitment > 0) {
                rewardsDue = pendingRewards.sub(pendingRewards.mul(timeRemainingInCommitment).div(tranche.durationCommittedInWeeks.mul(oneWeek)));
            } else {
                rewardsDue = pendingRewards;
            }
            safeZORROTransfer(_user, rewardsDue);
        }

        // Get current amount in tranche
        uint256 amount = tranche.contribution.mul(1e12).div(tranche.timeMultiplier);
        // Establish cap for safety
        if (_wantAmt > amount) {
            _wantAmt = amount;
        }
        // If the _wantAmt is > 0, transfer Want tokens from the underlying Zorro Vault contract and update shares. If NOT, user shares will NOT be updated. 
        if (_wantAmt > 0) {
            // Perform the actual withdrawal function on the underlying Vault contract and get the number of shares to remove
            uint256 sharesRemoved = IVault(poolInfo[_pid].vault).withdraw(_user, _wantAmt);
            uint256 contributionRemoved = getUserContribution(sharesRemoved, tranche.timeMultiplier);
            // Update shares safely
            if (contributionRemoved > tranche.contribution) {
                tranche.contribution = 0;
                pool.totalTrancheContributions = pool.totalTrancheContributions.sub(tranche.contribution);
            } else {
                tranche.contribution = tranche.contribution.sub(contributionRemoved);
                pool.totalTrancheContributions = pool.totalTrancheContributions.sub(contributionRemoved);
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
        uint256 newTrancheShare = tranche.contribution.mul(1e12).div(pool.totalTrancheContributions);
        tranche.rewardDebt = pool.accZORRORewards.mul(newTrancheShare).div(1e12);
        emit Withdraw(_user, _pid, _trancheId, _wantAmt);

        return _wantAmt;
    }

    /// @notice Delete a tranche from a user's tranches
    /// @param _pid index of pool to deposit into
    /// @param _trancheId index of tranche
    /// @param _user User to remove tranche from
    function deleteTranche(uint256 _pid, uint256 _trancheId, address _user) internal {
        // Determine the number of tranches
        uint256 _trancheLength = trancheInfo[_pid][_user].length;
        // Shift tranche to current index
        trancheInfo[_pid][_user][_trancheId] = trancheInfo[_pid][_user][_trancheLength - 1];
        // Pop last item off of tranche array
        trancheInfo[_pid][_user].pop();
    }

    /// @notice Withdraws funds from a pool and converts the Want token into USDC
    /// @param _pid index of pool to deposit into
    /// @param _trancheId index of tranche
    /// @param _wantAmt value in Want tokens to withdraw (0 will result in harvest and uint256(-1) will result in max value)
    /// @return Amount (in USDC) returned
    function withdrawalFullService(uint256 _pid, uint256 _trancheId, uint256 _wantAmt) public nonReentrant returns (uint256) {
        (uint256 amount, bool isSynchronous) = _withdrawalFullService(_pid, msg.sender, _trancheId, _wantAmt, false);
        require(isSynchronous, "not synchronous");
        return amount;
    }

    /// @notice Private function for withdrawing funds from a pool and converting the Want token into USDC
    /// @param _pid index of pool to deposit into
    /// @param _user address of user
    /// @param _trancheId index of tranche
    /// @param _wantAmt value in Want tokens to withdraw (0 will result in harvest and uint256(-1) will result in max value)
    /// @param _isForTransfer Whether this is for a transfer
    /// @return Amount (in USDC) returned
    function _withdrawalFullService(uint256 _pid, address _user, uint256 _trancheId, uint256 _wantAmt, bool _isForTransfer) internal returns (uint256, bool) {
        // Call core withdrawal function (returns actual amount withdrawn)
        uint256 wantAmtWithdrawn = _withdraw(_pid, _user, _trancheId, _wantAmt);
        // Get library from pool
        address lib = poolInfo[_pid].lib;
        // Perform delegate call to autoswap and receive tokens and enter underlying vaults
        (bool success, bytes memory data) = lib.call(abi.encodeWithSignature("withdraw(address, uint256)", _user, wantAmtWithdrawn));
        require(success, "call to withdraw() failed");
        // Parse and return amount data
        (uint256 amount, bool isSynchronous) = abi.decode(data, (uint256, bool));
        if (isSynchronous) {
            return (amount, true);
        } else {
            // Record claim and return 0 for now
            address intermediaryToken = poolInfo[_pid].intermediaryToken;
            recordClaim(_pid, _user, amount, intermediaryToken, _isForTransfer ? 2 : 1);
            return (0, false);
        }
    }

    /// @notice Transfer all assets from a tranche in one vault to a new vault
    /// @param _fromPid index of pool FROM
    /// @param _fromTrancheId index of tranche FROM
    /// @param _toPid index of pool TO
    function transferInvestment(uint256 _fromPid, uint256 _fromTrancheId, uint256 _toPid) public nonReentrant {
        // Get weeks committed and entered at
        uint256 weeksCommitted = trancheInfo[_fromPid][msg.sender][_fromTrancheId].durationCommittedInWeeks;
        uint256 enteredVaultAt = trancheInfo[_fromPid][msg.sender][_fromTrancheId].enteredVaultAt;
        // Withdraw
        (uint256 withdrawnUSDC, bool isSynchronous) = _withdrawalFullService(_fromPid, msg.sender, _fromTrancheId, type(uint256).max, true);
        // Check if synchrounous
        if (isSynchronous) {
            // Redeposit
            address[] memory sourceTokens;
            sourceTokens[0] = defaultStablecoin;
            _depositFullService(_toPid, msg.sender, withdrawnUSDC, sourceTokens, weeksCommitted, enteredVaultAt);
            emit TransferInvestment(msg.sender, _fromPid, _fromTrancheId, _toPid);
        } else {
            // Otherwise set redeposit information
            redepositInfo[_toPid][msg.sender].durationCommittedInWeeks = weeksCommitted;
            redepositInfo[_toPid][msg.sender].enteredVaultAt = enteredVaultAt;
        }
    }

    /// @notice Claim Intermediary token and transfer to new Vault (usually called after async settlement has occurred)
    /// @param _pid index of pool
    /// @param _user address of user
    /// @param _amount amount of token to claim
    /// @param _token address of token to claim
    function claimAndTransfer(uint256 _pid, address _user, uint256 _amount, address _token) external onlyOwner {
        // Claim 
        uint256 amountClaimed = _claimToken(_pid, _user, _amount, _token);

        // Withdraw claimed intermediary token
        address lib = poolInfo[_pid].lib;
        (bool success, bytes memory data) = lib.call(abi.encodeWithSignature("withdrawClaimedIntermedToken(address, uint256)", _user, amountClaimed));
        require(success, "call to withdrawClaimedIntermedToken() failed");
        uint valueUSDC = abi.decode(data, (uint256));
        require(valueUSDC > 0, "withdrawClaimedIntermedToken() yielded zero value");

        // Get redeposit params
        uint256 durationCommittedInWeeks = redepositInfo[_pid][_user].durationCommittedInWeeks;
        uint256 enteredVaultAt = redepositInfo[_pid][_user].enteredVaultAt;

        // Redeposit
        address[] memory sourceTokens;
        sourceTokens[0] = defaultStablecoin;
        _depositFullService(_pid, _user, valueUSDC, sourceTokens, durationCommittedInWeeks, enteredVaultAt);
    }

    /// @notice Withdraw the maximum number of Want tokens from a pool
    /// @param _pid index of pool
    function withdrawAll(uint256 _pid) public nonReentrant {
        uint256 numTranches = trancheLength(_pid, msg.sender);
        for (uint256 tid = 0; tid < numTranches; ++tid) {
            withdraw(_pid, type(uint256).max, tid);
        }
    }

    /* Claims */

    /// @notice Claims a token for async operations (e.g. Tranchess)
    /// @dev Can be used to claim any token and will clear out claim in storage once successful
    /// @param _pid index of pool to deposit into
    /// @param _amount amount of token to claim
    /// @param _token the address of the token to be claimed
    /// @return amount of token claimed
    function claimToken(uint256 _pid, uint256 _amount, address _token) public nonReentrant returns (uint256) {
        return _claimToken(_pid, msg.sender, _amount, _token);
    }

    /// @notice Private function for claiming a token for async operations (e.g. Tranchess)
    /// @dev Can be used to claim any token and will clear out claim in storage once successful
    /// @param _pid index of pool to deposit into
    /// @param _user address of user
    /// @param _amount amount of token to claim
    /// @param _token the address of the token to be claimed
    /// @return amount of token claimed
    function _claimToken(uint256 _pid, address _user, uint256 _amount, address _token) internal returns (uint256) {
        // Check that a claim exists for a user
        require(claims[_pid][_user][_token].amount > 0, "No claim recorded!");
        // Call claim via delegatecall
        address lib = poolInfo[_pid].lib;
        (bool success, bytes memory data) = lib.delegatecall(abi.encodeWithSignature("claimToken(uint256)", _amount, _token));
        require(success, "delegatecall to claimToken() failed");
        // Clear out claim 
        claims[_pid][_user][_token].amount = 0;
        // Parse and return amount data
        return abi.decode(data, (uint256));
    }

    /// @notice Record a claim for a token (usually for async operations when obtaining Want tokens, like Tranchess)
    /// @dev Will abort if a claim for a given token, pool, and user is already in progress (for safety)
    /// @param _pid index of pool to deposit into
    /// @param _user address of the user
    /// @param _amount amount of token to claim
    /// @param _token the address of the token to be claimed
    /// @param _claimReason uint256 :: 0: deposit, 1: withdrawal, 2: transfer
    function recordClaim(uint256 _pid, address _user, uint256 _amount, address _token, uint256 _claimReason) internal {
        // Record claim if one doesn't already exist
        require(claims[_pid][_user][_token].amount == 0, "A current claim is already in progress!");
        claims[_pid][_user][_token].amount = _amount;
        claims[_pid][_user][_token].reason = _claimReason;
        // Emit claim creation event
        emit ClaimCreated(_user, _pid, _amount, _token);
    }

    /* Allocations */

    /// @notice Calculate time multiplier based on duration committed
    /// @param durationInWeeks number of weeks committed into Vault
    /// @return multiplier factor, times 1e12
    function getTimeMultiplier(uint256 durationInWeeks) private view returns (uint256) {
        if (isTimeMultiplierActive) {
            return (uint256(1).add((uint256(2).div(10)).mul(durationInWeeks.sqrt()))).mul(1e12);
        } else {
            return 1e12;
        }
    }

    /// @notice The contribution of the user, meant to be used in rewards allocations
    /// @param _liquidityCommitted How many tokens staked (e.g. LP tokens)
    /// @param _timeMultiplier Time multiplier value (from getTimeMultiplier())
    /// @return The relative contribution of the user (unitless)
    function getUserContribution(uint256 _liquidityCommitted, uint256 _timeMultiplier) private pure returns (uint256) {
        return _liquidityCommitted.mul(_timeMultiplier).div(1e12);
    }
}
