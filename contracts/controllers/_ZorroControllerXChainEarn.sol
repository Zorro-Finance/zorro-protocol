// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./_ZorroControllerXChain.sol";


contract ZorroControllerXChainEarn is ZorroControllerXChain {
    /* Libraries */
    using SafeMath for uint256;

    // TODO: Make this a LayerZero call
    /// @notice Sends a request to the remote chain to unlock and burn temporarily withheld USDC. To be called after a successful withdrawal
    /// @dev Internal function, only to be called by receiveXChainRepatriationRequest()
    /// @param _account The address of the wallet (cross chain identity) to unlock funds for
    /// @param _amountUSDC The amount in USDC that should be unlocked and burned
    /// @param _chainId The Zorro destination chain ID so that the request can be routed to the appropriate chain
    /// @param _destinationContract The address of the contract on the remote chain to send the unlock request to
    function _sendXChainUnlockRequest(
        address _account,
        uint256 _amountUSDC,
        uint256 _chainId,
        bytes memory _destinationContract
    ) internal {
        // TODO: Replace entire call with a LayerZero request to the other chain. Q: How to deal with uncertain fee calculations?
        // Get endpoint contract
        address _endpointContract = endpointContracts[_chainId];

        // Prepare cross chain request
        (bool success, bytes memory data) = _endpointContract.call(
            abi.encodeWithSignature(
                "encodeUnlockRequest(address _account,uint256 _amountUSDC)",
                _account,
                _amountUSDC
            )
        );
        require(success, "Unsuccessful serialize unlock");
        bytes memory _payload = abi.decode(data, (bytes));

        // Call contract layer
        (bool success1, ) = _endpointContract.call(
            abi.encodeWithSignature(
                "sendXChainTransaction(bytes calldata _destinationContract,bytes calldata _payload)",
                _destinationContract,
                _payload
            )
        );
        // Require successful call
        require(success1, "Unsuccessful xchain unlock");
    }

    // TODO This should be called from a LayerZero receiver
    /// @notice Receives a request from home chain to unlock and burn temporarily withheld USDC.
    /// @param _account The address of the wallet (cross chain identity) to unlock funds for
    /// @param _amountUSDC The amount in USDC that should be unlocked and burned
    function receiveXChainUnlockRequest(
        address _account,
        uint256 _amountUSDC,
        bytes memory _xChainOrigin,
        bytes memory _xChainSender
    ) external onlyXChainEndpoints onlyXChainZorroControllers(_xChainSender) {
        // // Get controller
        // TokenLockController lockController = TokenLockController(
        //     lockUSDCController
        // );
        // // Unlock user funds & burn
        // lockController.unlockFunds(_account, _amountUSDC, burnAddress);
    }

    /* Earnings/Distribution */

    /// @notice Prepares and sends an earnings distribution request cross-chain (back to the home chain)
    /// @param _pid The pool ID associated with the vault which experienced earnings
    /// @param _buybackAmountUSDC The amount of USDC to buyback
    /// @param _revShareAmountUSDC The amount of USDC to share as revenue to the ZOR staking vault
    function distributeEarningsXChain(
        uint256 _pid,
        uint256 _buybackAmountUSDC,
        uint256 _revShareAmountUSDC
    ) public onlyRegisteredVault(_pid) {
        /* 
        TODO Convert this to a LayerZero call

        // Check lock to see if anything is pending for this block and pool. If so, revert
        require(
            lockedEarningsStatus[block.number][_pid] == 0,
            "Xchain earnings lock pending"
        );

        // Lock USDC on a ledger for this block and pid, with status of pending
        uint256 _amountUSDC = IERC20(defaultStablecoin).balanceOf(
            address(this)
        );
        TokenLockController(lockUSDCController).lockFunds(
            address(this),
            _amountUSDC
        );
        lockedEarningsStatus[block.number][_pid] = 1;

        // Fetch xchain endpoint for home chain
        XChainEndpoint xChainEndpoint = XChainEndpoint(
            endpointContracts[homeChainId]
        );

        // Construct payload
        bytes memory _payload = abi.encodeWithSignature(
            "receiveXChainDistributionRequest(uint256 _chainId,bytes _callbackContract,uint256 _amountUSDCBuyback,uint256 _amountUSDCRevShare,uint256 _failedAmountUSDCBuyback,uint256 _failedAmountUSDCRevShare)",
            chainId,
            abi.encode(address(this)),
            _buybackAmountUSDC,
            _revShareAmountUSDC,
            failedLockedBuybackUSDC,
            failedLockedRevShareUSDC
        );

        // Call?

        */
    }

    /// @notice Receives an authorized request from remote chains to perform earnings fee distribution events, such as: buyback + LP + burn, and revenue share
    /// @param _chainId The ID of the chain that this request originated from
    /// @param _callbackContract Address of destination contract in bytes for the callback
    /// @param _amountUSDCBuyback The amount in USDC that should be minted for LP + burn
    /// @param _amountUSDCRevShare The amount in USDC that should be minted for revenue sharing with ZOR stakers
    /// @param _failedAmountUSDCBuyback The previously failed buyback amount that is being retried
    /// @param _failedAmountUSDCRevShare The previously failed revshare amount that is being retried
    /// @param _xChainOrigin Address of the original sender (in bytes) on the remote chain (equiv to tx.origin). Injected by endpoint contract after verifying proof
    function receiveXChainDistributionRequest(
        uint256 _chainId,
        bytes calldata _callbackContract,
        uint256 _amountUSDCBuyback,
        uint256 _amountUSDCRevShare,
        uint256 _failedAmountUSDCBuyback,
        uint256 _failedAmountUSDCRevShare,
        bytes memory _xChainOrigin,
        bytes memory _xChainSender
    ) external onlyXChainEndpoints onlyXChainZorroControllers(_xChainSender) {
        // Make Chainlink request to get ZOR price
        // TODO: Don't do a Chainlink direct request. Use price feeds instead (i.e. no need for a callback func so merge its contents here)
        // Chainlink.Request memory req = buildChainlinkRequest(
        //     zorroControllerOraclePriceJobId,
        //     address(this),
        //     this.buybackAndRevShareCallback.selector
        // );
        // req.addBytes("chainId", abi.encodePacked(_chainId));
        // req.addBytes("callbackContract", abi.encodePacked(_callbackContract));
        // req.addBytes("amountUSDCBuyback", abi.encodePacked(_amountUSDCBuyback));
        // req.addBytes(
        //     "amountUSDCRevShare",
        //     abi.encodePacked(_amountUSDCRevShare)
        // );
        // req.addBytes(
        //     "failedAmountUSDCBuyback",
        //     abi.encodePacked(_failedAmountUSDCBuyback)
        // );
        // req.addBytes(
        //     "failedAmountUSDCRevShare",
        //     abi.encodePacked(_failedAmountUSDCRevShare)
        // );
        // sendChainlinkRequestTo(
        //     zorroControllerOracle,
        //     req,
        //     zorroControllerOracleFee
        // );
    }

    /// @notice Receives cross chain request for burning any temporarily locked funds for earnings
    /// @param _amountUSDCBuyback The amount in USDC that was bought back
    /// @param _amountUSDCRevShare The amount in USDC that was rev-shared
    /// @param _failedAmountUSDCBuyback The previously failed buyback amount that was successfully retried
    /// @param _failedAmountUSDCRevShare The previously failed revshare amount that was successfully retried
    /// @param _xChainOrigin Address of the original sender (in bytes) on the remote chain (equiv to tx.origin). Injected by endpoint contract after verifying proof
    function receiveBurnLockedEarningsRequest(
        uint256 _amountUSDCBuyback,
        uint256 _amountUSDCRevShare,
        uint256 _failedAmountUSDCBuyback,
        uint256 _failedAmountUSDCRevShare,
        bytes memory _xChainOrigin,
        bytes memory _xChainSender
    ) external onlyXChainEndpoints onlyXChainZorroControllers(_xChainSender) {
        // TODO: We can probably get rid of this entire function
        // Calculate total amount to unlock and burn
        uint256 _totalBurnableUSDC = _amountUSDCBuyback
            .add(_amountUSDCRevShare)
            .add(_failedAmountUSDCBuyback)
            .add(_failedAmountUSDCRevShare);
        // Unlock + burn
        // TokenLockController(lockUSDCController).unlockFunds(
        //     address(this),
        //     _totalBurnableUSDC,
        //     burnAddress
        // );
        // Decrement any failed amounts
        failedLockedBuybackUSDC = failedLockedBuybackUSDC.sub(
            _failedAmountUSDCBuyback
        );
        failedLockedRevShareUSDC = failedLockedRevShareUSDC.sub(
            _failedAmountUSDCRevShare
        );
    }

    // TODO: Ledger system in case this fails?
    /// @notice Receives an authorized request from remote chains to perform earnings fee distribution events, such as: buyback + LP + burn, and revenue share
    /// @dev Can only be called by the Chainlink Oracle
    /// @param _chainId The ID of the chain that this request originated from
    /// @param _callbackContract Address of destination contract in bytes for the callback
    /// @param _amountUSDCBuyback The amount in USDC that should be minted for LP + burn
    /// @param _amountUSDCRevShare The amount in USDC that should be minted for revenue sharing with ZOR stakers
    /// @param _failedAmountUSDCBuyback The previously failed buyback amount that is being retried
    /// @param _failedAmountUSDCRevShare The previously failed revshare amount that is being retried
    /// @param _ZORROExchangeRate ZOR per USD, times 1e12
    function buybackAndRevShareCallback(
        uint256 _chainId,
        bytes calldata _callbackContract,
        uint256 _amountUSDCBuyback,
        uint256 _amountUSDCRevShare,
        uint256 _failedAmountUSDCBuyback,
        uint256 _failedAmountUSDCRevShare,
        uint256 _ZORROExchangeRate
    ) external onlyAllowZorroControllerOracle {
        // Total USDC to perform operations
        // TODO: How do failed amounts come into play here? Will we even have failures now?
        uint256 _amountUSDC = _amountUSDCBuyback
            .add(_amountUSDCRevShare)
            .add(_failedAmountUSDCBuyback)
            .add(_failedAmountUSDCRevShare);

        // Determine new USDC balances
        uint256 _balUSDC = IERC20(defaultStablecoin).balanceOf(address(this));

        /* Buyback */
        uint256 _buybackAmount = _balUSDC
            .mul(_amountUSDCBuyback.add(_failedAmountUSDCBuyback))
            .div(_amountUSDC);
        _buybackOnChain(_buybackAmount, _ZORROExchangeRate);

        /* Rev share */
        uint256 _revShareAmount = _balUSDC.sub(_buybackAmount);
        _revShareOnChain(_revShareAmount, _ZORROExchangeRate);

        // Send cross chain burn request back to the remote chain
        /* 
        TODO: Convert to LayerZero call

        XChainEndpoint endpointContract = XChainEndpoint(
            endpointContracts[_chainId]
        );
        bytes memory _payload = abi.encodeWithSignature(
            "receiveBurnLockedEarningsRequest(uint256 _amountUSDCBuyback,uint256 _amountUSDCRevShare,uint256 _failedAmountUSDCBuyback,uint256 _failedAmountUSDCRevShare)",
            _amountUSDCBuyback,
            _amountUSDCRevShare,
            _failedAmountUSDCBuyback,
            _failedAmountUSDCRevShare
        );
        endpointContract.sendXChainTransaction(_callbackContract, _payload, "");
        */
    }
}