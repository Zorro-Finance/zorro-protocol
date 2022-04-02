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
        uint256 _zorroOriginChainId = zorroStargateChainMap[_chainId];
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
            // TODO: Make sure not to get _chainIds mixed up here
            (
                ,
                uint256 _originChainId,
                uint256 _pid,
                uint256 _trancheId,
                bytes memory _originRecipient,
                uint256 _burnableZORRewards
            ) = abi.decode(
                    payload,
                    (
                        bytes4,
                        uint256,
                        uint256,
                        uint256,
                        bytes,
                        uint256
                    )
                );
            // Forward request to repatriation function
            _receiveXChainRepatriationRequest(
                _originChainId,
                _pid,
                _trancheId,
                _originRecipient,
                _burnableZORRewards
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
        // TODO: Implement in a similar way to sgReceive().
        // Need receiveXChainWithdrawalRequest
    }
}
