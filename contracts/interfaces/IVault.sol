// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;


/* For interacting with our own Vaults */
interface IVault {
    // Total want tokens managed by strategy
    function wantLockedTotal() external view returns (uint256);

    // Sum of all shares of users to wantLockedTotal
    function sharesTotal() external view returns (uint256);

    // Deposits
    function exchangeUSDForWantToken(
        uint256 _amountUSDC,
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
