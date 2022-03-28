// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;


struct PriceData {
    uint256 token0; // Value of Token 0 in USD, times 1e12
    uint256 token1; // Value of Token 1 in USD, times 1e12
    uint256 earnToken; // Value of Earn token in USD, times 1e12
    uint256 lpPoolToken0; // Value of LP Pool Token 0 in USD, times 1e12
    uint256 lpPoolToken1; // Value of LP Pool Token 1 in USD, times 1e12
    uint256 zorroToken; // Value of Zorro Token in USD, times 1e12
    uint256 tokenUSDC; // Value of USDC Token in USD, times 1e12
}


/* For interacting with our own Vaults */
interface IVault {
    // Total want tokens managed by strategy
    function wantLockedTotal() external view returns (uint256);

    // Sum of all shares of users to wantLockedTotal
    function sharesTotal() external view returns (uint256);

    // Deposits
    function exchangeUSDForWantToken(
        uint256 _amountUSDC,
        uint256 _maxMarketMovementAllowed,
        PriceData calldata _priceData
    ) external returns (uint256);

    function depositWantToken(address _account, uint256 _wantAmt) external returns (uint256);

    // Withdrawals
    function withdrawWantToken(address _account, bool _harvestOnly) external returns (uint256);

    function exchangeWantTokenForUSD(
        uint256 _amount,
        uint256 _maxMarketMovementAllowed,
        PriceData calldata _priceData
    ) external returns (uint256);

    // Compounding
    function earn(
        uint256 _maxMarketMovementAllowed,
        PriceData calldata _priceData
    ) external;

    // Transfer ERC20 tokens on the Vault back to the owner, if necessary
    function inCaseTokensGetStuck(
        address _token,
        uint256 _amount,
        address _to
    ) external;
}