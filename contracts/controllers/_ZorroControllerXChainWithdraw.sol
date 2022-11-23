// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./_ZorroControllerXChainBase.sol";

import "../interfaces/IZorroController.sol";

import "../interfaces/IZorroControllerXChain.sol";

import "../interfaces/IZorro.sol";

import "./actions/ZorroControllerXChainActions.sol";

contract ZorroControllerXChainWithdraw is
    IZorroControllerXChainWithdraw,
    ZorroControllerXChainBase
{
    /* Sending */

    /* Sending::withdrawals */

    /// @notice Prepares and sends a cross chain withdrwal request.
    /// @dev Requires value to be submitted to pay for cross chain transaction. Use checkXChainWithdrawalFee() to estimate fees
    /// @param _destZorroChainId The Zorro chain ID of the remote chain to withdraw from
    /// @param _pid The pool ID on the remote chain
    /// @param _trancheId The ID of the tranche for the given user and pool
    /// @param _maxMarketMovement Acceptable degree of slippage on any transaction (e.g. 950 = 5%, 990 = 1% etc.)
    /// @param _gasForDestinationLZReceive How much additional gas to provide at destination contract
    function sendXChainWithdrawalRequest(
        uint256 _destZorroChainId,
        uint256 _pid,
        uint256 _trancheId,
        uint256 _maxMarketMovement,
        uint256 _gasForDestinationLZReceive
    ) external payable nonReentrant {
        // Prep payload
        bytes memory _payload = ZorroControllerXChainActions(controllerActions)
            .encodeXChainWithdrawalPayload(
                chainId,
                abi.encodePacked(msg.sender),
                _pid,
                _trancheId,
                _maxMarketMovement
            );

        // Destination info
        bytes memory _dstContract = controllerContractsMap[_destZorroChainId];

        // Send LayerZero request
        _callLZSend(
            LZMessagePayload({
                zorroChainId: _destZorroChainId,
                destinationContract: _dstContract,
                payload: _payload,
                refundAddress: payable(msg.sender),
                _zroPaymentAddress: address(0),
                adapterParams: ZorroControllerXChainActions(controllerActions).getLZAdapterParamsForWithdraw(
                    _gasForDestinationLZReceive
                )
            })
        );
    }

    /* Sending::repatriation */

    /// @notice Prepares and sends cross chain repatriation request via Stargate
    /// @param _originChainId Zorro chain ID of origin chain that repatriation shall go to
    /// @param _pid Pool ID on current chain that withdrawal came from
    /// @param _trancheId Tranche ID on current chain that withdrawal came from
    /// @param _originRecipient Recipient on home chain that repatriate funds shall go to
    /// @param _amountUSD Amount withdrawn, to be repatriated
    /// @param _rewardsDue ZOR rewards due to the recipient
    /// @param _maxMarketMovementAllowed Acceptable slippage (950 = 5%, 990 = 1%, etc.)
    function _sendXChainRepatriationRequest(
        uint256 _originChainId,
        uint256 _pid,
        uint256 _trancheId,
        bytes memory _originRecipient,
        uint256 _amountUSD,
        uint256 _rewardsDue,
        uint256 _maxMarketMovementAllowed
    ) internal {
        // Prep payload
        bytes memory _payload = ZorroControllerXChainActions(controllerActions)
            .encodeXChainRepatriationPayload(
                _originChainId,
                _pid,
                _trancheId,
                _originRecipient,
                _rewardsDue
            );
        // Destination info
        bytes memory _dstContract = controllerContractsMap[_originChainId];

        // Send Stargate request
        _callStargateSwap(
            StargateSwapPayload({
                chainId: _originChainId,
                qty: _amountUSD,
                dstContract: _dstContract,
                payload: _payload,
                maxMarketMovement: _maxMarketMovementAllowed
            })
        );
    }

    /* Receiving */

    /* Receiving::withdrawals */

    /// @notice Dummy func to allow .selector call above and guarantee typesafety for abi calls.
    /// @dev Should never ever be actually called.
    function receiveXChainWithdrawalRequest(
        uint256 _originChainId,
        bytes memory _originAccount,
        uint256 _pid,
        uint256 _trancheId,
        uint256 _maxMarketMovement
    ) public {
        // Revert to make sure this function never gets called
        require(false, "illegal dummy func call");

        // But still include the function call here anyway to satisfy type safety requirements in case there is a change
        _receiveXChainWithdrawalRequest(
            _originChainId,
            _originAccount,
            _pid,
            _trancheId,
            _maxMarketMovement
        );
    }

    /// @notice Handler for receiving withdrawal requests
    /// @param _originChainId Zorro Chain ID of the chain that this request came from
    /// @param _originAccount Wallet address of sender who initiated this request on the origin chain
    /// @param _pid Pool ID to withdraw from
    /// @param _trancheId Tranche ID to withdraw from
    /// @param _maxMarketMovement Slippage factor (e.g. 950 = 5%, 990 = 1%, etc.)
    function _receiveXChainWithdrawalRequest(
        uint256 _originChainId,
        bytes memory _originAccount,
        uint256 _pid,
        uint256 _trancheId,
        uint256 _maxMarketMovement
    ) internal virtual {
        // Get on-chain account using foreign account as guide
        address _account = ZorroControllerInvestment(currentChainController)
            .foreignTrancheInfo(_pid, _originAccount, _trancheId);

        // Withdraw funds
        (, uint256 _rewardsDue) = IZorroControllerInvestment(
            currentChainController
        ).withdrawalFullServiceFromXChain(
                _account,
                _originAccount,
                _pid,
                _trancheId,
                false,
                _maxMarketMovement
            );

        // Get USD bal
        uint256 _balUSD = IERC20(defaultStablecoin).balanceOf(address(this));

        // Only proceed if there is something to withdraw
        require(_balUSD > 0, "Nothing to withdraw");

        // Repatriate funds
        _sendXChainRepatriationRequest(
            _originChainId,
            _pid,
            _trancheId,
            _originAccount,
            _balUSD,
            _rewardsDue,
            _maxMarketMovement
        );
    }

    /* Receiving::repatriation */

    /// @notice Dummy func to allow .selector call above and guarantee typesafety for abi calls.
    /// @dev Should never ever be actually called.
    function receiveXChainRepatriationRequest(
        uint256 _originChainId,
        uint256 _pid,
        uint256 _trancheId,
        bytes memory _originRecipient,
        uint256 _rewardsDue
    ) public {
        // Revert to make sure this function never gets called
        require(false, "illegal dummy func call");

        // But still include the function call here anyway to satisfy type safety requirements in case there is a change
        _receiveXChainRepatriationRequest(
            _originChainId,
            _pid,
            _trancheId,
            _originRecipient,
            _rewardsDue
        );
    }

    /// @notice Receives a repatriation request from another chain and takes care of all financial operations (unlock/mint/burn) to pay the user their withdrawn funds from another chain
    /// @param _originChainId The Chain ID of the investment being repatriated
    /// @param _pid The pid of the investment being repatriated
    /// @param _trancheId The tranche ID of the investment being repatriated
    /// @param _originRecipient The wallet address on this chain that funds are being repatriated to
    /// @param _rewardsDue ZOR rewards due to the recipient
    function _receiveXChainRepatriationRequest(
        uint256 _originChainId,
        uint256 _pid,
        uint256 _trancheId,
        bytes memory _originRecipient,
        uint256 _rewardsDue
    ) internal virtual {
        // Get EVM address (decode)
        address _destination = ZorroControllerXChainActions(controllerActions).bytesToAddress(_originRecipient);

        // Emit repatriation event
        emit XChainRepatriation(_pid, _destination, _trancheId, _originChainId);

        // Repatriate rewards
        IZorroControllerInvestment(currentChainController).repatriateRewards(
            _rewardsDue,
            _destination
        );
    }
}
