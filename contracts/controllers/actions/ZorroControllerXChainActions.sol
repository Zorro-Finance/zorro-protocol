// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../../interfaces/Stargate/IStargateRouter.sol";

import "../../interfaces/LayerZero/ILayerZeroEndpoint.sol";

import "../../interfaces/IZorroControllerXChain.sol";

// TODO: Create interface for this contract

contract ZorroControllerXChainActions is OwnableUpgradeable {
    /* Constructor */

    /// @notice Constructor
    /// @param _stargateRouter Address of Stargate router
    /// @param _lzEndpoint Address of LayerZero endpoint for this chain
    function initialize(address _stargateRouter, address _lzEndpoint)
        public
        initializer
    {
        stargateRouter = _stargateRouter;
        layerZeroEndpoint = _lzEndpoint;
    }

    /* State */

    address public stargateRouter; 
    address public layerZeroEndpoint; 

    /* Utilities */

    /// @notice Decodes bytes array to address
    /// @param bys Bytes array 
    /// @return addr Address value
    function bytesToAddress(bytes memory bys) public pure returns (address addr) {
        assembly {
            addr := mload(add(bys,20))
        } 
    }

    /// @notice Removes function signature from ABI encoded payload
    /// @param _payloadWithSig ABI encoded payload with function selector
    /// @return paramsPayload Payload with params only
    function extractParamsPayload(bytes calldata _payloadWithSig) public pure returns (bytes memory paramsPayload) {
        paramsPayload = _payloadWithSig[4:];
    }

    /* Deposits */

    /// @notice Checks to see how much a cross chain deposit will cost
    /// @param _lzChainId The LayerZero Chain ID (not the Zorro one)
    /// @param _dstContract The destination contract address on the remote chain
    /// @param _payload The byte encoded cross chain payload (use encodeXChainDepositPayload() below)
    /// @return nativeFee Expected fee to pay for bridging/cross chain execution
    function checkXChainDepositFee(
        uint16 _lzChainId,
        bytes memory _dstContract,
        bytes memory _payload
    ) external view returns (uint256 nativeFee) {
        // Init empty LZ object
        IStargateRouter.lzTxObj memory _lzTxParams;

        // Calculate native gas fee and ZRO token fee (Layer Zero token)
        (nativeFee, ) = IStargateRouter(stargateRouter)
            .quoteLayerZeroFee(
                _lzChainId,
                1,
                _dstContract,
                _payload,
                _lzTxParams
            );
    }

    /// @notice Encodes payload for making cross chan deposit
    /// @param _pid Pool ID on remote chain
    /// @param _valueUSD Amount in USD to deposit
    /// @param _weeksCommitted Number of weeks to commit deposit for in vault
    /// @param _maxMarketMovement Slippage parameter (e.g. 950 = 5%, 990 = 1%, etc.)
    /// @param _originWallet Wallet address on origin chain that will be depositing funds cross chain.
    /// @param _destWallet Optional wallet address on destination chain that will be receiving deposit. If not provided, will use a truncated address based on the _originWallet
    /// @return payload The ABI encoded payload
    function encodeXChainDepositPayload(
        uint256 _pid,
        uint256 _valueUSD,
        uint256 _weeksCommitted,
        uint256 _maxMarketMovement,
        address _originWallet,
        bytes memory _destWallet
    ) public view returns (bytes memory payload) {
        // Calculate method signature
        bytes4 _sig = IZorroControllerXChainDeposit.receiveXChainDepositRequest.selector;

        // Calculate abi encoded bytes for input args
        bytes memory _inputs = abi.encode(
            _pid,
            _valueUSD,
            _weeksCommitted,
            _maxMarketMovement,
            abi.encodePacked(_originWallet), // Convert address to bytes
            this.bytesToAddress(_destWallet) // Decode bytes to address
        );
        // Concatenate bytes of signature and inputs
        payload = bytes.concat(_sig, _inputs);

        require(payload.length > 0, "Invalid xchain payload");
    }

    /* Earn */

    /// @notice Checks to see how much a cross chain earnings distribution will cost
    /// @param _lzChainId The Layer Zero chain ID (NOT the Zorro chain ID)
    /// @param _homeChainZorroController Address of the home chain Zorro controller (the destination contract)
    /// @param _payload The bytes encoded payload to be sent to the home chain (result of encodeXChainDistributeEarningsPayload())
    /// @return nativeFee Quantity of native token as fees
    function checkXChainDistributeEarningsFee(
        uint16 _lzChainId,
        address _homeChainZorroController,
        bytes memory _payload
    ) external view returns (uint256 nativeFee) {
        // Init empty LZ object
        IStargateRouter.lzTxObj memory _lzTxParams;

        // Get payload
        bytes memory _dstContract = abi.encodePacked(_homeChainZorroController);

        // Calculate native gas fee and ZRO token fee (Layer Zero token)
        (nativeFee, ) = IStargateRouter(stargateRouter)
            .quoteLayerZeroFee(
                _lzChainId,
                1,
                _dstContract,
                _payload,
                _lzTxParams
            );
    }

    /// @notice Encodes payload for making cross chan earnings distribution request
    /// @param _remoteChainId Zorro chain ID of the chain making the distribution request
    /// @param _amountUSDBuyback Amount in USD to buy back
    /// @param _amountUSDRevShare Amount in USD to rev share with ZOR staking vault
    /// @param _accSlashedRewards Accumulated slashed rewards on chain
    /// @param _maxMarketMovement factor to account for max market movement/slippage.
    /// @return bytes ABI encoded payload
    function encodeXChainDistributeEarningsPayload(
        uint256 _remoteChainId,
        uint256 _amountUSDBuyback,
        uint256 _amountUSDRevShare,
        uint256 _accSlashedRewards,
        uint256 _maxMarketMovement
    ) public pure returns (bytes memory) {
        // Calculate method signature
        bytes4 _sig = IZorroControllerXChainEarn.receiveXChainDistributionRequest.selector;
        // Calculate abi encoded bytes for input args
        bytes memory _inputs = abi.encode(
            _remoteChainId,
            _amountUSDBuyback,
            _amountUSDRevShare,
            _accSlashedRewards,
            _maxMarketMovement
        );
        // Concatenate bytes of signature and inputs
        return bytes.concat(_sig, _inputs);
    }

    /* Withdrawals */

    /// @notice Checks to see how much a cross chain withdrawal will cost
    /// @param _lzChainId The LayerZero Chain ID (not the Zorro one)
    /// @param _payload The bytes encoded withdrawal payload (calculated from encodeXChainWithdrawalPayload() below)
    /// @param _gasForDestinationLZReceive How much additional gas to provide at destination contract
    /// @return nativeFee Expected fee to pay for bridging/cross chain execution
    function checkXChainWithdrawalFee(
        uint16 _lzChainId,
        bytes memory _payload,
        uint256 _gasForDestinationLZReceive
    ) external view returns (uint256 nativeFee) {
        // Encode adapter params to provide more gas for destination
        bytes memory _adapterParams = this.getLZAdapterParamsForWithdraw(
            _gasForDestinationLZReceive
        );

        // Query LayerZero for quote
        (nativeFee, ) = ILayerZeroEndpoint(layerZeroEndpoint)
            .estimateFees(
                _lzChainId,
                address(this),
                _payload,
                false,
                _adapterParams
            );
    }

    /// @notice Encodes adapter params to provide more gas for destination
    /// @param _gasForDestinationLZReceive How much additional gas to provide at destination contract
    /// @return bytes Adapter payload
    function getLZAdapterParamsForWithdraw(uint256 _gasForDestinationLZReceive)
        public
        pure
        returns (bytes memory)
    {
        uint16 _version = 1;
        return abi.encodePacked(_version, _gasForDestinationLZReceive);
    }

    /// @notice Encodes payload for making cross chan withdrawal
    /// @param _originChainId Chain that withdrawal request originated from
    /// @param _originAccount Account on origin chain that withdrawal request originated from
    /// @param _pid Pool ID on remote chain
    /// @param _trancheId Tranche ID on remote chain
    /// @param _maxMarketMovement Slippage parameter (e.g. 950 = 5%, 990 = 1%, etc.)
    /// @return bytes ABI encoded payload
    function encodeXChainWithdrawalPayload(
        uint256 _originChainId,
        bytes memory _originAccount,
        uint256 _pid,
        uint256 _trancheId,
        uint256 _maxMarketMovement
    ) public pure returns (bytes memory) {
        // Calculate method signature
        bytes4 _sig = IZorroControllerXChainWithdraw.receiveXChainWithdrawalRequest.selector;

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

    /// @notice Estimates fees for repatriation operation
    /// @param _lzChainId The chain ID on LayerZero (not the Zorro one) for the chain to which funds are being repatriated
    /// @param _dstContract The bytes encoded address of the destination contract (controller address on chain being repatriated to)
    /// @param _payload The bytes encoded payload to be sent to the destination chain (calculated from encodeXChainRepatriationPayload())
    /// @return nativeFee Estimated fee in native tokens
    function checkXChainRepatriationFee(
        uint16 _lzChainId,
        bytes memory _dstContract,
        bytes memory _payload
    ) external view returns (uint256 nativeFee) {
        // Init empty LZ object
        IStargateRouter.lzTxObj memory _lzTxParams;

        // Calculate native gas fee and ZRO token fee (Layer Zero token)
        (nativeFee, ) = IStargateRouter(stargateRouter)
            .quoteLayerZeroFee(
                _lzChainId,
                1,
                _dstContract,
                _payload,
                _lzTxParams
            );
    }


    /// @notice Encodes payload for making cross chain repatriation
    /// @param _originChainId Zorro chain ID of chain that funds shall be repatriated back to
    /// @param _pid Pool ID on current chain that withdrawal came from
    /// @param _trancheId Tranche ID on current chain that withdrawal came from
    /// @param _originRecipient Recipient on home chain that repatriated funds shall be sent to
    /// @param _rewardsDue ZOR rewards due to the recipient
    /// @return bytes ABI encoded payload
    function encodeXChainRepatriationPayload(
        uint256 _originChainId,
        uint256 _pid,
        uint256 _trancheId,
        bytes memory _originRecipient,
        uint256 _rewardsDue
    ) public pure returns (bytes memory) {
        // Calculate method signature
        bytes4 _sig = IZorroControllerXChainWithdraw.receiveXChainRepatriationRequest.selector;

        // Calculate abi encoded bytes for input args
        bytes memory _inputs = abi.encode(
            _originChainId,
            _pid,
            _trancheId,
            _originRecipient,
            _rewardsDue
        );

        // Concatenate bytes of signature and inputs
        return bytes.concat(_sig, _inputs);
    }
}