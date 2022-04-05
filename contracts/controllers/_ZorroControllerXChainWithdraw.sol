// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./_ZorroControllerXChain.sol";

contract ZorroControllerXChainWithdraw is ZorroControllerXChain {
    /* Libraries */
    using SafeMath for uint256;

    /* Events */
    event XChainRepatriation(
        uint256 indexed _pid,
        address indexed _originRecipient,
        uint256 indexed _burnableZORRewards,
        uint256 _trancheId,
        uint256 _originChainId
    );

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
        uint16 _dstChainId = ZorroChainToLZMap[_zorroChainId];

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
        (uint256 _nativeFee, ) = ILayerZeroEndpoint(layerZeroEndpoint)
            .estimateFees(
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
    function _getLZAdapterParamsForWithdraw()
        internal
        pure
        returns (bytes memory)
    {
        uint16 _version = 1;
        uint256 _gasForDestinationLZReceive = 350000;
        return abi.encodePacked(_version, _gasForDestinationLZReceive);
    }

    /* Fees::repatriation */

    /// @notice Estimates fees for repatriation operation
    /// @param _originChainId Zorro chain ID of chain to which funds are to be repatriated to
    /// @param _pid Pool ID on current chain
    /// @param _trancheId ID of tranche on current chain that funds were withdrawn from
    /// @param _originRecipient Recipient of funds on the origin chain
    /// @param _burnableZORRewards Quantity of ZOR tokens minted for rewards here that need to be burned on the home chain
    /// @param _rewardsDue ZOR rewards due to the recipient
    /// @return uint256 Estimated fee in native tokens
    function _checkXChainRepatriationFee(
        uint256 _originChainId,
        uint256 _pid,
        uint256 _trancheId,
        bytes memory _originRecipient,
        uint256 _burnableZORRewards,
        uint256 _rewardsDue
    ) internal view returns (uint256) {
        // Init empty LZ object
        IStargateRouter.lzTxObj memory _lzTxParams;

        // Get payload
        bytes memory _payload = _encodeXChainRepatriationPayload(
            _originChainId,
            _pid,
            _trancheId,
            _originRecipient,
            _burnableZORRewards,
            _rewardsDue
        );
        bytes memory _dstContract = controllerContractsMap[_originChainId];

        // Calculate native gas fee and ZRO token fee (Layer Zero token)
        (uint256 _nativeFee, uint256 _lzFee) = IStargateRouter(stargateRouter)
            .quoteLayerZeroFee(
                ZorroChainToLZMap[_originChainId],
                1,
                _dstContract,
                _payload,
                _lzTxParams
            );

        return _nativeFee.add(_lzFee);
    }

    /* Encoding (payloads) */

    /* Encoding::withdrawals */

    /// @notice Encodes payload for making cross chan withdrawal
    /// @param _originChainId Chain that withdrawal request originated from
    /// @param _originAccount Account on origin chain that withdrawal request originated from
    /// @param _pid Pool ID on remote chain
    /// @param _trancheId Tranche ID on remote chain
    /// @param _maxMarketMovement Slippage parameter (e.g. 950 = 5%, 990 = 1%, etc.)
    /// @return bytes ABI encoded payload
    function _encodeXChainWithdrawalPayload(
        uint256 _originChainId,
        bytes memory _originAccount,
        uint256 _pid,
        uint256 _trancheId,
        uint256 _maxMarketMovement
    ) internal pure returns (bytes memory) {
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

    /// @notice Encodes payload for making cross chain repatriation
    /// @param _originChainId Zorro chain ID of chain that funds shall be repatriated back to
    /// @param _pid Pool ID on current chain that withdrawal came from
    /// @param _trancheId Tranche ID on current chain that withdrawal came from
    /// @param _originRecipient Recipient on home chain that repatriated funds shall be sent to
    /// @param _burnableZORRewards Qty of minted ZOR that needs to be burned on the home chain
    /// @param _rewardsDue ZOR rewards due to the recipient
    /// @return bytes ABI encoded payload
    function _encodeXChainRepatriationPayload(
        uint256 _originChainId,
        uint256 _pid,
        uint256 _trancheId,
        bytes memory _originRecipient,
        uint256 _burnableZORRewards,
        uint256 _rewardsDue
    ) internal pure returns (bytes memory) {
        // Calculate method signature
        bytes4 _sig = this.receiveXChainRepatriationRequest.selector;
        // Calculate abi encoded bytes for input args
        bytes memory _inputs = abi.encode(
            _originChainId,
            _pid,
            _trancheId,
            _originRecipient,
            _burnableZORRewards,
            _rewardsDue
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
        bytes memory _dstContract = controllerContractsMap[_destZorroChainId];

        // Send LayerZero request
        _callLZSend(
            LZMessagePayload({
                zorroChainId: _destZorroChainId,
                destinationContract: _dstContract,
                payload: _payload,
                refundAddress: payable(msg.sender),
                _zroPaymentAddress: address(0),
                adapterParams: _getLZAdapterParamsForWithdraw()
            })
        );
    }

    /* Sending::repatriation */

    /// @notice Prepares and sends cross chain repatriation request via Stargate
    /// @param _originChainId Chain ID of origin chain that repatriation shall go to
    /// @param _pid Pool ID on current chain that withdrawal came from
    /// @param _trancheId Tranche ID on current chain that withdrawal came from
    /// @param _originRecipient Recipient on home chain that repatriate funds shall go to
    /// @param _amountUSDC Amount withdrawn, to be repatriated
    /// @param _burnableZORRewards ZOR rewards minted, to be burned from the public pool on the home chain
    /// @param _rewardsDue ZOR rewards due to the recipient
    /// @param _maxMarketMovementAllowed Acceptable slippage (950 = 5%, 990 = 1%, etc.)
    function _sendXChainRepatriationRequest(
        uint256 _originChainId,
        uint256 _pid,
        uint256 _trancheId,
        bytes memory _originRecipient,
        uint256 _amountUSDC,
        uint256 _burnableZORRewards,
        uint256 _rewardsDue,
        uint256 _maxMarketMovementAllowed
    ) internal {
        // Prep payload
        bytes memory _payload = _encodeXChainRepatriationPayload(
            _originChainId,
            _pid,
            _trancheId,
            _originRecipient,
            _burnableZORRewards,
            _rewardsDue
        );
        // Destination info
        bytes memory _dstContract = controllerContractsMap[_originChainId];

        // Send Stargate request
        _callStargateSwap(
            StargateSwapPayload({
                chainId: _originChainId,
                qty: _amountUSDC,
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
    ) internal {
        // Get on-chain account using foreign account as guide
        address _account = foreignTrancheInfo[_pid][_originAccount][_trancheId];

        // Withdraw funds
        (, uint256 _mintedZORRewards, uint256 _rewardsDue,) = _withdrawalFullService(
            _account,
            _originAccount,
            _pid,
            _trancheId,
            false,
            _maxMarketMovement
        );

        // Get USDC bal
        uint256 _balUSDC = IERC20(defaultStablecoin).balanceOf(address(this));

        // Only proceed if there is something to withdraw
        require(_balUSDC > 0, "Nothing to withdraw");

        // Repatriate funds
        _sendXChainRepatriationRequest(
            _originChainId,
            _pid,
            _trancheId,
            _originAccount,
            _balUSDC,
            _mintedZORRewards,
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
        uint256 _burnableZORRewards,
        uint256 _rewardsDue
    ) public {
        // Revert to make sure this function never gets called
        revert("illegal dummy func call");

        // But still include the function call here anyway to satisfy type safety requirements in case there is a change
        _receiveXChainRepatriationRequest(
            _originChainId,
            _pid,
            _trancheId,
            _originRecipient,
            _burnableZORRewards,
            _rewardsDue
        );
    }

    /// @notice Receives a repatriation request from another chain and takes care of all financial operations (unlock/mint/burn) to pay the user their withdrawn funds from another chain
    /// @param _originChainId The Chain ID of the investment being repatriated
    /// @param _pid The pid of the investment being repatriated
    /// @param _trancheId The tranche ID of the investment being repatriated
    /// @param _originRecipient The wallet address on this chain that funds are being repatriated to
    /// @param _burnableZORRewards The amount of ZOR token to be burned (since rewards were minted on the opposite chain)
    /// @param _rewardsDue ZOR rewards due to the recipient
    function _receiveXChainRepatriationRequest(
        uint256 _originChainId,
        uint256 _pid,
        uint256 _trancheId,
        bytes memory _originRecipient,
        uint256 _burnableZORRewards,
        uint256 _rewardsDue
    ) internal {
        // Emit repatriation event
        emit XChainRepatriation(
            _pid,
            abi.decode(_originRecipient, (address)),
            _burnableZORRewards,
            _trancheId,
            _originChainId
        );

        // Mint ZOR and send to user
        Zorro(ZORRO).mint(abi.decode(_originRecipient, (address)), _rewardsDue);

        // Burn ZOR rewards as applicable (since rewards were minted on the other chain)
        if (_burnableZORRewards > 0) {
            Zorro(ZORRO).burn(publicPool, _burnableZORRewards);
        }
    }
}
