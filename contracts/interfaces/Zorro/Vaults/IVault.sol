// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/* For interacting with our own Vaults */
interface IVault {
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
    function token0PriceFeed() external view returns (AggregatorV3Interface);
    function token1PriceFeed() external view returns (AggregatorV3Interface);
    function earnTokenPriceFeed() external view returns (AggregatorV3Interface);
    function earnedToToken0Path(uint256 _index) external view returns (address);
    function earnedToToken1Path(uint256 _index) external view returns (address);
    
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
