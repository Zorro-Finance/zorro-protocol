// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import "../../../../libraries/SafeSwap.sol";

interface IZorroControllerXChainActions {
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

    /* Config */

    function stargateRouter() external returns (address);

    function layerZeroEndpoint() external returns (address);

    function uniRouterAddress() external returns (address);

    /* Functions */

    function bytesToAddress(bytes memory bys)
        external
        pure
        returns (address addr);

    function extractParamsPayload(bytes calldata _payloadWithSig)
        external
        pure
        returns (bytes memory paramsPayload);

    function checkXChainDepositFee(
        uint16 _lzChainId,
        bytes memory _dstContract,
        bytes memory _payload,
        uint256 _dstGasForCall
    ) external view returns (uint256 nativeFee);

    function encodeXChainDepositPayload(
        uint256 _vid,
        uint256 _valueUSD,
        uint256 _weeksCommitted,
        uint256 _maxMarketMovement,
        address _originWallet,
        bytes memory _destWallet
    ) external view returns (bytes memory payload);

    function checkXChainDistributeEarningsFee(
        uint16 _lzChainId,
        address _homeChainZorroController,
        bytes memory _payload
    ) external view returns (uint256 nativeFee);

    function encodeXChainDistributeEarningsPayload(
        uint256 _remoteChainId,
        uint256 _amountUSDBuyback,
        uint256 _amountUSDRevShare,
        uint256 _accSlashedRewards,
        uint256 _maxMarketMovement
    ) external pure returns (bytes memory);

    function distributeEarnings(
        address _stablecoin,
        uint256 _amountUSDBuyback,
        uint256 _amountUSDRevShare,
        uint256 _maxMarketMovement,
        EarningsBuybackParams memory _buybackParams,
        EarningsRevshareParams memory _revshareParams
    ) external;

    function checkXChainWithdrawalFee(
        uint16 _lzChainId,
        bytes memory _payload,
        uint256 _gasForDestinationLZReceive
    ) external view returns (uint256 nativeFee);

    function getLZAdapterParamsForWithdraw(uint256 _gasForDestinationLZReceive)
        external
        pure
        returns (bytes memory);

    function encodeXChainWithdrawalPayload(
        uint256 _originChainId,
        bytes memory _originAccount,
        uint256 _vid,
        uint256 _trancheId,
        uint256 _maxMarketMovement
    ) external pure returns (bytes memory);

    function checkXChainRepatriationFee(
        uint16 _lzChainId,
        bytes memory _dstContract,
        bytes memory _payload
    ) external view returns (uint256 nativeFee);

    function encodeXChainRepatriationPayload(
        uint256 _originChainId,
        uint256 _vid,
        uint256 _trancheId,
        bytes memory _originRecipient,
        uint256 _rewardsDue
    ) external pure returns (bytes memory);

    function safeSwap(SafeSwapUni.SafeSwapParams memory _swapParams) external;

    function joinPool(
        address _token0,
        address _token1,
        uint256 _token0Amt,
        uint256 _token1Amt,
        uint256 _maxMarketMovementAllowed,
        address _recipient
    ) external;
}
