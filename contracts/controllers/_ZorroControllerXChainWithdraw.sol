// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./_ZorroControllerXChain.sol";


contract ZorroControllerXChainWithdraw is ZorroControllerXChain {
    /* Fees */

    /* Fees::withdrawals */

    /// @notice Checks to see how much a cross chain withdrawal will cost
    /// @param _zorroChainId The Zorro Chain ID (not the LayerZero one)
    /// @param _pid The pool ID on the remote chain
    /// @param _trancheId The tranche ID on the remote chain
    /// @param _maxMarketMovement Acceptable degree of slippage on any transaction (e.g. 950 = 5%, 990 = 1% etc.)
    /// @return uint256 Expected fee to pay for bridging/cross chain execution
    function checkXChainWithdrawalFee(
        uint256 _zorroChainId,
        uint256 _pid,
        uint256 _trancheId,
        uint256 _maxMarketMovement
    ) external view returns (uint256) {
        // Get destination 
        uint16 _dstChainId = stargateZorroChainMap[_zorroChainId];

        // Prepare encoding
        bytes memory _payload = _encodeXChainWithdrawalPayload(
            chainId,
            abi.encodePacked(msg.sender),  
            _pid, 
            _trancheId, 
            _maxMarketMovement
        );

        // Encode adapter params to provide more gas for destination
        bytes memory _adapterParams = _getLZAdapterParamsForWithdraw();

        // Query LayerZero for quote
        (uint256 _nativeFee,) = ILayerZeroEndpoint(layerZeroEndpoint).estimateFees(
            _dstChainId, 
            address(this), 
            _payload, 
            false, 
            _adapterParams
        );
        // TODO: Check if we need to sum these values or what? Need to better understand fee estimation in general: Oracle, relayer fees etc. 
        return _nativeFee;
    }

    /// @notice Encodes adapter params to provide more gas for destination
    function _getLZAdapterParamsForWithdraw() internal pure returns (bytes memory) {
        uint16 _version = 1;
        uint256 _gasForDestinationLZReceive = 350000;
        return abi.encodePacked(_version, _gasForDestinationLZReceive);
    }

    /* Fees::repatriation */

    // TODO: Docstrings
    function _checkXChainRepatriationFee() internal view returns (uint256) {
        // TODO: Implement
    }

    /* Encoding (payloads) */

    /* Encoding::withdrawals */

    // TODO: docstrings
    function _encodeXChainWithdrawalPayload(
        uint256 _originChainId,
        bytes memory _originAccount,
        uint256 _pid,
        uint256 _trancheId,
        uint256 _maxMarketMovement
    ) internal pure returns (bytes memory) {
        // TODO: Implement
        // Calculate method signature
        bytes4 _sig = this.receiveXChainWithdrawalRequest.selector;
        // Calculate abi encoded bytes for input args
        bytes memory _inputs = abi.encode(
            _originChainId,
            _originAccount,
            _pid,
            _trancheId,
            _maxMarketMovement
        );
        // Concatenate bytes of signature and inputs
        return bytes.concat(_sig, _inputs);
    }

    /* Encoding::repatriation */

    // TODO: docstrings
    function _encodeXChainRepatriationPayload(
        uint256 _originChainId,
        uint256 _pid,
        uint256 _trancheId,
        bytes memory _originRecipient,
        uint256 _burnableZORRewards
    ) internal pure returns (bytes memory) {
        // Calculate method signature
        bytes4 _sig = this.receiveXChainRepatriationRequest.selector;
        // Calculate abi encoded bytes for input args
        bytes memory _inputs = abi.encode(
            _originChainId,
            _pid,
            _trancheId,
            _originRecipient,
            _burnableZORRewards
        );
        // Concatenate bytes of signature and inputs
        return bytes.concat(_sig, _inputs);
    }

    /* Sending */

    /* Sending::withdrawals */

    /// @notice Prepares and sends a cross chain withdrwal request.
    /// @dev Requires value to be submitted to pay for cross chain transaction. Use checkXChainWithdrawalFee() to estimate fees
    /// @param _destZorroChainId The Zorro chain ID of the remote chain to withdraw from
    /// @param _pid The pool ID on the remote chain
    /// @param _trancheId The ID of the tranche for the given user and pool
    /// @param _maxMarketMovement Acceptable degree of slippage on any transaction (e.g. 950 = 5%, 990 = 1% etc.)
    function sendXChainWithdrawalRequest(
        uint256 _destZorroChainId,
        bytes memory _originAccount,
        uint256 _pid,
        uint256 _trancheId,
        uint256 _maxMarketMovement
    ) external payable nonReentrant {
        // Prep payload
        bytes memory _payload = _encodeXChainWithdrawalPayload(
            chainId, 
            abi.encodePacked(msg.sender),
            _pid,
            _trancheId, 
            _maxMarketMovement
        );

        // Destination info
        bytes memory _dstContract = abi.encodePacked(endpointContracts[_destZorroChainId]);

        // Send LayerZero request
        _callLZSend(LZMessagePayload({
            zorroChainId: _destZorroChainId,
            destinationContract: _dstContract,
            payload: _payload,
            refundAddress: payable(msg.sender),
            _zroPaymentAddress: address(0),
            adapterParams: _getLZAdapterParamsForWithdraw()
        }));
    }

    /* Sending::repatriation */

    // TODO: Docstrings
    function _sendXChainRepatriationRequest() internal {
        // TODO: implement
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
        revert("illegal dummy func call");

        // But still include the function call here anyway to satisfy type safety requirements in case there is a change
        _receiveXChainWithdrawalRequest(
            _originChainId,
            _originAccount,
            _pid,
            _trancheId,
            _maxMarketMovement
        );
    }

    // TODO: docstrings
    function _receiveXChainWithdrawalRequest(
        uint256 _originChainId,
        bytes memory _originAccount,
        uint256 _pid,
        uint256 _trancheId,
        uint256 _maxMarketMovement
    ) internal {
        // Get on-chain account using foreign account as guide
        address _account;
        for (
            uint256 i = 0;
            i < foreignTrancheInfo[_pid][_originAccount].length;
            ++i
        ) {
            ForeignTrancheInfo memory _fti = foreignTrancheInfo[_pid][
                _originAccount
            ][i];
            if (_fti.trancheIndex == _trancheId) {
                _account = _fti.localAccount;
                break;
            }
        }

        // Get tranche
        TrancheInfo memory tranche = trancheInfo[_pid][_account][_trancheId];

        // Withdraw funds
        _withdrawalFullService(
            _account,
            _originAccount,
            _pid,
            _trancheId,
            false,
            _maxMarketMovement
        );

        // TODO: Very important: Determine burnable rewards for real during:
        /*
        1. Deposits (xchain)
        2. Withdrawals (xchain)
        For now, just setting it to zero. (Dummy value)
        */
        uint256 _burnableZORRewards = 0;


        // Get USDC bal
        uint256 _balUSDC = IERC20(defaultStablecoin).balanceOf(address(this));

        // Only proceed if there is something to withdraw
        require(_balUSDC > 0, "Nothing to withdraw");

        // Repatriate funds
        // Get payload
        bytes memory _payload = _encodeXChainRepatriationPayload(
            _originChainId,
            _pid,
            _trancheId,
            _originAccount,
            _burnableZORRewards
        );
        // Get origin chain destination
        bytes memory _dstContract = abi.encodePacked(endpointContracts[_originChainId]);
        // Call Stargate
        _callStargateSwap(
            StargateSwapPayload({
                chainId: _originChainId,
                qty: _balUSDC,
                dstContract: _dstContract,
                payload: _payload,
                maxMarketMovement: _maxMarketMovement
            })
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
        uint256 _burnableZORRewards
    ) public {
        // Revert to make sure this function never gets called
        revert("illegal dummy func call");

        // But still include the function call here anyway to satisfy type safety requirements in case there is a change
        _receiveXChainRepatriationRequest(
            _originChainId,
            _pid,
            _trancheId,
            _originRecipient,
            _burnableZORRewards
        );
    }

    /// @notice Receives a repatriation request from another chain and takes care of all financial operations (unlock/mint/burn) to pay the user their withdrawn funds from another chain
    /// @param _originChainId The Chain ID of the investment being repatriated
    /// @param _pid The pid of the investment being repatriated
    /// @param _trancheId The tranche ID of the investment being repatriated
    /// @param _originRecipient The wallet address on this chain that funds are being repatriated to
    /// @param _burnableZORRewards The amount of ZOR token to be burned (since rewards were minted on the opposite chain)
    function _receiveXChainRepatriationRequest(
        uint256 _originChainId,
        uint256 _pid,
        uint256 _trancheId,
        bytes memory _originRecipient,
        uint256 _burnableZORRewards
    ) internal {
        // Emit repatriation event TODO

        // Burn ZOR rewards as applicable (since rewards were minted on the other chain)
        if (_burnableZORRewards > 0) {
            // TODO: Burn ZOR
        }
    }
}