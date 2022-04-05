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

    /* State */
    
    mapping(uint256 => bytes) public controllerContractsMap; // Mapping of Zorro chain ID to endpoint contract
    mapping(uint256 => uint16) public ZorroChainToLZMap; // Mapping of Zorro Chain ID to Stargate/LayerZero Chain ID
    address public stargateRouter; // Address to on-chain Stargate router
    uint256 public stargateSwapPoolId; // Address of the pool to swap from on this contract
    mapping(uint256 => uint256) public stargateDestPoolIds; // Mapping from Zorro chain ID to Stargate dest Pool for the same token
    address public layerZeroEndpoint; // Address to on-chain LayerZero endpoint

    /* Setters */
    // TODO: Setters/contructors needed


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
