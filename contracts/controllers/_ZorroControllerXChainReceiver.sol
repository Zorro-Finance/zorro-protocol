// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../interfaces/LayerZero/ILayerZeroReceiver.sol";

import "../interfaces/Stargate/IStargateReceiver.sol";

import "./_ZorroControllerXChainDeposit.sol";

import "./_ZorroControllerXChainWithdraw.sol";

import "./_ZorroControllerXChainEarn.sol";

import "../interfaces/Zorro/Controllers/IZorroControllerXChain.sol";

contract ZorroControllerXChainReceiver is
    IZorroControllerXChainReceiver,
    ZorroControllerXChainDeposit,
    ZorroControllerXChainWithdraw,
    ZorroControllerXChainEarn
{
    /* Modifiers */
    /// @notice Ensures cross chain request is coming only from a LZ endpoint or STG router address
    modifier onlyRegEndpoint() {
        require(
            msg.sender == layerZeroEndpoint || msg.sender == stargateRouter,
            "Unrecog xchain sender"
        );
        _;
    }

    /* Receivers */

    /// @notice Receives stargate cross-chain calls
    /// @dev Implements IStargateReceiver interface
    function sgReceive(
        uint16 _chainId,
        bytes memory _srcAddress,
        uint256 _nonce,
        address _token,
        uint256 amountLD,
        bytes memory payload
    ) public override onlyRegEndpoint {
        // Checks / authorization
        require(_chainId >= 0);
        require(_srcAddress.length > 0);
        require(_nonce >= 0);
        // Amounts
        uint256 _tokenBal = IERC20(_token).balanceOf(address(this));
        require(amountLD <= _tokenBal, "amountLD exceeds bal");

        // Determine function based on signature
        // Get func signature
        bytes4 _funcSig = bytes4(payload);
        // Get params payload only
        bytes memory _paramsPayload = ZorroControllerXChainActions(
            controllerActions
        ).extractParamsPayload(payload);

        // Match to appropriate func
        if (this.receiveXChainDepositRequest.selector == _funcSig) {
            // Decode params
            (
                uint256 _vid,
                ,
                uint256 _weeksCommitted,
                uint256 _maxMarketMovement,
                bytes memory _originAccount,
                address _destAccount
            ) = abi.decode(
                    _paramsPayload,
                    (uint256, uint256, uint256, uint256, bytes, address)
                );

            // Call receiving function for cross chain deposits
            // Replace _valueUSD to account for any slippage during bridging
            _receiveXChainDepositRequest(
                _vid,
                amountLD,
                _weeksCommitted,
                block.timestamp,
                _maxMarketMovement,
                _originAccount,
                _destAccount
            );
        } else if (this.receiveXChainRepatriationRequest.selector == _funcSig) {
            // Decode params from payload
            (
                uint256 _originChainId,
                uint256 _vid,
                uint256 _trancheId,
                bytes memory _originRecipient,
                uint256 _rewardsDue
            ) = abi.decode(
                    _paramsPayload,
                    (uint256, uint256, uint256, bytes, uint256)
                );
            // Forward request to repatriation function
            _receiveXChainRepatriationRequest(
                _originChainId,
                _vid,
                _trancheId,
                _originRecipient,
                _rewardsDue
            );
        } else if (this.receiveXChainDistributionRequest.selector == _funcSig) {
            // Decode params from payload
            (
                uint256 _remoteChainId,
                uint256 _amountUSDBuyback,
                uint256 _amountUSDRevShare,
                uint256 _accSlashedRewards,
                uint256 _maxMarketMovement
            ) = abi.decode(
                    _paramsPayload,
                    (uint256, uint256, uint256, uint256, uint256)
                );
            // Forward request to distribution function
            _receiveXChainDistributionRequest(
                _remoteChainId,
                _amountUSDBuyback,
                _amountUSDRevShare,
                _accSlashedRewards,
                _maxMarketMovement
            );
        } else {
            revert("Unrecognized func");
        }
    }

    function lzReceive(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        uint64 _nonce,
        bytes calldata _payload
    ) external override onlyRegEndpoint() {
        // Check requirements
        require(_srcChainId >= 0);
        require(_srcAddress.length > 0);
        require(_nonce >= 0);

        // Determine function based on signature
        // Get func signature
        bytes4 _funcSig = bytes4(_payload);
        // Get params-only payload
        bytes memory _paramsPayload = ZorroControllerXChainActions(
            controllerActions
        ).extractParamsPayload(_payload);
        // Match to appropriate func
        if (this.receiveXChainWithdrawalRequest.selector == _funcSig) {
            // Decode params
            (
                uint256 _originChainId,
                bytes memory _originAccount,
                uint256 _vid,
                uint256 _trancheId,
                uint256 _maxMarketMovement,
                uint256 _dstGasForCall
            ) = abi.decode(
                    _paramsPayload,
                    (uint256, bytes, uint256, uint256, uint256, uint256)
                );

            // Call receiving function for cross chain withdrawals
            // Replace _valueUSD to account for any slippage during bridging
            _receiveXChainWithdrawalRequest(
                _originChainId,
                _originAccount,
                _vid,
                _trancheId,
                _maxMarketMovement,
                _dstGasForCall
            );
        } else {
            revert("Unrecognized func");
        }
    }
}
