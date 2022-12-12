// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import "../../../../libraries/SafeSwap.sol";

interface IVaultActions {
    /* Structs */

    struct ExitPoolParams {
        address token0;
        address token1;
        address poolAddress;
        address lpTokenAddress;
    }

    struct DistributeEarningsParams {
        address ZORROAddress;
        address rewardsAddress;
        address stablecoin;
        address zorroStakingVault;
        address zorroLPPoolOtherToken;
        AggregatorV3Interface ZORPriceFeed;
        AggregatorV3Interface lpPoolOtherTokenPriceFeed;
        AggregatorV3Interface stablecoinPriceFeed;
        address[] stablecoinToZORROPath;
        address[] stablecoinToZORLPPoolOtherTokenPath;
        uint16 controllerFeeBP; // BP = basis points
        uint16 buybackBP;
        uint16 revShareBP;
        bool isHomeChain;
    }

    struct BuybackBurnLPParams {
        address stablecoin;
        address ZORROAddress;
        address zorroLPPoolOtherToken;
        address[] stablecoinToZORROPath;
        address[] stablecoinToZORLPPoolOtherTokenPath;
        AggregatorV3Interface stablecoinPriceFeed;
        AggregatorV3Interface ZORPriceFeed;
        AggregatorV3Interface lpPoolOtherTokenPriceFeed;
    }

    struct RevShareParams {
        address stablecoin;
        address ZORROAddress;
        address zorroStakingVault;
        address[] stablecoinToZORROPath;
        AggregatorV3Interface stablecoinPriceFeed;
        AggregatorV3Interface ZORPriceFeed;
    }

    /* Config */

    function uniRouterAddress() external view returns (address);

    function burnAddress() external view returns (address);

    /* Functions */

    function joinPool(
        address _token0,
        address _token1,
        uint256 _token0Amt,
        uint256 _token1Amt,
        uint256 _maxMarketMovementAllowed,
        address _recipient
    ) external;

    function exitPool(
        uint256 _amountLP,
        uint256 _maxMarketMovementAllowed,
        address _recipient,
        ExitPoolParams memory _exitPoolParams
    ) external;

    function safeSwap(SafeSwapUni.SafeSwapParams memory _swapParams) external;

    function distributeAndReinvestEarnings(
        uint256 _amount,
        uint256 _maxMarketMovementAllowed,
        DistributeEarningsParams memory _params
    )
        external
        returns (
            uint256 wantRemaining,
            uint256 xChainBuybackAmt,
            uint256 xChainRevShareAmt
        );

    function exchangeUSDForWantToken(
        uint256 _amountUSD,
        uint256 _maxMarketMovementAllowed
    ) external returns (uint256 wantObtained);

    function exchangeWantTokenForUSD(
        uint256 _amount,
        uint256 _maxMarketMovementAllowed
    ) external returns (uint256 usdObtained);

    function unrealizedProfits(address _vault)
        external
        view
        returns (uint256 accumulatedProfit, uint256 harvestableProfit);

    function currentWantEquity(address _vault)
        external
        view
        returns (uint256 positionVal);

    function reversePath(address[] memory _path)
        external
        pure
        returns (address[] memory newPath);
}
