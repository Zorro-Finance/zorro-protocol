// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../../interfaces/Stargate/IStargateRouter.sol";

import "../../interfaces/LayerZero/ILayerZeroEndpoint.sol";

import "../../interfaces/IZorroControllerXChain.sol";

import "../../libraries/SafeSwap.sol";

import "../../libraries/PriceFeed.sol";

// TODO: Create interface for this contract

contract ZorroControllerXChainActions is OwnableUpgradeable {
    /* Libraries */

    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeSwapUni for IAMMRouter02;
    using PriceFeed for AggregatorV3Interface;

    /* Constructor */

    /// @notice Constructor
    /// @param _stargateRouter Address of Stargate router
    /// @param _lzEndpoint Address of LayerZero endpoint for this chain
    /// @param _uniRouter Address of Uniswap style router for swaps
    function initialize(
        address _stargateRouter,
        address _lzEndpoint,
        address _uniRouter
    ) public initializer {
        stargateRouter = _stargateRouter;
        layerZeroEndpoint = _lzEndpoint;
        uniRouterAddress = _uniRouter;
    }

    /* Structs */

    struct EarningsBuybackParams {
        address stablecoin;
        address ZORRO;
        address zorroLPPoolOtherToken;
        address burnAddress;
        AggregatorV3Interface priceFeedStablecoin;
        AggregatorV3Interface priceFeedZOR;
        AggregatorV3Interface priceFeedLPPoolOtherToken;
        address[] stablecoinToZorroPath;
        address[] stablecoinToZorroLPPoolOtherTokenPath;
    }

    struct EarningsRevshareParams {
        address stablecoin;
        address ZORRO;
        address zorroLPPoolOtherToken;
        address zorroStakingVault;
        AggregatorV3Interface priceFeedStablecoin;
        AggregatorV3Interface priceFeedZOR;
        address[] stablecoinToZorroPath;
    }

    /* State */

    address public stargateRouter;
    address public layerZeroEndpoint;
    address public uniRouterAddress;

    /* Utilities */

    /// @notice Decodes bytes array to address
    /// @param bys Bytes array
    /// @return addr Address value
    function bytesToAddress(bytes memory bys)
        public
        pure
        returns (address addr)
    {
        assembly {
            addr := mload(add(bys, 20))
        }
    }

    /// @notice Removes function signature from ABI encoded payload
    /// @param _payloadWithSig ABI encoded payload with function selector
    /// @return paramsPayload Payload with params only
    function extractParamsPayload(bytes calldata _payloadWithSig)
        public
        pure
        returns (bytes memory paramsPayload)
    {
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
        (nativeFee, ) = IStargateRouter(stargateRouter).quoteLayerZeroFee(
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
        bytes4 _sig = IZorroControllerXChainDeposit
            .receiveXChainDepositRequest
            .selector;

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
        (nativeFee, ) = IStargateRouter(stargateRouter).quoteLayerZeroFee(
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
        bytes4 _sig = IZorroControllerXChainEarn
            .receiveXChainDistributionRequest
            .selector;
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

    // TODO: For all controller and vault actions contracts, make sure
    // functions have a modifier that restricts access to controllers and
    // vaults only.

    /// @notice Receives an authorized request from remote chains to perform earnings fee distribution events, such as: buyback + LP + burn, and revenue share
    /// @param _stablecoin Address of the stablecoin to distribute
    /// @param _amountUSDBuyback The amount in USD that should be minted for LP + burn
    /// @param _amountUSDRevShare The amount in USD that should be minted for revenue sharing with ZOR stakers
    /// @param _maxMarketMovement Factor to account for max market movement/slippage.
    /// @param _buybackParams Params to perform buyback distribution
    /// @param _revshareParams Params to perform revenue share distribution
    function distributeEarnings(
        address _stablecoin,
        uint256 _amountUSDBuyback,
        uint256 _amountUSDRevShare,
        uint256 _maxMarketMovement,
        EarningsBuybackParams memory _buybackParams,
        EarningsRevshareParams memory _revshareParams
    ) public {
        // Total USD to perform operations
        uint256 _totalUSD = _amountUSDBuyback + _amountUSDRevShare;

        // Transfer funds IN
        IERC20Upgradeable(_stablecoin).safeTransferFrom(
            msg.sender,
            address(this),
            _totalUSD
        );

        /* Buyback */
        // (Account for slippage)
        uint256 _buybackAmount = (_totalUSD * _amountUSDBuyback) / _totalUSD;
        _buybackOnChain(
            _buybackAmount, 
            _maxMarketMovement,
            _buybackParams
        );

        /* Rev share */
        // (Account for slippage)
        uint256 _revShareAmount = (_totalUSD * _amountUSDRevShare) / _totalUSD;
        _revShareOnChain(
            _revShareAmount, 
            _maxMarketMovement,
            _revshareParams
        );
    }

    /// @notice Adds liquidity to the main ZOR LP pool and burns the resulting LP token
    /// @param _amountUSD Amount of USD to add as liquidity
    /// @param _maxMarketMovement factor to account for max market movement/slippage.
    /// @param _params A EarningsBuybackParams struct
    function _buybackOnChain(
        uint256 _amountUSD,
        uint256 _maxMarketMovement,
        EarningsBuybackParams memory _params
    ) internal {
        // Swap to ZOR token
        _safeSwap(
            SafeSwapParams({
                amountIn: _amountUSD / 2,
                priceToken0: _params.priceFeedStablecoin.getExchangeRate(),
                priceToken1: _params.priceFeedZOR.getExchangeRate(),
                token0: _params.stablecoin,
                token1: _params.ZORRO,
                maxMarketMovementAllowed: _maxMarketMovement,
                path: _params.stablecoinToZorroPath,
                destination: address(this)
            })
        );

        // Swap to counterparty token (if not USD)
        if (_params.zorroLPPoolOtherToken != _params.stablecoin) {
            _safeSwap(
                SafeSwapParams({
                    amountIn: _amountUSD / 2,
                    priceToken0: _params.priceFeedStablecoin.getExchangeRate(),
                    priceToken1: _params
                        .priceFeedLPPoolOtherToken
                        .getExchangeRate(),
                    token0: _params.stablecoin,
                    token1: _params.zorroLPPoolOtherToken,
                    maxMarketMovementAllowed: _maxMarketMovement,
                    path: _params.stablecoinToZorroLPPoolOtherTokenPath,
                    destination: address(this)
                })
            );
        }

        // Calc balances
        uint256 tokenZORAmt = IERC20Upgradeable(_params.ZORRO).balanceOf(
            address(this)
        );
        uint256 tokenOtherAmt = IERC20Upgradeable(_params.zorroLPPoolOtherToken)
            .balanceOf(address(this));

        // Add liquidity
        _joinPool(
            _params.ZORRO,
            _params.zorroLPPoolOtherToken,
            tokenZORAmt,
            tokenOtherAmt,
            _maxMarketMovement,
            _params.burnAddress
        );
    }

    /// @notice Pays the ZOR single staking pool the revenue share amount specified
    /// @param _amountUSD Amount of USD to send as ZOR revenue share
    /// @param _maxMarketMovement factor to account for max market movement/slippage.
    /// @param _params A EarningsRevshareParams struct
    function _revShareOnChain(
        uint256 _amountUSD,
        uint256 _maxMarketMovement,
        EarningsRevshareParams memory _params
    ) internal {
        // Swap to ZOR token and send to Zorro Staking Vault
        _safeSwap(
            SafeSwapParams({
                amountIn: _amountUSD,
                priceToken0: _params.priceFeedStablecoin.getExchangeRate(),
                priceToken1: _params.priceFeedZOR.getExchangeRate(),
                token0: _params.stablecoin,
                token1: _params.ZORRO,
                maxMarketMovementAllowed: _maxMarketMovement,
                path: _params.stablecoinToZorroPath,
                destination: _params.zorroStakingVault
            })
        );
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
        (nativeFee, ) = ILayerZeroEndpoint(layerZeroEndpoint).estimateFees(
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
        bytes4 _sig = IZorroControllerXChainWithdraw
            .receiveXChainWithdrawalRequest
            .selector;

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
        (nativeFee, ) = IStargateRouter(stargateRouter).quoteLayerZeroFee(
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
        bytes4 _sig = IZorroControllerXChainWithdraw
            .receiveXChainRepatriationRequest
            .selector;

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

    /* Uni router operations: Swaps, Add/remove liquidity etc. */

    /// @notice Safely swaps tokens using the most suitable protocol based on token
    /// @dev NOTE: Caller must approve tokens for spending beforehand
    /// @param _swapParams SafeSwapParams for swap
    function safeSwap(SafeSwapParams memory _swapParams) public {
        // Transfer tokens in
        IERC20Upgradeable(_swapParams.token0).safeTransferFrom(
            msg.sender,
            address(this),
            _swapParams.amountIn
        );

        // Call internal swap function
        _safeSwap(_swapParams);
    }

    /// @notice Internal function for swapping
    /// @dev Does not transfer tokens to this contract (assumes they are already here)
    /// @param _swapParams SafeSwapParams for swap
    function _safeSwap(SafeSwapParams memory _swapParams) internal {
        // Allowance
        IERC20Upgradeable(_swapParams.token0).safeIncreaseAllowance(
            uniRouterAddress,
            _swapParams.amountIn
        );

        // Get decimal info
        uint8[] memory _decimals = new uint8[](2);
        _decimals[0] = ERC20Upgradeable(_swapParams.token0).decimals();
        _decimals[1] = ERC20Upgradeable(_swapParams.token1).decimals();

        // Determine exchange rates using price feed oracle
        uint256[] memory _priceTokens = new uint256[](2);
        _priceTokens[0] = _swapParams.priceToken0;
        _priceTokens[1] = _swapParams.priceToken1;

        // Swap
        IAMMRouter02(uniRouterAddress).safeSwap(
            _swapParams.amountIn,
            _priceTokens,
            _swapParams.maxMarketMovementAllowed,
            _swapParams.path,
            _decimals,
            _swapParams.destination,
            block.timestamp + 600
        );
    }

    /// @notice Adds liquidity to the pool of this contract
    /// @dev NOTE: Requires spending approval by caller
    /// @param _token0 The address of Token0
    /// @param _token1 The address of Token1
    /// @param _token0Amt Quantity of Token0 to add
    /// @param _token1Amt Quantity of Token1 to add
    /// @param _maxMarketMovementAllowed The max slippage allowed for swaps. 1000 = 0 %, 995 = 0.5%, etc.
    /// @param _recipient The recipient of the LP token
    function joinPool(
        address _token0,
        address _token1,
        uint256 _token0Amt,
        uint256 _token1Amt,
        uint256 _maxMarketMovementAllowed,
        address _recipient
    ) public {
        // Transfer funds in
        IERC20Upgradeable(_token0).safeTransferFrom(
            msg.sender,
            address(this),
            _token0Amt
        );
        IERC20Upgradeable(_token1).safeTransferFrom(
            msg.sender,
            address(this),
            _token1Amt
        );

        // Call internal function to add liquidity
        _joinPool(
            _token0,
            _token1,
            _token0Amt,
            _token1Amt,
            _maxMarketMovementAllowed,
            _recipient
        );
    }

    /// @notice Internal function for adding liquidity to the pool of this contract
    /// @dev NOTE: Unlike public function, does not transfer tokens into contract (assumes already tokens already present)
    /// @param _token0 The address of Token0
    /// @param _token1 The address of Token1
    /// @param _token0Amt Quantity of Token0 to add
    /// @param _token1Amt Quantity of Token1 to add
    /// @param _maxMarketMovementAllowed The max slippage allowed for swaps. 1000 = 0 %, 995 = 0.5%, etc.
    /// @param _recipient The recipient of the LP token
    function _joinPool(
        address _token0,
        address _token1,
        uint256 _token0Amt,
        uint256 _token1Amt,
        uint256 _maxMarketMovementAllowed,
        address _recipient
    ) internal {
        // Approve spending
        IERC20Upgradeable(_token0).safeIncreaseAllowance(
            uniRouterAddress,
            _token0Amt
        );
        IERC20Upgradeable(_token1).safeIncreaseAllowance(
            uniRouterAddress,
            _token1Amt
        );

        // Add liquidity
        IAMMRouter02(uniRouterAddress).addLiquidity(
            _token0,
            _token1,
            _token0Amt,
            _token1Amt,
            (_token0Amt * _maxMarketMovementAllowed) / 1000,
            (_token1Amt * _maxMarketMovementAllowed) / 1000,
            _recipient,
            block.timestamp + 600
        );
    }
}
