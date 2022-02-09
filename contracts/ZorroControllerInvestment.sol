// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ZorroControllerBase.sol";

import "./interfaces/IVault.sol";

import "./libraries/SafeERC20.sol";

import "./libraries/SafeMath.sol";

import "./libraries/Math.sol";

import "./TokenLockController.sol";

import "./XChainEndpoint.sol";

import "./ZorroTokens.sol";

import "./interfaces/IAMMRouter02.sol";

import "./libraries/SafeSwap.sol";


contract ZorroControllerInvestment is ZorroControllerBase {
    /*
    Libraries
    */
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using CustomMath for uint256;
    using SafeSwap for IAMMRouter02;

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
            _user,
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

        // TODO: Need to approve the Vault contract first?

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
                .withdrawWantToken(_user, _wantAmt);
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
    /// @param _account address of user
    /// @param _pid index of pool to deposit into
    /// @param _trancheId index of tranche
    /// @param _wantAmt value in Want tokens to withdraw (0 will result in harvest and uint256(-1) will result in max value)
    /// @param _maxMarketMovement factor to account for max market movement/slippage. The definition varies by Vault, so consult the associated Vault contract for info
    /// @return Amount (in USDC) returned
    function _withdrawalFullService(
        address _account,
        uint256 _pid,
        uint256 _trancheId,
        uint256 _wantAmt,
        uint256 _maxMarketMovement
    ) internal returns (uint256) {
        // Update tranche status
        trancheInfo[_pid][_account][_trancheId].exitedVaultStartingAt = block.timestamp;

        // Get Vault contract
        IVault vault = IVault(poolInfo[_pid].vault);

        // Call core withdrawal function (returns actual amount withdrawn)
        uint256 wantAmtWithdrawn = _withdraw(_pid, _user, _trancheId, _wantAmt);

        uint256 amount = vault.exchangeWantTokenForUSD(
            _user,
            wantAmtWithdrawn,
            _maxMarketMovement
        );

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

    /* 
    Cross Chain functions 
    */

    /* Deposits */

    /// @notice Prepares and sends a cross chain deposit request. Takes care of necessary financial ops (transfer/locking USDC)
    /// @param _chainId The Zorro destination chain ID so that the request can be routed to the appropriate chain
    /// @param _destinationContract The address of the smart contract on the destination chain
    /// @param _payload The input payload for the destination function, encoded in bytes (EVM ABI or equivalent depending on chain)
    function sendXChainDepositRequest(
        uint256 _chainId,
        bytes calldata _destinationContract,
        bytes calldata _payload
    ) external nonReentrant {
        // Get endpoint contract that interfaces with the remote chain
        address _endpointContract = XChainEndpoint(endpointContracts[_chainId]);
        // Extract amount of USDC to transfer into this contract from the payload
        uint256 _amountUSDC = _endpointContract.extractValueFromPayload(_payload);
        // Verify that encoded user identity is in fact msg.sender.
        address _userIdentity = _endpointContract.extractIdentityFromPayload(_payload);
        require(_userIdentity == msg.sender, "Payload sender doesnt match msg.sender");
        // Allow this contract to spend USDC
        IERC20(defaultStablecoin).safeIncreaseAllowance(address(this), _amountUSDC);
        // Transfer USDC into this contract
        IERC20(defaultStablecoin).safeTransferFrom(msg.sender, address(this), _amountUSDC);
        // Lock USDC on the ledger
        TokenLockController(lockUSDCController).lockFunds(msg.sender, _amountUSDC);
        // Call contract layer
        (bool successful, ) = _endpointContract.call(
            abi.encodeWithSignature(
                "sendXChainTransaction(bytes calldata _destinationContract,bytes calldata _payload)",
                _destinationContract,
                _payload
            )
        );
        // Require successful call
        require(successful, "Deposit call unsuccessful");
    }

    /// @notice Receives a cross chain deposit request from the contract layer of the XchainEndpoint contract
    /// @dev For params, see _depositFullService() function declaration above
    function receiveXChainDepositRequest(
        address _account,
        uint256 _valueUSDC,
        uint256 _pid,
        uint256 _weeksCommitted,
        uint256 _vaultEnteredAt,
        uint256 _maxMarketMovement
    ) internal {
        // Mint corresponding amount of zUSDC
        ZUSDC(syntheticStablecoin).mint(address(this), _valueUSDC);
        // Swap zUSDC for USDC
        address[] memory _path = [syntheticStablecoin, defaultStablecoin];
        IAMMRouter02(uniRouterAddress).safeSwap(
            _valueUSDC,
            _maxMarketMovement,
            _path,
            address(this),
            block.timestamp.add(600)
        );
        // Call deposit function
        _depositFullService(_pid, _account, _valueUSDC, _weeksCommitted, _vaultEnteredAt, _maxMarketMovement);
    }

    /* Withdrawals */
    /// @notice Prepares and sends a cross chain withdrwal request.
    /// @param _chainId The Zorro destination chain ID so that the request can be routed to the appropriate chain
    /// @param _destinationContract The address of the smart contract on the destination chain
    /// @param _payload The input payload for the destination function, encoded in bytes (EVM ABI or equivalent depending on chain)
    function sendXChainWithdrawalRequest(
        uint256 _chainId,
        bytes calldata _destinationContract,
        bytes calldata _payload
    ) external nonReentrant {
        // Get endpoint contract that interfaces with the remote chain
        address _endpointContract = XChainEndpoint(endpointContracts[_chainId]);
        // Verify that the encoded user identity is in fact msg.sender
        address _userIdentity = _endpointContract.extractIdentityFromPayload(_payload);
        require(_userIdentity == msg.sender, "Payload sender doesnt match msg.sender");
        // Call contract layer
        (bool successful, ) = _endpointContract.call(
            abi.encodeWithSignature(
                "sendXChainTransaction(bytes calldata _destinationContract,bytes calldata _payload)",
                _destinationContract,
                _payload
            )
        );
        // Require successful call
        require(successful, "Withdrawal call unsuccessful");
    }

    /// @notice Receives a cross chain withdrawal request from the contract layer of the XchainEndpoint contract
    /// @dev For params, see _withdrawalFullService() function declaration above. Executes idempotently.
    function receiveXChainWithdrawalRequest(
        address _account,
        uint256 _pid,
        uint256 _trancheId,
        uint256 _wantAmt, // TODO: Remove - not required as we're doing 100% withdrawals only
        uint256 _maxMarketMovement
    ) internal {
        // First check if withdrawal was already attempted (e.g. there was a cross chain failure). If so, redrive this function
        // without the withdrawal and lock steps
        TrancheInfo tranche = trancheInfo[_pid][_account][_trancheId];
        uint256 _amountUSDC = 0;
        if (tranche.exitedVaultStartingAt == 0) {
            // Call withdrawal function
            _amountUSDC = _withdrawalFullService(_account, _pid, _trancheId, _wantAmt, _maxMarketMovement);
            // Lock withdrawn USDC
            TokenLockController(lockUSDCController).lockFunds(_account, _amountUSDC);   
        } else {
            // Lookup amount locked
            _amountUSDC = TokenLockController(lockUSDCController).lockedFunds[_account];
        }

        // Only proceed if there is something to withdraw
        require(_amountUSDC > 0, "Nothing to withdraw");

        // Prepare repatriation transaction
        bytes _destinationContract = abi.encodePacked(homeChainZorroController);
        bytes _payload = abi.encodeWithSignature(
            "receiveXChainRepatriationRequest(address _account,uint256 _withdrawnUSDC,uint256 _pid,uint256 _trancheId,uint256 _maxMarketMovement,address _callbackContract)", 
            _account, _amountUSDC, _pid, _trancheId, _maxMarketMovement, address(this)
        );

        // Call contract layer to dispatch cross chain transaction
        (bool successful, ) = _endpointContract.call(
            abi.encodeWithSignature(
                "sendXChainTransaction(bytes calldata _destinationContract,bytes calldata _payload)",
                _destinationContract,
                _payload
            )
        );
        // Require successful call
        require(successful, "Repatriation call unsuccessful");
    }

    // TODO: VERY IMPORTANT: Once code is done, check all ABI encodings to make sure method signature string matches the order of all 
    // arguments. We changed around the order of many args. 

    /// @notice Receives a repatriation request from another chain and takes care of all financial operations (unlock/mint/burn) to pay the user their withdrawn funds from another chain
    /// @param _account The user on this chain who initiated the withdrawal request
    /// @param _withdrawnUSDC The amount of USDC withdrawn on the remote chain
    /// @param _originalDepositUSDC The amount originally deposited into this tranche // TODO net- or gross- of fees? IMPORTANT
    /// @param _pid The pool ID on the remote chain that the user withdrew from
    /// @param _trancheId The ID of the tranche on the remote chain, that was originally used to deposit
    /// @param _maxMarketMovement factor to account for max market movement/slippage. // TODO - need definition
    /// @param _callbackContract The remote contract that called this function.
    function receiveXChainRepatriationRequest(
        address _account,
        uint256 _withdrawnUSDC,
        uint256 _originalDepositUSDC,
        uint256 _pid,
        uint256 _trancheId,
        uint256 _maxMarketMovement,
        address _callbackContract
    ) external nonReentrant {
        // TODO: Complete function, docstrings
        /*
        TODO
        - Need original deposit amount, which is stored on opposite chain. OR we maintain a xchain mapping on this chain by tranche

        */
        // Initialize finance variables
        uint256 _profit = 0;
        uint256 _unlockableAmountUSDC = 0;
        uint256 _mintableAmountZUSDC = 0;
        uint256 _burnableAmountUSDC = 0;

        // Update amounts depending on whether investment was profitable
        if (_withdrawnUSDC >= _originalDepositUSDC) {
            // Profitable
            // Calculate profit amount if a profit was made
            _profit = _withdrawnUSDC.sub(_originalDepositUSDC);
            // Set the unlockable amount to the original deposit amount (principal) only
            _unlockableAmountUSDC = _originalDepositUSDC;
            // Set the mint amount to the proceeds.
            _mintableAmountZUSDC = _profit;
        } else {
            // Loss
            // Set the unlockable amount to the withdrawal amount
            _unlockableAmountUSDC = _withdrawnUSDC;
            // The burn amount to the loss amount
            _burnableAmountUSDC = _originalDepositUSDC.sub(_withdrawnUSDC);
        }

        // Unlock USDC principal
        TokenLockController(lockUSDCController).unlockFunds(_account, _unlockableAmountUSDC, address(this));
        // Mint zUSDC (if applicable)
        if (_mintableAmountZUSDC > 0) {
            ZUSDC(syntheticStablecoin).mint(address(this), _mintableAmountZUSDC);
            // Swap zUSDC for USDC
            address[] memory _path = [syntheticStablecoin, defaultStablecoin];
            IAMMRouter02(uniRouterAddress).safeSwap(
                _mintableAmountZUSDC,
                _maxMarketMovement,
                _path,
                address(this),
                block.timestamp.add(600)
            );
        }
        // Burn unused USDC (if applicable)
        if (_burnableAmountUSDC > 0) {
            IERC20(defaultStablecoin).safeTransfer(burnAddress, _burnableAmountUSDC);
        }
        // Transfer total USDC to wallet
        uint256 _balanceUSDC = IERC20(defaultStablecoin).balanceOf(address(this));
        IERC20(defaultStablecoin).transfer(_account, _balanceUSDC);
        // Send cross-chain burn request for the USDC that has been temporarily locked on the opposite chain
        // TODO - how to prepare request such that it's generalized for any chain? E.g. abi encoding
        sendXChainUnlockRequest();
    }

    // TODO: Do we need to account for "dust" amounts? Too small amounts causing potential failures? Rounding errors? See Autofarm code

    /* Cross-chain unlocks */

    /// @notice Sends a request to the remote chain to unlock and burn temporarily withheld USDC. To be called after a successful withdrawal
    /// @dev Internal function, only to be called by receiveXChainRepatriationRequest()
    /// @param _chainId The Zorro destination chain ID so that the request can be routed to the appropriate chain
    /// @param _account The address of the wallet (cross chain identity) to unlock funds for
    /// @param _amountUSDC The amount in USDC that should be unlocked and burned
    /// @param _destinationContract The address of the contract on the remote chain to send the unlock request to
    function sendXChainUnlockRequest(
        uint256 _chainId,
        address _account,
        uint256 _amountUSDC,
        address _destinationContract
    ) internal {
        // Get endpoint contract
        address _endpointContract = endpointContracts[_chainId];

        // Prepare cross chain request
        (bool success, bytes memory data) = _endpointContract.call(
            abi.encodeWithSignature(
                "encodeUnlockRequest(address _account,uint256 _amountUSDC)", 
                _account, _amountUSDC
            )
        );
        require(success, "Unsuccessful serialize unlock");
        bytes _payload = abi.decode(data, (bytes));

        // Call contract layer
        (bool success1,) = _endpointContract.call(
            abi.encodeWithSignature(
                "sendXChainTransaction(bytes calldata _destinationContract,bytes calldata _payload)",
                _destinationContract,
                _payload
            )
        );
        // Require successful call
        require(success1, "Unsuccessful xchain unlock");
    }

    // TODO - consider having this emit an event
    /// @notice Receives a request from home chain (BSC) to unlock and burn temporarily withheld USDC.
    /// @param _account The address of the wallet (cross chain identity) to unlock funds for
    /// @param _amountUSDC The amount in USDC that should be unlocked and burned
    function receiveXChainUnlockRequest(
        address _account,
        uint256 _amountUSDC
    ) public {
        // Get controller
        TokenLockController lockController = TokenLockController(lockUSDCController);
        // Unlock user funds
        lockController.unlockFunds(_account, _amountUSDC, address(0));
        // Burn
        lockController.burnFunds(_amountUSDC);
    }

    /* Safety */
    // TODO: Get function visibilities, modifiers correct. Note that this is a different oracle. Consider emitting events too

    /// @notice Called by oracle when the deposit logic on the remote chain failed, and the deposit logic on this chain thus needs to be reverted
    /// @dev Unlocks USDC and returns it to depositor
    /// @param _account The address of the depositor
    /// @param _amountUSDC The amount originally deposited (TODO: inclusive of fees?)
    function revertXChainDeposit(address _account, uint256 _amountUSDC) public {
        // Unlock & return to wallet
        TokenLockController(lockUSDCController).unlockFunds(_account, _amountUSDC, _account);
    }

    // TODO - decide on what we're doing for emergencies
    function emergencyWithdrawal() public {

    }

    // TODO - All the functions for updating pool rewards cross chain

    /*
    - Request ZOR burn cross chain
    - Repatriation request
    - Reversion request
    - Cross chain identity (1- include in proof, 2- verify it's the same as in payload)
    - How to ensure usdc transferFrom is the same as that specified in the payload 
    - 100% withdrawal only
    - Lock/unlock (be aware of the principal)
    - Burn when done locking (cross chain call)
    - Get all function visibilities right
    - Get all function modifiers right (onlyOwner etc.)
    - Have some sort of global lock so that people can't game the system to replay events and cause race conditions, etc.
    - Figure out how to abstract the logic out for ABI decoding and verification of payload params (identity, amount, etc.), since each chain is different!
    */
}
