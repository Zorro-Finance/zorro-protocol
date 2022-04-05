// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./_ZorroControllerInvestment.sol";

import "../interfaces/IAMMRouter02.sol";

import "../interfaces/IVault.sol";

import "../libraries/SafeSwap.sol";

import "../interfaces/ILayerZeroEndpoint.sol";

import "../interfaces/IStargateRouter.sol";

contract ZorroControllerXChain is ZorroControllerInvestment {
    /* Libraries */
    using SafeMath for uint256;

    /* Structs */

    // Stargate swaps
    struct StargateSwapPayload {
        uint256 chainId;
        uint256 qty;
        bytes dstContract;
        bytes payload;
        uint256 maxMarketMovement;
    }

    // LayerZero messages
    struct LZMessagePayload {
        uint256 zorroChainId;
        bytes destinationContract;
        bytes payload;
        address payable refundAddress;
        address _zroPaymentAddress;
        bytes adapterParams;
    }

    /* Router functions */

    /// @notice Internal function for making swap calls to Stargate
    /// @param _swapPayload Struct with key swap payload information for the call to the Stargate router
    function _callStargateSwap(StargateSwapPayload memory _swapPayload)
        internal
    {
        IStargateRouter.lzTxObj memory _lzTxObj;
        IStargateRouter(stargateRouter).swap{value: msg.value}(
            ZorroChainToLZMap[_swapPayload.chainId],
            stargateSwapPoolId,
            stargateDestPoolIds[_swapPayload.chainId],
            payable(msg.sender),
            _swapPayload.qty,
            _swapPayload.qty.mul(_swapPayload.maxMarketMovement).div(1000),
            _lzTxObj,
            _swapPayload.dstContract,
            _swapPayload.payload
        );
    }

    /// @notice Internal function for sending cross chain messages using LayerZero
    /// @param _msgPayload Struct with key message details for the LayerZero cross chain transaction
    function _callLZSend(LZMessagePayload memory _msgPayload) internal {
        // Convert any key params
        uint16 _dstChainId = ZorroChainToLZMap[_msgPayload.zorroChainId];

        // Send transaction to layer
        ILayerZeroEndpoint(layerZeroEndpoint).send{value: msg.value}(
            _dstChainId,
            _msgPayload.destinationContract,
            _msgPayload.payload,
            _msgPayload.refundAddress,
            _msgPayload.refundAddress,
            _msgPayload.adapterParams
        );
    }
}
