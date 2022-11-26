// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/* For interacting with our own Vaults */
interface IVault {
    /* Struct */

    struct VaultBaseInit {
        VaultConfig config;
        VaultAddresses keyAddresses;
        VaultSwapPaths swapPaths;
        VaultFees fees;
        VaultPriceFeeds priceFeeds;
    }

    struct VaultConfig {
        uint256 pid;
        bool isHomeChain;
        bool isFarmable;
    }

    struct VaultAddresses {
        address govAddress;
        address zorroControllerAddress;
        address zorroXChainController;
        address ZORROAddress;
        address zorroStakingVault;
        address wantAddress;
        address token0Address;
        address token1Address;
        address earnedAddress;
        address farmContractAddress;
        address rewardsAddress;
        address poolAddress;
        address uniRouterAddress;
        address zorroLPPool;
        address zorroLPPoolOtherToken;
        address defaultStablecoin;
    }

    struct VaultSwapPaths {
        address[] earnedToZORROPath;
        address[] earnedToToken0Path;
        address[] earnedToToken1Path;
        address[] stablecoinToToken0Path;
        address[] stablecoinToToken1Path;
        address[] earnedToZORLPPoolOtherTokenPath;
        address[] earnedToStablecoinPath;
        address[] stablecoinToZORROPath;
        address[] stablecoinToLPPoolOtherTokenPath;
    }

    struct VaultFees {
        uint256 controllerFee;
        uint256 buyBackRate;
        uint256 revShareRate;
        uint256 entranceFeeFactor;
        uint256 withdrawFeeFactor;
    }

    struct VaultPriceFeeds {
        address token0PriceFeed;
        address token1PriceFeed;
        address earnTokenPriceFeed;
        address ZORPriceFeed;
        address lpPoolOtherTokenPriceFeed;
        address stablecoinPriceFeed;
    }

    /* Events */

    event SetSettings(
        uint256 _entranceFeeFactor,
        uint256 _withdrawFeeFactor,
        uint256 _controllerFee,
        uint256 _buyBackRate,
        uint256 _revShareRate
    );
    event SetGov(address _govAddress);
    event SetOnlyGov(bool _onlyGov);
    event SetUniRouterAddress(address _uniRouterAddress);
    event SetRewardsAddress(address _rewardsAddress);
    event Buyback(uint256 indexed _amount);
    event RevShare(uint256 indexed _amount);

    /* Functions */

    // Config variables
    function wantAddress() external view returns (address);
    function poolAddress() external view returns (address);
    function earnedAddress() external view returns (address);
    function token0Address() external view returns (address);
    function token1Address() external view returns (address);
    function swapPaths(address _startToken, address _endToken, uint256 _index) external view returns (address); 
    function swapPathLength(address _startToken, address _endToken) external view returns (uint16);
    function priceFeeds(address _token) external view returns (AggregatorV3Interface);
    
    // Total want tokens managed by strategy
    function wantLockedTotal() external view returns (uint256);

    // Sum of all shares of users to wantLockedTotal
    function sharesTotal() external view returns (uint256);

    // Deposits
    function exchangeUSDForWantToken(
        uint256 _amountUSD,
        uint256 _maxMarketMovementAllowed
    ) external returns (uint256);

    function depositWantToken(
        uint256 _wantAmt
    ) external returns (uint256);

    // Withdrawals
    function withdrawWantToken(
        uint256 _wantAmt
    ) external returns (uint256);

    function exchangeWantTokenForUSD(
        uint256 _amount,
        uint256 _maxMarketMovementAllowed
    ) external returns (uint256);

    // Compounding
    function earn(
        uint256 _maxMarketMovementAllowed
    ) external;

    function farm() external;

    // Access
    function pause() external;

    function unpause() external;

    // Transfer ERC20 tokens on the Vault back to the owner, if necessary
    function inCaseTokensGetStuck(
        address _token,
        uint256 _amount,
        address _to
    ) external;
}
