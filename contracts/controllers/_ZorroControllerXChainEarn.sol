// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./_ZorroControllerXChain.sol";

contract ZorroControllerXChainEarn is ZorroControllerXChain {
    /* Libraries */
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /* Events */
    event XChainDistributeEarnings(
        uint256 indexed _remoteChainId,
        uint256 indexed _buybackAmountUSDC,
        uint256 indexed _revShareAmountUSDC
    );

    /* Fees */

    /// @notice Checks to see how much a cross chain earnings distribution will cost
    /// @param _amountUSDCBuyback Amount of USDC to buy back
    /// @param _amountUSDCRevShare Amount of USDC to rev share with ZOR single staking vault
    /// @return uint256 Quantity of native token as fees
    function checkXChainDistributeEarningsFee(
        uint256 _amountUSDCBuyback,
        uint256 _amountUSDCRevShare
    ) external view returns (uint256) {
        // Init empty LZ object
        IStargateRouter.lzTxObj memory _lzTxParams;

        // Get payload
        bytes memory _payload = _encodeXChainDistributeEarningsPayload(
            chainId,
            _amountUSDCBuyback,
            _amountUSDCRevShare
        );
        bytes memory _dstContract = abi.encodePacked(homeChainZorroController);

        // Calculate native gas fee and ZRO token fee (Layer Zero token)
        (uint256 _nativeFee, uint256 _lzFee) = IStargateRouter(stargateRouter)
            .quoteLayerZeroFee(
                ZorroChainToLZMap[homeChainId],
                1,
                _dstContract,
                _payload,
                _lzTxParams
            );
        // TODO: Q: Is it the sum of these fees or just one?
        return _nativeFee.add(_lzFee);
    }

    /* Encoding (payloads) */

    /// @notice Encodes payload for making cross chan earnings distribution request
    /// @param _remoteChainId Zorro chain ID of the chain making the distribution request
    /// @param _amountUSDCBuyback Amount in USDC to buy back
    /// @param _amountUSDCRevShare Amount in USDC to rev share with ZOR staking vault
    /// @return bytes ABI encoded payload
    function _encodeXChainDistributeEarningsPayload(
        uint256 _remoteChainId,
        uint256 _amountUSDCBuyback,
        uint256 _amountUSDCRevShare
    ) internal pure returns (bytes memory) {
        // Calculate method signature
        bytes4 _sig = this.receiveXChainDistributionRequest.selector;
        // Calculate abi encoded bytes for input args
        bytes memory _inputs = abi.encode(
            _remoteChainId,
            _amountUSDCBuyback,
            _amountUSDCRevShare
        );
        // Concatenate bytes of signature and inputs
        return bytes.concat(_sig, _inputs);
    }

    /* Sending */
    
    /// @notice Sends a request back to the home chain to distribute earnings
    /// @param _pid Pool ID
    /// @param _buybackAmountUSDC Amount in USDC to buy back
    /// @param _revShareAmountUSDC Amount in USDC to revshare w/ ZOR single staking vault
    /// @param _maxMarketMovement Acceptable slippage (950 = 5%, 990 = 1% etc.)
    function sendXChainDistributeEarningsRequest(
        uint256 _pid,
        uint256 _buybackAmountUSDC,
        uint256 _revShareAmountUSDC,
        uint256 _maxMarketMovement
    ) public payable nonReentrant onlyRegisteredVault(_pid) {
        // Require funds to be submitted with this message
        require(msg.value > 0, "No fees submitted");

        // Calculate total USDC to transfer
        uint256 _totalUSDC = _buybackAmountUSDC.add(_revShareAmountUSDC);

        // Allow this contract to spend USDC
        IERC20(defaultStablecoin).safeIncreaseAllowance(
            address(this),
            _totalUSDC
        );

        // Transfer USDC into this contract
        IERC20(defaultStablecoin).safeTransferFrom(
            msg.sender,
            address(this),
            _totalUSDC
        );

        // Check balances
        uint256 _balUSDC = IERC20(defaultStablecoin).balanceOf(address(this));

        // Generate payload
        bytes memory _payload = _encodeXChainDistributeEarningsPayload(
            chainId,
            _buybackAmountUSDC,
            _revShareAmountUSDC
        );

        // Get the destination contract address on the remote chain
        bytes memory _dstContract = controllerContractsMap[chainId];

        // Call stargate to initiate bridge
        _callStargateSwap(
            StargateSwapPayload({
                chainId: homeChainId,
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
    function receiveXChainDistributionRequest(
        uint256 _remoteChainId,
        uint256 _amountUSDCBuyback,
        uint256 _amountUSDCRevShare
    ) public {
        // Revert to make sure this function never gets called
        revert("illegal dummy func call");

        // But still include the function call here anyway to satisfy type safety requirements in case there is a change
        _receiveXChainDistributionRequest(
            _remoteChainId,
            _amountUSDCBuyback,
            _amountUSDCRevShare
        );
    }

    /// @notice Receives an authorized request from remote chains to perform earnings fee distribution events, such as: buyback + LP + burn, and revenue share
    /// @param _remoteChainId The Zorro chain ID of the chain that this request originated from
    /// @param _amountUSDCBuyback The amount in USDC that should be minted for LP + burn
    /// @param _amountUSDCRevShare The amount in USDC that should be minted for revenue sharing with ZOR stakers
    function _receiveXChainDistributionRequest(
        uint256 _remoteChainId,
        uint256 _amountUSDCBuyback,
        uint256 _amountUSDCRevShare
    ) internal {
        // Total USDC to perform operations
        uint256 _totalUSDC = _amountUSDCBuyback.add(_amountUSDCRevShare);

        // Determine new USDC balances
        uint256 _balUSDC = IERC20(defaultStablecoin).balanceOf(address(this));

        /* Buyback */
        // (Account for slippage)
        uint256 _buybackAmount = _balUSDC.mul(_amountUSDCBuyback).div(
            _totalUSDC
        );
        _buybackOnChain(_buybackAmount);

        /* Rev share */
        // (Account for slippage)
        uint256 _revShareAmount = _balUSDC.mul(_amountUSDCRevShare).div(
            _totalUSDC
        );
        _revShareOnChain(_revShareAmount);

        // Emit event
        emit XChainDistributeEarnings(
            _remoteChainId,
            _buybackAmount,
            _revShareAmount
        );
    }
}
