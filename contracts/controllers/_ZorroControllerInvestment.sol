// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./_ZorroControllerBase.sol";

import "../interfaces/IVault.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "../libraries/Math.sol";

import "../tokens/ZorroToken.sol";

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
        _deposit(
            _pid,
            msg.sender,
            "",
            _wantAmt,
            _weeksCommitted,
            block.timestamp
        );
    }

    /// @notice Internal function for depositing Want tokens into Vault
    /// @dev Because the vault entry date can be backdated, this is a dangerous method and should only be called indirectly through other functions
    /// @param _pid index of pool
    /// @param _account address of on-chain user (required for onchain, optional for cross-chain)
    /// @param _foreignAccount address of origin chain user (for cross chain transactions it's required)
    /// @param _wantAmt how much Want token to deposit (must already be sent to vault contract)
    /// @param _weeksCommitted how many weeks the user is committing to on this vault
    /// @param _enteredVaultAt Date to backdate vault entry to
    /// @return _mintedZORRewards Amount of ZOR rewards minted
    function _deposit(
        uint256 _pid,
        address _account,
        bytes memory _foreignAccount,
        uint256 _wantAmt,
        uint256 _weeksCommitted,
        uint256 _enteredVaultAt
    ) internal returns (uint256 _mintedZORRewards) {
        // Get pool info
        PoolInfo storage pool = poolInfo[_pid];

        // Preflight checks
        require(_wantAmt > 0, "_wantAmt must be > 0!");

        // Update the pool before anything to ensure rewards have been updated and transferred
        _mintedZORRewards = updatePool(_pid);

        // Associate foreign and local account address, as applicable

        // Get local chain account, as applicable
        address _localAccount = _account;
        if (_account == address(0)) {
            // Foreign account MUST be provided
            require(
                _foreignAccount.length > 0,
                "Neither foreign acct nor local acct provided"
            );
            // If no local account provided, truncate foreign chain address to 20-bytes
            _localAccount = address(bytes20(_foreignAccount));
        }

        // Perform the actual deposit function on the underlying Vault contract and get the number of shares to add
        uint256 sharesAdded = IVault(poolInfo[_pid].vault).depositWantToken(
            _localAccount,
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

        // Create tranche info
        TrancheInfo memory _trancheInfo = TrancheInfo({
            contribution: contributionAdded,
            timeMultiplier: timeMultiplier,
            rewardDebt: pool.accZORRORewards.mul(newTrancheShare).div(1e12),
            durationCommittedInWeeks: _weeksCommitted,
            enteredVaultAt: _enteredVaultAt,
            exitedVaultStartingAt: 0
        });
        _updateTrancheInfoForDeposit(
            _pid,
            _localAccount,
            _foreignAccount,
            _trancheInfo
        );

        // Emit deposit event
        emit Deposit(_localAccount, _pid, _wantAmt);
    }

    /// @notice Internal function for updating tranche ledger upon deposit
    /// @param _pid Index of pool
    /// @param _localAccount On-chain address
    /// @param _foreignAccount Cross-chain address, if applicable
    /// @param _trancheInfo TrancheInfo object
    function _updateTrancheInfoForDeposit(
        uint256 _pid,
        address _localAccount,
        bytes memory _foreignAccount,
        TrancheInfo memory _trancheInfo
    ) internal {
        // Push a new tranche for this on-chain user
        trancheInfo[_pid][_localAccount].push(_trancheInfo);

        // If foreign account provided, write the tranche info to the foreign account ledger as well
        if (_foreignAccount.length > 0) {
            foreignTrancheInfo[_pid][_foreignAccount].push(
                ForeignTrancheInfo({
                    trancheIndex: trancheLength(_pid, _localAccount).sub(1),
                    localAccount: _localAccount
                })
            );
        }
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
        _deposit(
            _pid,
            _account,
            _foreignAccount,
            _wantAmt,
            _weeksCommitted,
            _vaultEnteredAt
        );
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
        (uint256 _wantAmt, ) = _withdraw(
            _pid,
            msg.sender,
            "",
            _trancheId,
            _harvestOnly
        );

        // Transfer to user and return Want amount
        IERC20(poolInfo[_pid].want).safeTransfer(msg.sender, _wantAmt);

        return _wantAmt;
    }

    /// @notice Internal function for withdrawing Want tokens from underlying Vault.
    /// @dev Can only specify one of _localAccount, _foreignAccount
    /// @param _pid index of pool
    /// @param _localAccount Address of the on-chain account that the investment was made with
    /// @param _foreignAccount Address of the foreign chain account that this inviestment was made with
    /// @param _trancheId index of tranche
    /// @param _harvestOnly If true, will only harvest Zorro tokens but not do a withdrawal
    /// @return tuple Amount of Want token withdrawn, Amount of ZOR rewards minted
    function _withdraw(
        uint256 _pid,
        address _localAccount,
        bytes memory _foreignAccount,
        uint256 _trancheId,
        bool _harvestOnly
    ) internal returns (uint256, uint256) {
        // Can only specify one account (on-chain/foreign, but not both)
        require(
            (_localAccount == address(0) && _foreignAccount.length > 0) ||
                (_localAccount != address(0) && _foreignAccount.length == 0),
            "Only one account type allowed"
        );
        // Determine account type and associated values
        TrancheInfo memory _tranche = _getTranche(
            _pid,
            _trancheId,
            _foreignAccount,
            _localAccount
        );

        // Get pool and current tranche info
        PoolInfo storage _pool = poolInfo[_pid];

        // Require non-zero tranche contribution
        require(_tranche.contribution > 0, "tranche.contribution is 0");
        // Require non-zero overall tranche contribution
        require(
            _pool.totalTrancheContributions > 0,
            "totalTrancheContributions is 0"
        );

        // Update the pool before anything to ensure rewards have been updated and transferred
        uint256 _mintedZORRewards = updatePool(_pid);

        // Withdraw pending ZORRO rewards (a.k.a. "Harvest")
        uint256 _trancheShare = _tranche.contribution.mul(1e12).div(
            _pool.totalTrancheContributions
        );
        uint256 _pendingRewards = _trancheShare
            .mul(_pool.accZORRORewards)
            .div(1e12)
            .sub(_tranche.rewardDebt);
        if (_pendingRewards > 0) {
            // If pending rewards payable, pay them out
            _payPendingRewards(_pid, _tranche, _pendingRewards, _localAccount);
        }

        // Perform the actual withdrawal function on the underlying Vault contract and get the number of shares to remove
        // TODO: Issue: this withdraws everything in the vault for the account, and not everything in the tranche
        IVault(poolInfo[_pid].vault).withdrawWantToken(
            _localAccount,
            _foreignAccount,
            _harvestOnly
        );

        // Update shares safely
        _pool.totalTrancheContributions = _pool.totalTrancheContributions.sub(
            _tranche.contribution
        );

        // Calculate Want token balance
        uint256 _wantBal = IERC20(_pool.want).balanceOf(address(this));

        // All withdrawals are full withdrawals so delete the tranche
        _deleteTranche(_pid, _trancheId, _localAccount, _foreignAccount);

        // Emit withdrawal event and return want balance
        // TODO: Make this for foreign accounts too?
        emit Withdraw(_localAccount, _pid, _trancheId, _wantBal);

        return (_wantBal, _mintedZORRewards);
    }

    /// @notice Get tranche based on tranche ID and account information 
    /// @dev Takes into account potential cross chain identities
    /// @param _pid Pool ID
    /// @param _trancheId Tranche ID
    /// @param _foreignAccount Identity of the foreign account that the tranche might be associated with 
    /// @param _localAccount Identity of the account on the local chain that the tranche might be associated with
    /// @return _tranche TrancheInfo object for the tranche found
    function _getTranche(
        uint256 _pid,
        uint256 _trancheId,
        bytes memory _foreignAccount,
        address _localAccount
    ) internal view returns (TrancheInfo memory _tranche) {
        if (_localAccount == address(0)) {
            // On-chain withdrawal
            _tranche = trancheInfo[_pid][_localAccount][_trancheId];
        } else {
            // Cross-chain withdrawal
            for (
                uint16 i = 0;
                i < foreignTrancheInfo[_pid][_foreignAccount].length;
                ++i
            ) {
                ForeignTrancheInfo memory _fti = foreignTrancheInfo[_pid][
                    _foreignAccount
                ][i];
                if (_fti.trancheIndex == _trancheId) {
                    _tranche = trancheInfo[_pid][_fti.localAccount][_trancheId];
                    break;
                }
            }
        }
    }

    /// @notice Pays out pending rewards
    /// @param _pid Pool ID
    /// @param _tranche TrancheInfo object 
    /// @param _pendingRewards Qty of ZOR tokens as pending rewards
    /// @param _localAccount Local account associated with tranche
    function _payPendingRewards(
        uint256 _pid,
        TrancheInfo memory _tranche,
        uint256 _pendingRewards,
        address _localAccount
    ) internal {
        // Only process rewards > 0
        if (_pendingRewards <= 0) {
            return;
        }
        // Check if this is an early withdrawal
        // If so, slash the accumulated rewards proportionally to the % time remaining before maturity of the time commitment
        // If not, distribute rewards as normal
        uint256 timeRemainingInCommitment = _tranche
            .enteredVaultAt
            .add(_tranche.durationCommittedInWeeks.mul(1 weeks))
            .sub(block.timestamp);
        uint256 rewardsDue = 0;
        uint256 slashedRewards = 0;
        if (timeRemainingInCommitment > 0) {
            slashedRewards = _pendingRewards.mul(timeRemainingInCommitment).div(
                    _tranche.durationCommittedInWeeks.mul(1 weeks)
                );
            rewardsDue = _pendingRewards.sub(slashedRewards);
        } else {
            rewardsDue = _pendingRewards;
        }
        // Transfer ZORRO rewards to user, net of any applicable slashing
        // TODO: How does this work for cross chain? (The ZOR transfer)
        _safeZORROTransfer(_localAccount, rewardsDue);
        // Transfer any slashed rewards to single Zorro staking vault, if applicable
        if (slashedRewards > 0) {
            address singleStakingVaultZORRO = poolInfo[_pid].vault;
            // Transfer slashed rewards to vault to reward ZORRO stakers
            _safeZORROTransfer(singleStakingVaultZORRO, slashedRewards);
        }
    }

    // TODO: Should we consider not deleting tranches? Gas!!!
    /// @notice Delete a tranche from a user's tranches
    /// @param _pid index of pool to deposit into
    /// @param _trancheId index of tranche
    /// @param _account On-chain wallet to remove tranche from
    /// @param _foreignAccount Cross-chain wallet to remove tranche from
    function _deleteTranche(
        uint256 _pid,
        uint256 _trancheId,
        address _account,
        bytes memory _foreignAccount
    ) internal {
        // Determine the number of tranches
        uint256 _trancheLength = trancheInfo[_pid][_account].length;
        // Shift tranche to current index
        trancheInfo[_pid][_account][_trancheId] = trancheInfo[_pid][_account][
            _trancheLength - 1
        ];
        // Pop last item off of tranche array
        trancheInfo[_pid][_account].pop();

        if (_foreignAccount.length > 0) {
            // Determine the number of foreign tranches
            uint256 _foreignTrancheLength = foreignTrancheInfo[_pid][
                _foreignAccount
            ].length;
            // Iterate through foreign tranche array
            for (uint8 i = 0; i < _foreignTrancheLength; ++i) {
                if (
                    foreignTrancheInfo[_pid][_foreignAccount][i].trancheIndex ==
                    _trancheId
                ) {
                    // Shift foreign tranche to current index
                    foreignTrancheInfo[_pid][_foreignAccount][
                        i
                    ] = foreignTrancheInfo[_pid][_foreignAccount][
                        _foreignTrancheLength - 1
                    ];
                    // Pop last item off of foreign tranche array
                    foreignTrancheInfo[_pid][_foreignAccount].pop();
                }
            }
        }
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
        (uint256 _amountUSDC, ) = _withdrawalFullService(
            msg.sender,
            "",
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
    /// @param _account address of wallet on-chain
    /// @param _foreignAccount address of wallet cross-chain (that originally made this deposit)
    /// @param _pid index of pool to deposit into
    /// @param _trancheId index of tranche
    /// @param _harvestOnly If true, will only harvest Zorro tokens but not do a withdrawal
    /// @param _maxMarketMovement factor to account for max market movement/slippage. The definition varies by Vault, so consult the associated Vault contract for info
    /// @return tuple Amount (in USDC) returned, minted ZOR rewards
    function _withdrawalFullService(
        address _account,
        bytes memory _foreignAccount,
        uint256 _pid,
        uint256 _trancheId,
        bool _harvestOnly,
        uint256 _maxMarketMovement
    ) internal returns (uint256, uint256) {
        // Update tranche status
        trancheInfo[_pid][_account][_trancheId].exitedVaultStartingAt = block
            .timestamp;
        // Get Vault contract
        address _vaultAddr = poolInfo[_pid].vault;
        IVault vault = IVault(_vaultAddr);

        // Call core withdrawal function (returns actual amount withdrawn)
        (uint256 _wantAmtWithdrawn, uint256 _mintedZORRewards) = _withdraw(
            _pid,
            _account,
            _foreignAccount,
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

        return (amount, _mintedZORRewards);
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
        (uint256 withdrawnUSDC, ) = _withdrawalFullService(
            msg.sender,
            "",
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
            "",
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
