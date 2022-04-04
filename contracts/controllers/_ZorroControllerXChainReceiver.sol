// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../interfaces/ILayerZeroReceiver.sol";

import "../interfaces/IStargateReceiver.sol";

import "./_ZorroControllerXChainDeposit.sol";

import "./_ZorroControllerXChainWithdraw.sol";

import "./_ZorroControllerXChainEarn.sol";

contract ZorroControllerXChainReceiver is
    ZorroControllerXChainDeposit,
    ZorroControllerXChainWithdraw,
    ZorroControllerXChainEarn,
    IStargateReceiver,
    ILayerZeroReceiver
{
    /// @notice Receives stargate cross-chain calls
    /// @dev Implements IStargateReceiver interface
    function sgReceive(
        uint16 _chainId,
        bytes memory _srcAddress,
        uint256 _nonce,
        address _token,
        uint256 amountLD,
        bytes memory payload
    ) public override {
        // Map to Zorro chain ID
        uint256 _zorroOriginChainId = LZChainToZorroMap[_chainId];
        // Checks / authorization
        // Amounts
        uint256 _tokenBal = IERC20(_token).balanceOf(address(this));
        require(amountLD <= _tokenBal, "amountLD exceeds bal");
        // Access
        // Src address is a valid controller
        require(
            registeredXChainControllers[_srcAddress],
            "unrecognized controller"
        );

        // Determine function based on signature
        // Get func signature
        bytes4 _funcSig = bytes4(payload);
        // Match to appropriate func
        if (this.receiveXChainDepositRequest.selector == _funcSig) {
            // Decode params
            (
                ,
                uint256 _pid,
                ,
                uint256 _weeksCommitted,
                uint256 _maxMarketMovement,
                bytes memory _originAccount,
                address _destAccount
            ) = abi.decode(
                    payload,
                    (bytes4, uint256, uint256, uint256, uint256, bytes, address)
                );

            // Call receiving function for cross chain deposits
            // Replace _valueUSDC to account for any slippage during bridging
            _receiveXChainDepositRequest(
                _pid,
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
                ,
                uint256 _originChainId,
                uint256 _pid,
                uint256 _trancheId,
                bytes memory _originRecipient,
                uint256 _burnableZORRewards
            ) = abi.decode(
                    payload,
                    (bytes4, uint256, uint256, uint256, bytes, uint256)
                );
            // Forward request to repatriation function
            _receiveXChainRepatriationRequest(
                _originChainId,
                _pid,
                _trancheId,
                _originRecipient,
                _burnableZORRewards
            );
        } else if (this.receiveXChainDistributionRequest.selector == _funcSig) {
            // Decode params from payload
            (
                ,
                uint256 _remoteChainId, 
                uint256 _amountUSDCBuyback, 
                uint256 _amountUSDCRevShare
            ) = abi.decode(
                payload,
                (bytes4, uint256, uint256, uint256)
            );
            // Forward request to distribution function
            _receiveXChainDistributionRequest(
                _remoteChainId, 
                _amountUSDCBuyback, 
                _amountUSDCRevShare
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
    ) external override {
        // Map to Zorro chain ID
        uint256 _zorroOriginChainId = LZChainToZorroMap[_srcChainId];
        
        // Access
        // Src address is a valid controller
        // TODO: Might need to validate that the srcAddress is on the expected chain too
        require(
            registeredXChainControllers[_srcAddress],
            "unrecognized controller"
        );

        // Determine function based on signature
        // Get func signature
        bytes4 _funcSig = bytes4(_payload);
        // Match to appropriate func
        if (this.receiveXChainWithdrawalRequest.selector == _funcSig) {
            // Decode params
            (
                ,
                uint256 _originChainId,
                bytes memory _originAccount,
                uint256 _pid,
                uint256 _trancheId,
                uint256 _maxMarketMovement
            ) = abi.decode(
                    _payload,
                    (bytes4, uint256, bytes, uint256, uint256, uint256)
                );

            // Call receiving function for cross chain withdrawals
            // Replace _valueUSDC to account for any slippage during bridging
            _receiveXChainWithdrawalRequest(
                _originChainId,
                _originAccount,
                _pid,
                _trancheId,
                _maxMarketMovement
            );
        } else {
            revert("Unrecognized func");
        }
    }
}
