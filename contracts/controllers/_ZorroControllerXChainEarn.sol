// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./_ZorroControllerXChain.sol";

contract ZorroControllerXChainEarn is ZorroControllerXChain {
    /* Libraries */
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /* Modifiers */

    /// @notice Only can be called from a registered vault
    /// @param _pid The pool ID
    modifier onlyRegisteredVault(uint256 _pid) {
        require(_msgSender() == poolInfo[_pid].vault, "only reg vault");
        _;
    }

    /* Events */
    event XChainDistributeEarnings(
        uint256 indexed _remoteChainId,
        uint256 indexed _buybackAmountUSDC,
        uint256 indexed _revShareAmountUSDC
    );

    event RemovedSlashedRewards(
        uint256 indexed _amountZOR
    );

    /* State */
    uint256 public accumulatedSlashedRewards; // Accumulated ZOR rewards that need to be minted in batch on the home chain. Should reset to zero periodically

    /* Fees */

    /// @notice Checks to see how much a cross chain earnings distribution will cost
    /// @param _amountUSDCBuyback Amount of USDC to buy back
    /// @param _amountUSDCRevShare Amount of USDC to rev share with ZOR single staking vault
    /// @param _accSlashedRewards Accumulated slashed rewards on chain
    /// @return uint256 Quantity of native token as fees
    /// @param _maxMarketMovement factor to account for max market movement/slippage.
    function checkXChainDistributeEarningsFee(
        uint256 _amountUSDCBuyback,
        uint256 _amountUSDCRevShare,
        uint256 _accSlashedRewards,
        uint256 _maxMarketMovement
    ) external view returns (uint256) {
        // Init empty LZ object
        IStargateRouter.lzTxObj memory _lzTxParams;

        // Get payload
        bytes memory _payload = _encodeXChainDistributeEarningsPayload(
            chainId,
            _amountUSDCBuyback,
            _amountUSDCRevShare,
            _accSlashedRewards,
            _maxMarketMovement
        );
        bytes memory _dstContract = abi.encodePacked(homeChainZorroController);

        // Calculate native gas fee and ZRO token fee (Layer Zero token)
        (uint256 _nativeFee,) = IStargateRouter(stargateRouter)
            .quoteLayerZeroFee(
                ZorroChainToLZMap[homeChainId],
                1,
                _dstContract,
                _payload,
                _lzTxParams
            );
        return _nativeFee;
    }

    /* Encoding (payloads) */

    /// @notice Encodes payload for making cross chan earnings distribution request
    /// @param _remoteChainId Zorro chain ID of the chain making the distribution request
    /// @param _amountUSDCBuyback Amount in USDC to buy back
    /// @param _amountUSDCRevShare Amount in USDC to rev share with ZOR staking vault
    /// @param _accSlashedRewards Accumulated slashed rewards on chain
    /// @param _maxMarketMovement factor to account for max market movement/slippage.
    /// @return bytes ABI encoded payload
    function _encodeXChainDistributeEarningsPayload(
        uint256 _remoteChainId,
        uint256 _amountUSDCBuyback,
        uint256 _amountUSDCRevShare,
        uint256 _accSlashedRewards,
        uint256 _maxMarketMovement
    ) internal pure returns (bytes memory) {
        // Calculate method signature
        bytes4 _sig = this.receiveXChainDistributionRequest.selector;
        // Calculate abi encoded bytes for input args
        bytes memory _inputs = abi.encode(
            _remoteChainId,
            _amountUSDCBuyback,
            _amountUSDCRevShare,
            _accSlashedRewards,
            _maxMarketMovement
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

        // Get accumulated ZOR rewards and set value
        uint256 _slashedRewards = _removeSlashedRewards();

        // Generate payload
        bytes memory _payload = _encodeXChainDistributeEarningsPayload(
            chainId,
            _buybackAmountUSDC,
            _revShareAmountUSDC,
            _slashedRewards,
            _maxMarketMovement
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
        uint256 _amountUSDCRevShare,
        uint256 _accSlashedRewards,
        uint256 _maxMarketMovement
    ) public {
        // Revert to make sure this function never gets called
        revert("illegal dummy func call");

        // But still include the function call here anyway to satisfy type safety requirements in case there is a change
        _receiveXChainDistributionRequest(
            _remoteChainId,
            _amountUSDCBuyback,
            _amountUSDCRevShare,
            _accSlashedRewards,
            _maxMarketMovement
        );
    }

    /// @notice Receives an authorized request from remote chains to perform earnings fee distribution events, such as: buyback + LP + burn, and revenue share
    /// @param _remoteChainId The Zorro chain ID of the chain that this request originated from
    /// @param _amountUSDCBuyback The amount in USDC that should be minted for LP + burn
    /// @param _amountUSDCRevShare The amount in USDC that should be minted for revenue sharing with ZOR stakers
    /// @param _accSlashedRewards Accumulated slashed rewards on chain
    /// @param _maxMarketMovement factor to account for max market movement/slippage.
    function _receiveXChainDistributionRequest(
        uint256 _remoteChainId,
        uint256 _amountUSDCBuyback,
        uint256 _amountUSDCRevShare,
        uint256 _accSlashedRewards,
        uint256 _maxMarketMovement
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
        _buybackOnChain(_buybackAmount, _maxMarketMovement);

        /* Rev share */
        // (Account for slippage)
        uint256 _revShareAmount = _balUSDC.mul(_amountUSDCRevShare).div(
            _totalUSDC
        );
        _revShareOnChain(_revShareAmount, _maxMarketMovement);

        // Emit event
        emit XChainDistributeEarnings(
            _remoteChainId,
            _buybackAmount,
            _revShareAmount
        );

        // Award slashed rewards to ZOR stakers
        if (_accSlashedRewards > 0) {
            _awardSlashedRewardsToStakers(_accSlashedRewards);
        }
    }

    /* Slashed rewards */

    /// @notice Called by oracle to remove slashed ZOR rewards and reset
    /// @return _slashedZORRewards The amount of accumulated slashed ZOR rewards
    function _removeSlashedRewards()
        internal
        returns (uint256 _slashedZORRewards)
    {
        // Store current rewards amount
        _slashedZORRewards = accumulatedSlashedRewards;

        // Emit success event
        emit RemovedSlashedRewards(_slashedZORRewards);

        // Reset accumulated rewards
        accumulatedSlashedRewards = 0;
    }

    /// @notice Awards the slashed ZOR rewards from other chains to this (home) chain's ZOR staking vault
    /// @param _slashedZORRewards The amount of accumulated slashed ZOR rewards
    function _awardSlashedRewardsToStakers(uint256 _slashedZORRewards)
        internal
    {
        // Mint ZOR and send to ZOR staking vault.
        Zorro(ZORRO).mint(zorroStakingVault, _slashedZORRewards);
    }
}
