// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./_ZorroControllerXChainBase.sol";

import "../interfaces/IZorroController.sol";

import "../interfaces/IZorroControllerXChain.sol";

contract ZorroControllerXChainDeposit is
    IZorroControllerXChainDeposit,
    ZorroControllerXChainBase
{
    /* Libraries */
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /* Fees */

    /// @notice Checks to see how much a cross chain deposit will cost
    /// @param _chainId The Zorro Chain ID (not the LayerZero one)
    /// @param _dstContract The destination contract address on the remote chain
    /// @param _pid The pool ID on the remote chain
    /// @param _valueUSDC The amount of USDC to deposit
    /// @param _weeksCommitted Number of weeks to commit to a vault
    /// @param _maxMarketMovement Acceptable degree of slippage on any transaction (e.g. 950 = 5%, 990 = 1% etc.)
    /// @param _destWallet A valid address on the remote chain that can claim ownership
    /// @return uint256 Expected fee to pay for bridging/cross chain execution
    function checkXChainDepositFee(
        uint256 _chainId,
        bytes memory _dstContract,
        uint256 _pid,
        uint256 _valueUSDC,
        uint256 _weeksCommitted,
        uint256 _maxMarketMovement,
        bytes memory _destWallet
    ) external view returns (uint256) {
        // Init empty LZ object
        IStargateRouter.lzTxObj memory _lzTxParams;

        // Get payload
        bytes memory _payload = _encodeXChainDepositPayload(
            _chainId,
            _pid,
            _valueUSDC,
            _weeksCommitted,
            _maxMarketMovement,
            msg.sender,
            _destWallet
        );

        // Calculate native gas fee and ZRO token fee (Layer Zero token)
        (uint256 _nativeFee, ) = IStargateRouter(stargateRouter)
            .quoteLayerZeroFee(
                ZorroChainToLZMap[_chainId],
                1,
                _dstContract,
                _payload,
                _lzTxParams
            );
        return _nativeFee;
    }

    /* Payload encoding */

    /// @notice Encodes payload for making cross chan deposit
    /// @param _destChainId Destination Zorro Chain ID
    /// @param _pid Pool ID on remote chain
    /// @param _valueUSDC Amount in USDC to deposit
    /// @param _weeksCommitted Number of weeks to commit deposit for in vault
    /// @param _maxMarketMovement Slippage parameter (e.g. 950 = 5%, 990 = 1%, etc.)
    /// @param _originWallet Wallet address on origin chain that will be depositing funds cross chain.
    /// @param _destWallet Optional wallet address on destination chain that will be receiving deposit. If not provided, will use a truncated address based on the _originWallet
    /// @return payload The ABI encoded payload
    function _encodeXChainDepositPayload(
        uint256 _destChainId,
        uint256 _pid,
        uint256 _valueUSDC,
        uint256 _weeksCommitted,
        uint256 _maxMarketMovement,
        address _originWallet,
        bytes memory _destWallet
    ) internal view returns (bytes memory payload) {
        if (chainTypes[_destChainId] == 0) {
            // Destination chain is an EVM chain

            // Calculate method signature
            bytes4 _sig = this.receiveXChainDepositRequest.selector;
            // Calculate abi encoded bytes for input args
            bytes memory _inputs = abi.encode(
                _pid,
                _valueUSDC,
                _weeksCommitted,
                _maxMarketMovement,
                abi.encodePacked(_originWallet), // Convert address to bytes
                _bytesToAddress(_destWallet) // Decode bytes to address
            );
            // Concatenate bytes of signature and inputs
            payload = bytes.concat(_sig, _inputs);
        }

        require(payload.length > 0, "Invalid xchain payload");
    }

    /* Sending */

    /// @notice Prepares and sends a cross chain deposit request. Takes care of necessary financial ops (transfer/locking USDC)
    /// @dev Requires appropriate fee to be paid via msg.value (use checkXChainDepositFee() above)
    /// @param _zorroChainId The Zorro Chain ID (not the LayerZero one)
    /// @param _pid The pool ID on the remote chain
    /// @param _valueUSDC The amount of USDC to deposit
    /// @param _weeksCommitted Number of weeks to commit to a vault
    /// @param _maxMarketMovement Acceptable degree of slippage on any transaction (e.g. 950 = 5%, 990 = 1% etc.)
    /// @param _destWallet A valid address on the remote chain that can claim ownership
    function sendXChainDepositRequest(
        uint256 _zorroChainId,
        uint256 _pid,
        uint256 _valueUSDC,
        uint256 _weeksCommitted,
        uint256 _maxMarketMovement,
        bytes memory _destWallet
    ) external payable nonReentrant {
        // Require funds to be submitted with this message
        require(msg.value > 0, "No fees submitted");

        // Transfer USDC into this contract
        IERC20Upgradeable(defaultStablecoin).safeTransferFrom(
            msg.sender,
            address(this),
            _valueUSDC
        );

        // Check balances
        uint256 _balUSDC = IERC20Upgradeable(defaultStablecoin).balanceOf(
            address(this)
        );

        // Generate payload
        bytes memory _payload = _encodeXChainDepositPayload(
            _zorroChainId,
            _pid,
            _balUSDC,
            _weeksCommitted,
            _maxMarketMovement,
            msg.sender,
            _destWallet
        );

        // Get the destination contract address on the remote chain
        bytes memory _dstContract = controllerContractsMap[_zorroChainId];

        // Call stargate to initiate bridge
        _callStargateSwap(
            StargateSwapPayload({
                chainId: _zorroChainId,
                qty: _balUSDC,
                dstContract: _dstContract,
                payload: _payload,
                maxMarketMovement: _maxMarketMovement
            })
        );
    }

    /* Receiving */

    /// @notice Dummy func to allow .selector call above and guarantee typesafety for abi calls.
    /// @dev Should never ever be actually called.
    function receiveXChainDepositRequest(
        uint256 _pid,
        uint256 _valueUSDC,
        uint256 _weeksCommitted,
        uint256 _maxMarketMovement,
        bytes memory _originAccount,
        address _destAccount
    ) public {
        // Revert to make sure this function never gets called
        require(false, "illegal dummy func call");

        // But still include the function call here anyway to satisfy type safety requirements in case there is a change
        _receiveXChainDepositRequest(
            _pid,
            _valueUSDC,
            _weeksCommitted,
            block.timestamp,
            _maxMarketMovement,
            _originAccount,
            _destAccount
        );
    }

    /// @notice Receives a cross chain deposit request from the contract layer of the XchainEndpoint contract
    /// @dev For params, see _depositFullService() function declaration above
    /// @param _pid The pool ID on the remote chain
    /// @param _valueUSDC The amount of USDC to deposit
    /// @param _weeksCommitted Number of weeks to commit to a vault
    /// @param _maxMarketMovement Acceptable degree of slippage on any transaction (e.g. 950 = 5%, 990 = 1% etc.)
    /// @param _originAccount The address on the origin chain to associate the deposit with (mandatory)
    /// @param _destAccount The address on the current chain to additionally associate the deposit with (allows on-chain withdrawals of the deposit) (if not provided, will truncate origin address to uint160 i.e. Solidity address type)
    function _receiveXChainDepositRequest(
        uint256 _pid,
        uint256 _valueUSDC,
        uint256 _weeksCommitted,
        uint256 _vaultEnteredAt,
        uint256 _maxMarketMovement,
        bytes memory _originAccount,
        address _destAccount
    ) internal virtual {
        // Approve spending
        IERC20Upgradeable(defaultStablecoin).safeIncreaseAllowance(
            currentChainController,
            _valueUSDC
        );
        
        // Call deposit function
        IZorroControllerInvestment(currentChainController)
            .depositFullServiceFromXChain(
                _pid,
                _destAccount,
                _originAccount,
                _valueUSDC,
                _weeksCommitted,
                _vaultEnteredAt,
                _maxMarketMovement
            );
    }
}
